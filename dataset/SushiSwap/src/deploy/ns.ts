import { deployContract } from "./util/index.js";
import dotenv from "dotenv";

dotenv.config();

const adminKeyset = process.env.ADMIN_KEYSET;

if (!adminKeyset) {
	throw new Error("ADMIN_KEYSET environment variable is not set");
}

await deployContract({
	contractName: "ns",
	data: {
		"admin-keyset": {
			keys: [adminKeyset],
			pred: "keys-all",
		},
	},
});

//n_49d62374d49bd6c59814220d560dea72df388b4a: testnet
//n_49d62374d49bd6c59814220d560dea72df388b4a: mainnet
