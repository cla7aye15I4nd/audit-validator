# KoyoDex Deployment Guide

This guide provides step-by-step instructions for deploying the `KoyoDex` Diamond contract and its associated Facets on the Sepolia network using Hardhat.

## Prerequisites

- Node.js and npm installed
- Hardhat installed (`npm install --save-dev hardhat`)
- Solidity contract files for `KoyoDex` and its Facets
- Ethers.js library installed (`npm install @nomiclabs/hardhat-ethers ethers`)
- An account with Sepolia testnet Ether for deploying contracts

## Directory Structure

```
project-root/
|-- contracts/
|   |-- KoyoDex.sol
|   |-- facets/
|   |   |-- EmergencyManagementFacet.sol
|   |   |-- FeeManagementFacet.sol
|   |   |-- InterestRateModelFacet.sol
|   |   |-- LendingPoolFacet.sol
|   |   |-- MarginAccountFacet.sol
|   |   |-- MarginTradingFacet.sol
|   |   |-- PriceOracleFacet.sol
|   |   |-- RoleManagementFacet.sol
|   |   |-- TokenRegistryFacet.sol
|   |-- libraries/
|   |   |-- LibDiamond.sol
|   |   |-- RoleConstants.sol
|   |-- interfaces/
|   |   |-- IDiamondCut.sol
|   |   |-- IDiamondLoupe.sol
|   |   |-- IFacetInterface.sol
|-- scripts/
|   |-- deploy_koyodex.js
|-- hardhat.config.js
```

## Steps to Deploy

### Step 1: Set Up Hardhat Project

1. **Initialize Hardhat**: Create a new Hardhat project if you haven't already.

   ```bash
   npx hardhat
   ```

   Follow the prompts to set up your project.

2. **Install Dependencies**: Ensure that Hardhat and Ethers.js are installed.

   ```bash
   npm install --save-dev hardhat @nomiclabs/hardhat-ethers ethers
   ```

### Step 2: Compile Contracts

Ensure that your contracts are correctly placed in the `contracts/` directory. Update `hardhat.config.js` to configure the Solidity version and network:

```javascript
require('dotenv').config();
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: "0.8.27", 
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  networks: {
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [process.env.PRIVATE_KEY]
    },
    hardhat: {
      chainId: 1337
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
};

```

Compile the contracts:

```bash
npx hardhat compile
```

### Step 3: Create Deployment Script

Create a deployment script `deploy_koyodex.js` in the `scripts/` directory:

