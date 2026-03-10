import {
	DeployFunction,
	DeployOptions,
	DeployResult,
} from "hardhat-deploy/types";
import type { NomicLabsHardhatPluginError } from "hardhat/internal/core/errors";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
	console.log("005 Deploying ListingWriteableFacet");
	const { deployments, getNamedAccounts, getChainId, network } = hre;
	const { deploy } = deployments;

	const chainId = await getChainId();
	console.log({ live: network.live, chainId });
	const { deployer } = await getNamedAccounts();

	const deployOptions: DeployOptions = {
		from: deployer,
		args: [],
		log: true,
		deterministicDeployment: "0x1234",
	};

	// if (chainId === "1") {
	// 	console.log("Setting maxFeePerGas to 36 gwei (36_000_000_000) for mainnet");
	// 	deployOptions.maxFeePerGas = "36000000000";
	// }

	let deployAttempt = 0;
	let newlyDeployed: DeployResult | undefined = undefined;
	while (!newlyDeployed) {
		console.log("Deploy attempt (ListingWriteableFacet): ", deployAttempt++);
		try {
			newlyDeployed = await deploy("ListingWriteableFacet", deployOptions);
		} catch (e) {
			console.log("Error deploying: ", e);
			console.log("Try again in 5");
			// Wait 5 seconds and try again
			await new Promise((resolve) => setTimeout(resolve, 5000));
		}
	}

	console.log("ListingWriteableFacet: ", {
		address: newlyDeployed.address,
	});

	if (network.live && chainId !== "31337" && chainId !== "5777") {
		if (newlyDeployed.receipt) {
			console.log("Receipt found");

			const deployHash = newlyDeployed.receipt.transactionHash;
			const tx = await hre.ethers.provider.getTransaction(deployHash);

			const waitTime = 5; // 5 is good for mainnet/goerli

			console.log(`Waiting for ${waitTime} confirmations...`);

			await tx?.wait(waitTime);
		}

		console.log("Verifying ListingWriteableFacet...");
		const artifact = await deployments.getArtifact("ListingWriteableFacet");

		try {
			await hre.run("verify:verify", {
				address: newlyDeployed.address,
				contract: `${artifact.sourceName}:${artifact.contractName}`,
				network: hre.network,
			});
		} catch (e) {
			const error = e as NomicLabsHardhatPluginError;

			if (error.stack?.includes("Contract source code already verified")) {
				console.log("Already verified");
			} else {
				console.error("Error verifying: ", error);
			}
		}

		console.log("Verified");
	} else {
		console.log("Not verifying on non-live network");
	}
};
export default func;
func.tags = ["Facets"];
