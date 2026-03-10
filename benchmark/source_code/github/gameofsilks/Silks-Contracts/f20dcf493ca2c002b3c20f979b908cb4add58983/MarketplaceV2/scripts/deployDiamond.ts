/* eslint-disable @typescript-eslint/naming-convention */
import { ethers } from "hardhat";
import { getSelectors } from "./libraries/diamond";
import { facets } from "../diamondInfo.json";

export const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 };

const FacetNames = facets.map((facet) => facet.name);

// // These facets have extra "supportsInterface(bytes4)" that can not be added to diamond.
const FacetsWithExtra165: string[] = [];

export const deploy = async (): Promise<string> => {
	const [owner, addr1, addr2, addr3, addr4, ...addrs] =
		await ethers.getSigners();

	const cut = [];
	let initAddress = "";
	for (const FacetName of FacetNames) {
		const Facet = await ethers.getContractFactory(FacetName);
		const transactionResponse = await Facet.deploy();
		const facet = await transactionResponse.waitForDeployment();

		// console.log(`${FacetName} deployed: ${await facet.getAddress()}`);

		if (FacetName === "SilksMarketplaceDiamondInit") {
			initAddress = await facet.getAddress();
		}

		const facetsToRemove = FacetsWithExtra165.includes(FacetName)
			? ["supportsInterface(bytes4)"]
			: [];
		cut.push({
			target: await facet.getAddress(),
			action: FacetCutAction.Add,
			selectors: getSelectors(facet).remove(facetsToRemove),
		});
		//
		// console.log({
		// 	facetName: FacetName,
		// 	selectors: JSON.stringify(
		// 		getSelectors(facet).remove(facetsToRemove),
		// 		null,
		// 		2
		// 	),
		// });
	}

	const Diamond = await ethers.getContractFactory("SilksMarketplaceDiamond");
	const transactionResponse = await Diamond.deploy(owner.address);

	const diamond = await transactionResponse.waitForDeployment();

	// console.log("Cuts: ", JSON.stringify(cut, null, 2));
	// console.log(`Diamond deployed: ${await diamond.getAddress()}`);

	// Hardhat Avatar Address Goerli: 0xde3d8dee91e08a4b0c54b1e93a20ffe079c6628c
	const listTypes = [
		["0xde3d8dee91e08a4b0c54b1e93a20ffe079c6628c", "avatar", 721, true, true],
	];

	const royaltyPct = 800; // 8%
	const avatarAddress = "0xde3d8dee91e08a4b0c54b1e93a20ffe079c6628c"; // Goerli Address
	const priceFeedAddress = "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e"; // Goerli Address
	const initArgs = [
		listTypes,
		owner.address,
		royaltyPct,
		avatarAddress,
		priceFeedAddress,
	];

	const iface = new ethers.Interface([
		"function init((address,string,uint256,bool,bool)[],address,uint256,address,address) external",
	]);
	const callData = iface.encodeFunctionData("init", initArgs);

	// console.log({ cut, initAddress, callData });

	const diamondCutTx = await diamond.diamondCut(cut, initAddress, callData);
	await diamondCutTx.wait();

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
