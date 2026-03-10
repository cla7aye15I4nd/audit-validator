import type { ICommand, ICommandResult } from "@kadena/client";
import { Pact, createClient } from "@kadena/client";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import dotenv from "dotenv";
import { config } from "../config.js";
import { signTransaction } from "./sign-txn.js";

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export interface DeployConfig {
	contractName: string;
	data?: Record<string, any>;
	initializeCode?: string;
}

export async function deployContract({
	contractName,
	data = {},
	initializeCode = "",
}: DeployConfig): Promise<ICommandResult> {
	console.log(config);
	if (!config.pubKey || !config.secretKey) {
		throw new Error("Public key and secret key must be provided in the environment variables.");
	}

	const pactClient = createClient(`${config.apiHost}${config.networkId}/chain/${config.chainId}/pact`);

	// Read contract code from file
	const contractPath = path.join(__dirname, `../../contracts/modules/${contractName}.pact`);
	const contractCode = fs.readFileSync(contractPath, "utf8");

	const pactBuilder = Pact.builder
		// .execution(`(describe-namespace (read-msg "ns"))`)
		.execution(initializeCode ? `${contractCode}\n${initializeCode}` : contractCode)
		.addSigner(config.pubKey)
		.setMeta({
			chainId: config.chainId,
			gasLimit: config.gasLimit,
			gasPrice: config.gasPrice,
			senderAccount: `k:${config.pubKey}`,
		})
		.setNetworkId(config.networkId);

	if (Object.keys(data).length > 0) {
		Object.entries(data).forEach(([key, value]) => {
			console.log(key, value);
			pactBuilder.addData(key, value);
		});
	}

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
