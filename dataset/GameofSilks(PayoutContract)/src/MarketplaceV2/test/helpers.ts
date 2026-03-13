import fs from "fs";
import path from "path";
// import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { WeirdContract } from "./diamond";
import { Fragment } from "ethers";

type AbiInfo = {
	contractName: string;
	folder?: string;
};

export const getAbi = ({
	contractName,
	folder = "",
}: AbiInfo): any[] | undefined => {
	try {
		const dir = path.resolve(
			__dirname,
			`../artifacts/contracts/${folder}/${contractName}.sol/${contractName}.json`
		);
		const file = fs.readFileSync(dir, "utf8");
		const json = JSON.parse(file);
		return json.abi;
	} catch (e) {
		console.error(`Error`, e);
	}
};

type FacetInfo = {
	info: {
		name: string;
	};
	args?: any[];
	upgradeable?: boolean;
};

export const getFacet = async ({
	info,
	args = [],
	upgradeable = true,
}: FacetInfo): Promise<{
	info: { name: string; folder: string };
	deployedFacet: WeirdContract;
	upgradeable: boolean;
}> => {
	const contractFactory = await ethers.getContractFactory(info.name);
	const deployedFacet = await contractFactory.deploy(...args);
	return {
		// @ts-ignore This has folder
		info,
		deployedFacet,
		upgradeable,
	};
};

type SignatureInfo = {
	deployedFacet: WeirdContract;
};

export const getSignatures = async ({
	deployedFacet,
}: SignatureInfo): Promise<{ function: string; selector: string }[]> => {
	return deployedFacet.interface.fragments
		.filter((fragment: Fragment) => fragment.type === "function")
		.map((fragment: Fragment) => {
			// Format the fragment to get the function signature
			const functionSignature = fragment.format("full");
			// Compute the selector by taking the first 8 characters of the keccak256 hash of the signature
			// @ts-ignore SI: This is okay be selector is available
			const fragmentSelector = fragment.selector;
			let selector = fragmentSelector
				? fragmentSelector
				: `0x${ethers
						.keccak256(ethers.toUtf8Bytes(functionSignature))
						.slice(2, 10)}`;
			return {
				function: functionSignature,
				selector,
			};
		})
		.filter(({ function: functionSignature }) => {
			const initHash = ethers.id("init(bytes)").slice(2, 10);
			const supportsInterfaceHash = ethers
				.id("supportsInterface(bytes4)")
				.slice(2, 10);
			const currentHash = ethers
				.keccak256(ethers.toUtf8Bytes(functionSignature))
				.slice(2, 10);

			return currentHash !== initHash && currentHash !== supportsInterfaceHash;
		});
};

type FunctionInfo = {
	func: {
		name: string;
		inputs?: { type: string }[];
	};
};

export const getFunctionSignature = ({ func }: FunctionInfo): string => {
	return `${func.name}(${
		func.inputs?.length && func.inputs?.length > 0
			? `${func.inputs.map((item) => item.type).join(",")}`
			: ""
	})`;
};
