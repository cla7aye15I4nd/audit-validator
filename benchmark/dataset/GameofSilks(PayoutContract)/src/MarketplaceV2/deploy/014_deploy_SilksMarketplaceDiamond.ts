import {
	DeployFunction,
	DeployOptions,
	DeployResult,
} from "hardhat-deploy/types";
import type { NomicLabsHardhatPluginError } from "hardhat/internal/core/errors";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ethers } from "hardhat";
import { getSelectors } from "../scripts/libraries/diamond";
import { glob } from "glob";
import fs from "fs";
import path from "path";
import { SilksMarketplaceDiamond } from "../typechain-types";

export const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 };
interface FacetFile {
	address: string;
	abi: [key: string, value: any][];
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
	console.log("014 Deploying SilksMarketplaceDiamond");
	const { deployments, getNamedAccounts, getChainId, network } = hre;
	const { deploy } = deployments;

	const chainId = await getChainId();
	console.log({ live: network.live, chainId });
	const { deployer } = await getNamedAccounts();

	const deployOptions: DeployOptions = {
		from: deployer,
		args: [deployer],
		log: true,
		deterministicDeployment: "0x1238",
	};

	// if (chainId === "1") {
	// 	console.log("Setting maxFeePerGas to 36 gwei (36_000_000_000) for mainnet");
	// 	deployOptions.maxFeePerGas = "36000000000";
	// }

	let deployAttempt = 0;
	let newlyDeployed: DeployResult | undefined = undefined;
	while (!newlyDeployed) {
		console.log("Deploy attempt (SilksMarketplaceDiamond): ", deployAttempt++);
		try {
			newlyDeployed = await deploy("SilksMarketplaceDiamond", deployOptions);
		} catch (e) {
			console.log("Error deploying: ", e);
			console.log("Try again in 5");
			// Wait 5 seconds and try again
			await new Promise((resolve) => setTimeout(resolve, 5000));
		}
	}

	console.log("SilksMarketplaceDiamond: ", {
		address: newlyDeployed.address,
	});

	// if (network.live && chainId !== "31337" && chainId !== "5777") {
	// 	if (newlyDeployed.receipt) {
	// 		console.log("Receipt found");

	// 		const deployHash = newlyDeployed.receipt.transactionHash;
	// 		const tx = await hre.ethers.provider.getTransaction(deployHash);

	// 		const waitTime = 5; // 5 is good for mainnet/goerli

	// 		console.log(`Waiting for ${waitTime} confirmations...`);

	// 		await tx?.wait(waitTime);
	// 	}

	// 	console.log("Verifying SilksMarketplaceDiamond...");
	// 	const artifact = await deployments.getArtifact("SilksMarketplaceDiamond");

	// 	try {
	// 		await hre.run("verify:verify", {
	// 			address: newlyDeployed.address,
	// 			constructorArguments: [deployer],
	// 			contract: `${artifact.sourceName}:${artifact.contractName}`,
	// 			network: hre.network,
	// 		});
	// 	} catch (e) {
	// 		const error = e as NomicLabsHardhatPluginError;

	// 		if (error.stack?.includes("Contract source code already verified")) {
	// 			console.log("Already verified");
	// 		} else {
	// 			console.error("Error verifying: ", error);
	// 		}
	// 	}

	// 	console.log("Verified");
	// } else {
	// 	console.log("Not verifying on non-live network");
	// }

	await initializeAndCutDiamond(newlyDeployed.address, hre, deployer);
};
export default func;
func.tags = ["Diamond"];

const initializeAndCutDiamond = async (
	diamondAddress: string,
	hre: HardhatRuntimeEnvironment,
	deployer: string
) => {
	const diamond = (await ethers.getContractAt(
		"SilksMarketplaceDiamond",
		diamondAddress
	)) as SilksMarketplaceDiamond;

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
	const priceFeedAddress = "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e"; // Goerli Address
	const listTypes = [[avatarAddress, "avatar", 721, true, true]];
	const royaltyPct = 800; // 8%
	const initArgs = [
		listTypes,
		deployer,
		royaltyPct,
		avatarAddress,
		priceFeedAddress,
	];

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

	// Initialize the Diamond
	console.log("Initializing Diamond");
	const iDiamondInit = new ethers.Interface([
		"function init((address,string,uint256,bool,bool)[],address,uint256,address,address) external",
	]);
	const callData = iDiamondInit.encodeFunctionData("init", initArgs);
	const diamondCutTx = await diamond.diamondCut(cut, initAddress, callData);
	await diamondCutTx.wait();
};
