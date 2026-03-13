import { deployContract } from "./util/index.js";

const ns = process.env.NS;
const adminKeyset = process.env.ADMIN_KEYSET;

console.log({ ns, adminKeyset });

async function deployUtilities(): Promise<void> {
	await deployContract({
		contractName: "constants",
		data: {
			ns: ns,
			"admin-keyset": {
				keys: [adminKeyset],
				pred: "keys-all",
			},
		},
	});

	await deployContract({
		contractName: "fungible-util",
		data: {
			ns: ns,
		},
	});

	await deployContract({
		contractName: "sushi-callable-v1",
		data: {
			ns: ns,
		},
	});

	await deployContract({
		contractName: "sushi-noop-callable",
		data: {
			ns: ns,
		},
	});
}

deployUtilities()
	.catch((error) => {
		console.error("Error deploying utilities:", error);
		process.exit(1);
	})
	.finally(() => {
		console.log("Utilities deployment completed.");
	});

//n_49d62374d49bd6c59814220d560dea72df388b4a
