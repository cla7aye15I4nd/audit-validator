import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "hardhat-diamond-abi";
import "hardhat-abi-exporter";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import { config as dotenvConfig } from "dotenv";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-ethers";
import "@typechain/hardhat";
import { ethers } from "ethers";

import diamondInfo from "./diamondInfo.json";
import { HardhatUserConfig } from "hardhat/config";

dotenvConfig({ path: "./.env" });

// Ensure that we have all the environment variables we need.
const mnemonic: string | undefined = process.env.MNEMONIC;
if (!mnemonic) {
	throw new Error("Please set your MNEMONIC in a .env file");
}

const infuraApiKey: string | undefined = process.env.INFURA_API_KEY;
if (!infuraApiKey) {
	throw new Error("Please set your INFURA_API_KEY in a .env file");
}

const privateKey: string | undefined = process.env.PRIVATE_KEY;
if (!privateKey) {
	throw new Error("Please set your PRIVATE_KEY in a .env file");
}

// Generate additional accounts
const additionalAccounts = new Array(5).fill(0).map(() => {
	const wallet = ethers.Wallet.createRandom();
	return {
		privateKey: wallet.privateKey,
		balance: ethers.parseEther("1000").toString(), // Example balance of 1000 ETH
	};
});

const config: HardhatUserConfig = {
	namedAccounts: {
		deployer: 0,
	},
	solidity: {
		version: "0.8.23",
		settings: {
			viaIR: true,
			optimizer: {
				enabled: true,
				runs: 2000,
			},
		},
	},
	networks: {
		hardhat: {
			forking: {
				url: `https://goerli.infura.io/v3/${infuraApiKey}`,
				// Optionally, you can specify at which block number you want to fork
				blockNumber: 10_562_433,
			},
			accounts: [
				{
					privateKey: `${process.env.PRIVATE_KEY}`,
					balance: "10000000000000000000000",
				},
				...additionalAccounts,
			],
		},
		mainnet: {
			url: `https://mainnet.infura.io/v3/${infuraApiKey}`,
			accounts: [`${process.env.PRIVATE_KEY}`],
		},
		goerli: {
			url: `https://goerli.infura.io/v3/${infuraApiKey}`,
			accounts: [`${process.env.PRIVATE_KEY}`],
		},
		sepolia: {
			url: `https://sepolia.infura.io/v3/${infuraApiKey}`,
			accounts: [`${process.env.PRIVATE_KEY}`],
		},
	},
	contractSizer: {
		alphaSort: true,
		disambiguatePaths: true,
		except: [],
		only: [diamondInfo.name, ...diamondInfo.facets.map((facet) => facet.name)],
	},
	gasReporter: {
		coinmarketcap: process.env.COINMARKETCAP_API_KEY || "",
		currency: "USD",
		enabled: true,
		src: "./contracts",
		// gasPrice: 30,
		token: "ETH",
		outputFile: "gas-report",
		showMethodSig: true,
		noColors: true,
	},
	etherscan: {
		apiKey: process.env.ETHERSCAN_TOKEN,
	},
	typechain: {
		outDir: "typechain-types",
		target: "ethers-v6",
		alwaysGenerateOverloads: false,
		dontOverrideCompile: false,
	},
	diamondAbi: {
		name: "MarketplaceDiamondABI",
		// exclude: ["MockNFT", "MarketplaceMock", "SilksDummy"],
		include: [
			"ContractGlossaryAdminWriteableFacet",
			"ContractGlossaryReadableFacet",
			"ListingAdminReadableFacet",
			"ListingAdminWritableFacet",
			"ListingReadableFacet",
			"ListingWriteableFacet",
			"MarketplaceAdminWriteableFacet",
			"SilksMinterFacet",
			"SilksMinterAdminFacet",
			"PackFacet",
			"PackAdminFacet",
			"SilksMarketplaceDiamond",
		],
		strict: false,
		filter: function (abiElement, index, fullAbi, fullyQualifiedName) {
			// console.log("abiElement", abiElement);
			// console.log("index", index);
			// console.log("fullyQualifiedName", fullyQualifiedName);
			return abiElement.name !== "superSecret";
		},
	},
	abiExporter: [
		{
			path: "./abi/json",
			format: "json",
		},
		{
			path: "./abi/minimal",
			format: "minimal",
		},
		{
			path: "./abi/fullName",
			format: "fullName",
		},
	],
};

export default config;
