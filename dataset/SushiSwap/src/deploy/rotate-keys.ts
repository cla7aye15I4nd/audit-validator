import { config } from "./config.js";
import { createClient, Pact } from "@kadena/client";
import { signTransaction } from "./util/sign-txn.js";
import type { ICommand, ICommandResult } from "@kadena/client";

const ns = process.env.NS;

const newAdminKeyset = "";

async function update(): Promise<ICommandResult> {
	console.log(config);
	if (!config.pubKey || !config.secretKey) {
		throw new Error("Public key and secret key must be provided in the environment variables.");
	}
	if (!newAdminKeyset) {
		throw new Error("New admin keyset must be provided.");
	}

	const pactClient = createClient(`${config.apiHost}${config.networkId}/chain/${config.chainId}/pact`);

	const pactBuilder = Pact.builder
		.execution(`(namespace "${ns}") (define-keyset "${ns}.admin-keyset" (read-keyset 'admin-keyset))`)
		.addSigner(config.pubKey)
		.setMeta({
			chainId: config.chainId,
			gasLimit: config.gasLimit,
			gasPrice: config.gasPrice,
			senderAccount: `k:${config.pubKey}`,
		})
		.addData("admin-keyset", {
			keys: [newAdminKeyset],
			pred: "keys-all",
		})
		.setNetworkId(config.networkId);

	const tx = pactBuilder.createTransaction();

	try {
		const signedTx = (await signTransaction(tx)) as ICommand;
		const preflightResult = await pactClient.preflight(signedTx);
		console.log("Preflight result:", JSON.stringify(preflightResult, null, 2));

		if (preflightResult.result.status === "failure") {
			console.error("Preflight failed:", preflightResult.result.error);
			return preflightResult;
		}

		const res = await pactClient.submit(signedTx);
		console.log("Deploy request sent", res);
		const result = await pactClient.pollOne(res);
		if (result.result.status === "failure") {
			console.error("Deploy failed:", result.result.error);
		}
		console.log("Deployed contract:", result);
		return result;
	} catch (error) {
		console.error("Error deploying contract:", error);
		throw error;
	}
}

update()
	.catch((error) => {
		console.error("Error deploying utilities:", error);
		process.exit(1);
	})
	.finally(() => {
		console.log("Utilities deployment completed.");
	});
