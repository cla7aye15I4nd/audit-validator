/* eslint-disable @typescript-eslint/naming-convention */
import { ethers } from "hardhat";
import { getSelectors } from "./libraries/diamond";
import { glob } from "glob";
import fs from "fs";
import path from "path";

export const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 };
interface FacetFile {
	address: string;
	abi: [key: string, value: any][];
}

export const deploy = async (): Promise<string> => {
	const [owner] = await ethers.getSigners();

	// Get file paths
	const facetFiles = glob
		.sync("deployments/localhost/*Facet.json")
		.map((file) => {
			const facetName = path.basename(file, ".json");
			return {
				// ...facetFile,
				...(JSON.parse(fs.readFileSync(file, "utf8")) as FacetFile), // This is the same as the line above
				name: facetName,
			};
		});
	const initFile = glob.sync("deployments/localhost/*Init.json").map((file) => {
		const initName = path.basename(file, ".json");
		return {
			...(JSON.parse(fs.readFileSync(file, "utf8")) as FacetFile),
			name: initName,
		};
	});

	// Diamon initialization variables
	const initAddress = initFile[0].address;
	console.log("initAddress: ", initAddress);
	const avatarAddress = "0xde3d8dee91e08a4b0c54b1e93a20ffe079c6628c"; // Goerli Address
	const listTypes = [[avatarAddress, "avatar", 721, true, true]];
	const royaltyPct = 800; // 8%
	const initArgs = [listTypes, owner.address, royaltyPct, avatarAddress];

	// Get the Diamond Cut
	const cut = [];
	for (const facet of facetFiles) {
		console.log("Getting contractName: ", facet.name);
		const Facet = await ethers.getContractAt(facet.name, facet.address);

		cut.push({
			target: facet.address,
			action: FacetCutAction.Add,
			selectors: getSelectors(Facet), //.remove(facetsToRemove),
		});
	}
	console.log({ cut });
	// Deploy the Diamond
	console.log("Deploying Diamond");
	const Diamond = await ethers.getContractFactory("SilksMarketplaceDiamond");
	const transactionResponse = await Diamond.deploy(owner.address);
	const diamond = await transactionResponse.waitForDeployment();
	console.log("Diamond deployed to: ", { diamond });

	// Initialize the Diamond
	console.log("Initializing Diamond");
	const iDiamondInit = new ethers.Interface([
		"function init((address,string,uint256,bool,bool)[],address,uint256,address) external",
	]);
	const callData = iDiamondInit.encodeFunctionData("init", initArgs);
	const diamondCutTx = await diamond.diamondCut(cut, initAddress, callData);
	await diamondCutTx.wait();

	// Verify the Diamond
	// console.log({ FacetNames });
	return await diamond.getAddress();
};

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
if (require.main === module) {
	deploy()
		.then(() => process.exit(0))
		.catch((error) => {
			console.error(error);
			process.exit(1);
		});
}
