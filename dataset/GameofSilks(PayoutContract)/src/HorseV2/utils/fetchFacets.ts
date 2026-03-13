import "dotenv/config";

import hre from "hardhat";
import { Contract } from "ethers";

export const fetchFacets = async (): Promise<Contract[]> => {
	let facets: string[] = [
		"contracts/facets/ERC721Facet.sol:ERC721Facet",
		"contracts/facets/ReadableFacet.sol:ReadableFacet",
		"contracts/facets/WriteableFacet.sol:WriteableFacet",
	];

	const allContracts: Contract[] = [];
	for (const facetName of facets) {
		const Contract = await hre.ethers.getContractFactory(facetName);
		const contract = await Contract.deploy();

		allContracts.push(contract);
	}

	return allContracts;
};
