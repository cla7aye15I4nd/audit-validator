import type { ICommand, ICommandResult } from "@kadena/client";
import { Pact, createClient } from "@kadena/client";

import { config } from "./config.js";
import { signTransaction } from "./util/sign-txn.js";

export async function createAccount(): Promise<ICommandResult> {
	const pactClient = createClient(`${config.apiHost}${config.networkId}/chain/${config.chainId}/pact`);

	const pactBuilder = Pact.builder
		.execution(`(kdlaunch.kdswap-token.create-account "k:${config.pubKey}" (read-keyset "ks"))`)
		.addSigner(config.pubKey, (signFor) => [signFor("coin.GAS")])
		.addData("ks", {
			keys: [config.pubKey],
			pred: "keys-all",
		})
		.setMeta({
			chainId: config.chainId,
			gasLimit: config.gasLimit,
			gasPrice: config.gasPrice,
			senderAccount: `k:${config.pubKey}`,
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

createAccount().catch((error) => {
	console.error("Error in createAccount:", error);
	process.exit(1);
});
