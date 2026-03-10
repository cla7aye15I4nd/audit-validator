import type { ICommand, ICommandResult } from "@kadena/client";
import { Pact, createClient } from "@kadena/client";
import { config } from "./config.js";
import { signTransaction } from "./util/sign-txn.js";

const pairAccount = "7iQ1F7MYvQ6wt6wSfjT0aChgOhhRAG_2IqOtBqAQ-pA";

export async function createAccount(): Promise<ICommandResult> {
	const pactClient = createClient(`${config.apiHost}${config.networkId}/chain/${config.chainId}/pact`);

	const pactBuilder = Pact.builder
		.execution(
			`(n_82274f03ce7df5c0ea6c3d5766b535a7a748a552.sushi-exchange.add-liquidity coin kdlaunch.kdswap-token  1.0 100.0 0.0 0.0 "k:${config.pubKey}" "k:${config.pubKey}" (read-keyset "ks"))`
		)
		.addSigner(config.pubKey, (signFor) => [
			signFor("coin.GAS"),
			signFor("coin.TRANSFER", `k:${config.pubKey}`, `${pairAccount}`, { decimal: "1.0" }),
			signFor("kdlaunch.kdswap-token.TRANSFER", `k:${config.pubKey}`, `${pairAccount}`, { decimal: "100.0" }),
		])
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
	console.error(error);
	process.exitCode = 1;
});

// Deployed contract: {
//   gas: 1399,
//   result: {
//     status: 'success',
//     data: { amount0: 5, amount1: 500, supply: 50, liquidity: 49.9 }
//   },
//   reqKey: 'uAOzH_-VXi_UbOGQVrta5wAQm7eu85m6Pw8MfuOfcmw',
//   logs: 'V6SWzqtUgf4_C6fOjDpaQAA0xZ8zg5kamGcNJDDNdyY',
