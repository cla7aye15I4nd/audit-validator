import { fetchFacets } from "../utils/fetchFacets";
import { generateDummyContract } from "../utils/generateDummyContract";
import * as fs from "fs";

const main = async () => {
	const diamondAddress = "0x0000000000000000000000000000000000000000";
	const network = "localhost";

	if (!diamondAddress || !network) {
		throw new Error("missing argument");
	}

	try {
		const facets = await fetchFacets();

		const contractString = generateDummyContract(facets, {
			network,
			diamondAddress,
			solidityVersion: "^0.8.20",
			contractName: `EtherscanImplementation`,
			spdxIdentifier: "MIT",
		});

		fs.writeFileSync(
			`./contracts/dummy/EtherscanImplementation.sol`,
			contractString
		);
	} catch (error) {
		console.error(error);
	}
};

main();