```javascript
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function getArtifactSelectors(contractName) {
    const artifact = require(`../artifacts/contracts/facets/${contractName}.sol/${contractName}.json`);
    const abi = artifact.abi;
    
    const selectors = abi
        .filter(item => item.type === 'function')
        .map(item => {
            const funcSig = `${item.name}(${item.inputs.map(i => i.type).join(',')})`;
            const selector = ethers.keccak256(ethers.toUtf8Bytes(funcSig)).slice(0, 10);
            return {
                selector,
                signature: funcSig,
                name: item.name
            };
        });
    return selectors;
}

async function verifySelectorsBeforeDeployment() {
    const facetNames = [
        "EmergencyManagementFacet",
        "FeeManagementFacet",
        "InterestRateModelFacet",
        "LendingPoolFacet",
        "PriceOracleFacet",
        "MarginAccountsFacet",
        "MarginTradingFacet",
        "RoleManagementFacet",
        "TokenRegistryFacet",
        "ReentrancyGuardFacet"
    ];

    const selectorMap = new Map();
    let hasCollisions = false;
    const collisions = [];
    
    for (const facetName of facetNames) {
        const selectors = await getArtifactSelectors(facetName);
        
        for (const {selector, signature, name} of selectors) {
            if (selectorMap.has(selector)) {
                hasCollisions = true;
                collisions.push({
                    selector,
                    facet1: facetName,
                    facet2: selectorMap.get(selector).facet,
                    function1: name,
                    function2: selectorMap.get(selector).name,
                    signature1: signature,
                    signature2: selectorMap.get(selector).signature
                });
            } else {
                selectorMap.set(selector, {
                    facet: facetName,
                    name,
                    signature
                });
            }
        }
    }

    if (hasCollisions) {
        console.log("\nSelector Collisions Found:");
        console.log("==========================");
        collisions.forEach((collision, index) => {
            console.log(`\nCollision ${index + 1}:`);
            console.log(`Selector: ${collision.selector}`);
            console.log(`First Facet: ${collision.facet1}`);
            console.log(`Function: ${collision.function1}`);
            console.log(`Signature: ${collision.signature1}`);
            console.log(`Second Facet: ${collision.facet2}`);
            console.log(`Function: ${collision.function2}`);
            console.log(`Signature: ${collision.signature2}`);
        });
        console.log("\nTotal collisions found:", collisions.length);
        return false;
    }

    console.log("No selector collisions found across all facets.");
    return true;
}

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    console.log("Verifying selectors before deployment...");
    const selectorsValid = await verifySelectorsBeforeDeployment();
    if (!selectorsValid) {
        console.error("Selector verification failed. Aborting deployment.");
        return;
    }
    console.log("Selector verification passed. Proceeding with deployment...");

    const LibDiamond = await ethers.getContractFactory("LibDiamond");
    const libDiamond = await LibDiamond.deploy();
    await libDiamond.waitForDeployment();
    console.log("LibDiamond deployed to:", libDiamond.target);

    const EmergencyManagementFacet = await ethers.getContractFactory("EmergencyManagementFacet");
    const emergencyManagementFacet = await EmergencyManagementFacet.deploy();
    await emergencyManagementFacet.waitForDeployment();
    console.log("EmergencyManagementFacet deployed to:", emergencyManagementFacet.target);

    const FeeManagementFacet = await ethers.getContractFactory("FeeManagementFacet");
    const feeManagementFacet = await FeeManagementFacet.deploy();
    await feeManagementFacet.waitForDeployment();
    console.log("FeeManagementFacet deployed to:", feeManagementFacet.target);

    const InterestRateModelFacet = await ethers.getContractFactory("InterestRateModelFacet");
    const interestRateModelFacet = await InterestRateModelFacet.deploy();
    await interestRateModelFacet.waitForDeployment();
    console.log("InterestRateModelFacet deployed to:", interestRateModelFacet.target);

    const LendingPoolFacet = await ethers.getContractFactory("LendingPoolFacet");
    const lendingPoolFacet = await LendingPoolFacet.deploy();
    await lendingPoolFacet.waitForDeployment();
    console.log("LendingPoolFacet deployed to:", lendingPoolFacet.target);

    const PriceOracleFacet = await ethers.getContractFactory("PriceOracleFacet");
    const priceOracleFacet = await PriceOracleFacet.deploy();
    await priceOracleFacet.waitForDeployment();
    console.log("PriceOracleFacet deployed to:", priceOracleFacet.target);

    const MarginAccountsFacet = await ethers.getContractFactory("MarginAccountsFacet");
    const marginAccountsFacet = await MarginAccountsFacet.deploy();
    await marginAccountsFacet.waitForDeployment();
    console.log("MarginAccountsFacet deployed to:", marginAccountsFacet.target);

    const MarginTradingFacet = await ethers.getContractFactory("MarginTradingFacet");
    const marginTradingFacet = await MarginTradingFacet.deploy();
    await marginTradingFacet.waitForDeployment();
    console.log("MarginTradingFacet deployed to:", marginTradingFacet.target);

    const RoleManagementFacet = await ethers.getContractFactory("RoleManagementFacet");
    const roleManagementFacet = await RoleManagementFacet.deploy();
    await roleManagementFacet.waitForDeployment();
    console.log("RoleManagementFacet deployed to:", roleManagementFacet.target);

    const TokenRegistryFacet = await ethers.getContractFactory("TokenRegistryFacet");
    const tokenRegistryFacet = await TokenRegistryFacet.deploy();
    await tokenRegistryFacet.waitForDeployment();
    console.log("TokenRegistryFacet deployed to:", tokenRegistryFacet.target);

    const ReentrancyGuardFacet = await ethers.getContractFactory("ReentrancyGuardFacet");
    const reentrancyGuardFacet = await ReentrancyGuardFacet.deploy();
    await reentrancyGuardFacet.waitForDeployment();
    console.log("ReentrancyGuardFacet deployed to:", reentrancyGuardFacet.target);

    const facetAddresses = {
        emergencyManagementFacet: emergencyManagementFacet.target,
        feeManagementFacet: feeManagementFacet.target,
        interestRateModelFacet: interestRateModelFacet.target,
        lendingPoolFacet: lendingPoolFacet.target,
        priceOracleFacet: priceOracleFacet.target,
        marginAccountsFacet: marginAccountsFacet.target,
        marginTradingFacet: marginTradingFacet.target,
        roleManagementFacet: roleManagementFacet.target,
        tokenRegistryFacet: tokenRegistryFacet.target,
        reentrancyGuardFacet: reentrancyGuardFacet.target
    };

    const feeParams = {
        tradingFeeBasisPoints: 20,
        borrowingFeeBasisPoints: 50,
        lendingFeeBasisPoints: 10,
        liquidationFeeBasisPoints: 100,
        feeRecipient: deployer.address,
        feeToken: "0x10C03A2cc16B0Dbb91ae9A0B916448D17c1557cf",
        shibaSwapRouterAddress: "0x425141165d3DE9FEC831896C016617a52363b687"
    };

    const interestParams = {
        baseRatePerYear: 200,
        multiplierPerYear: 1000,
        jumpMultiplierPerYear: 2000,
        optimal: 8000,
        reserve: 1000,
        compoundingFrequency: 6500
    };

    const oracleParams = {
        router: "0xf6b5d6eafE402d22609e685DE3394c8b359CaD31",
        xfund: "0xb07C72acF3D7A5E9dA28C56af6F93862f8cc8196",
        dataProvider: "0x611661f4B5D82079E924AcE2A6D113fAbd214b14",
        fee: ethers.parseEther("0.0001"),
        heartbeat: 3600,
        deviation: 100
    };

    const KoyoDex = await ethers.getContractFactory("KoyoDex");
    const koyoDex = await KoyoDex.deploy(
        facetAddresses,
        feeParams,
        interestParams,
        oracleParams
    );
    await koyoDex.waitForDeployment();
    console.log("KoyoDex deployed to:", koyoDex.target);

    if (network.name !== "hardhat" && network.name !== "localhost") {
        console.log("Waiting for deployments to be confirmed...");
        
        // Wait for 5 block confirmations for the main contract
        await koyoDex.waitForDeployment();
        const receipt = await koyoDex.deploymentTransaction().wait(5);
        console.log("KoyoDex deployment confirmed at block:", receipt.blockNumber);
    
        console.log("Starting contract verification...");
        
        // Add delay before verification
        await new Promise(resolve => setTimeout(resolve, 30000)); // 30 seconds delay
    
        try {
            console.log("Verifying KoyoDex...");
            await hre.run("verify:verify", {
                address: koyoDex.target,
                constructorArguments: [facetAddresses, feeParams, interestParams, oracleParams],
            });
        } catch (error) {
            console.log("Error verifying KoyoDex:", error.message);
        }
    
        const facetsToVerify = [
            { contract: "EmergencyManagementFacet", address: emergencyManagementFacet.target },
            { contract: "FeeManagementFacet", address: feeManagementFacet.target },
            { contract: "InterestRateModelFacet", address: interestRateModelFacet.target },
            { contract: "LendingPoolFacet", address: lendingPoolFacet.target },
            { contract: "PriceOracleFacet", address: priceOracleFacet.target },
            { contract: "MarginAccountsFacet", address: marginAccountsFacet.target },
            { contract: "MarginTradingFacet", address: marginTradingFacet.target },
            { contract: "RoleManagementFacet", address: roleManagementFacet.target },
            { contract: "TokenRegistryFacet", address: tokenRegistryFacet.target },
            { contract: "ReentrancyGuardFacet", address: reentrancyGuardFacet.target }
        ];
    
        for (const facet of facetsToVerify) {
            try {
                console.log(`Verifying ${facet.contract}...`);
                await new Promise(resolve => setTimeout(resolve, 5000)); // 5 seconds delay between verifications
                
                await hre.run("verify:verify", {
                    address: facet.address,
                    contract: `contracts/facets/${facet.contract}.sol:${facet.contract}`
                });
            } catch (error) {
                console.log(`Error verifying ${facet.contract}:`, error.message);
            }
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
```

### Step 4: Run the Deployment Script

Run the script with Hardhat:

```bash
npx hardhat run scripts/deploy_koyodex.js --network sepolia
```

## Detailed Steps Explanation

1. **Deploy Facets**: Each Facet contract is deployed individually, and their addresses are logged.
2. **Deploy KoyoDex**: The `KoyoDex` Diamond contract is deployed with the addresses of the previously deployed Facets and necessary initialization parameters.
3. **Grant Roles**: Each Facet contract grants the `ADMIN_ROLE` to the `KoyoDex` contract to enable it to manage the facets.
4. **Initialize KoyoDex**: The `initializeFacets` function on the `KoyoDex` contract is called to perform any required initialization logic.


