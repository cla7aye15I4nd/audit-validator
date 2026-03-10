import { deployContract } from "./util/index.js";
import dotenv from "dotenv";

dotenv.config();

const ns = process.env.NS;

if (!ns) {
	throw new Error("NS environment variable is not set");
}

await deployContract({
	contractName: "sushi-exchange-tokens",
	data: {
		ns: ns,
	},
	initializeCode: `
    (create-table issuers)
    (create-table supplies)
    (create-table ledger)
  `,
});
