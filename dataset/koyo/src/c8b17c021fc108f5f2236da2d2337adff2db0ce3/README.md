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
  solidity: "0.8.26", 
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

async function main() {
  const [deployer] = await ethers.getSigners();

  // Deploy each Facet
  const EmergencyManagementFacet = await ethers.getContractFactory("EmergencyManagementFacet");
  const emergencyManagementFacet = await EmergencyManagementFacet.deploy({ from: deployer.address });
  await emergencyManagementFacet.waitForDeployment();
  if (!emergencyManagementFacet.target) {
    throw new Error("Failed to deploy EmergencyManagementFacet");
  }
  console.log("EmergencyManagementFacet deployed to:", emergencyManagementFacet.target);

  const FeeManagementFacet = await ethers.getContractFactory("FeeManagementFacet");
  const feeManagementFacet = await FeeManagementFacet.deploy({ from: deployer.address });
  await feeManagementFacet.waitForDeployment();
  if (!feeManagementFacet.target) {
    throw new Error("Failed to deploy FeeManagementFacet");
  }
  console.log("FeeManagementFacet deployed to:", feeManagementFacet.target);

  const InterestRateModelFacet = await ethers.getContractFactory("InterestRateModelFacet");
  const interestRateModelFacet = await InterestRateModelFacet.deploy({ from: deployer.address });
  await interestRateModelFacet.waitForDeployment();
  if (!interestRateModelFacet.target) {
    throw new Error("Failed to deploy InterestRateModelFacet");
  }
  console.log("InterestRateModelFacet deployed to:", interestRateModelFacet.target);

  const LendingPoolFacet = await ethers.getContractFactory("LendingPoolFacet");
  const lendingPoolFacet = await LendingPoolFacet.deploy({ from: deployer.address });
  await lendingPoolFacet.waitForDeployment();
  if (!lendingPoolFacet.target) {
    throw new Error("Failed to deploy LendingPoolFacet");
  }
  console.log("LendingPoolFacet deployed to:", lendingPoolFacet.target);

  const PriceOracleFacet = await ethers.getContractFactory("PriceOracleFacet");
  const priceOracleFacet = await PriceOracleFacet.deploy({ from: deployer.address });
  await priceOracleFacet.waitForDeployment();
  if (!priceOracleFacet.target) {
    throw new Error("Failed to deploy PriceOracleFacet");
  }
  console.log("PriceOracleFacet deployed to:", priceOracleFacet.target);

  const MarginAccountFacet = await ethers.getContractFactory("MarginAccountFacet");
  const marginAccountFacet = await MarginAccountFacet.deploy({ from: deployer.address });
  await marginAccountFacet.waitForDeployment();
  if (!marginAccountFacet.target) {
    throw new Error("Failed to deploy MarginAccountFacet");
  }
  console.log("MarginAccountFacet deployed to:", marginAccountFacet.target);

  const MarginTradingFacet = await ethers.getContractFactory("MarginTradingFacet");
  const marginTradingFacet = await MarginTradingFacet.deploy({ from: deployer.address });
  await marginTradingFacet.waitForDeployment();
  if (!marginTradingFacet.target) {
    throw new Error("Failed to deploy MarginTradingFacet");
  }
  console.log("MarginTradingFacet deployed to:", marginTradingFacet.target);

  const RoleManagementFacet = await ethers.getContractFactory("RoleManagementFacet");
  const roleManagementFacet = await RoleManagementFacet.deploy({ from: deployer.address });
  await roleManagementFacet.waitForDeployment();
  if (!roleManagementFacet.target) {
    throw new Error("Failed to deploy RoleManagementFacet");
  }
  console.log("RoleManagementFacet deployed to:", roleManagementFacet.target);

  const TokenRegistryFacet = await ethers.getContractFactory("TokenRegistryFacet");
  const tokenRegistryFacet = await TokenRegistryFacet.deploy({ from: deployer.address });
  await tokenRegistryFacet.waitForDeployment();
  if (!tokenRegistryFacet.target) {
    throw new Error("Failed to deploy TokenRegistryFacet");
  }
  console.log("TokenRegistryFacet deployed to:", tokenRegistryFacet.target);

  // Deploy KoyoDex
  const KoyoDex = await ethers.getContractFactory("KoyoDex");
  const koyodex = await KoyoDex.deploy(
    {
      emergencyManagementFacet: emergencyManagementFacet.target,
      feeManagementFacet: feeManagementFacet.target,
      interestRateModelFacet: interestRateModelFacet.target,
      lendingPoolFacet: lendingPoolFacet.target,
      priceOracleFacet: priceOracleFacet.target,
      marginAccountsFacet: marginAccountFacet.target,
      marginTradingFacet: marginTradingFacet.target,
      roleManagementFacet: roleManagementFacet.target,
      tokenRegistryFacet: tokenRegistryFacet.target
    },
    {
      tradingFeeBasisPoints: 100,
      borrowingFeeBasisPoints: 250,
      lendingFeeBasisPoints: 250,
      feeRecipient: "0x2f4Dc30e05AC1Ef6c9682F718C40127f66C5BA98",
      feeToken: "0x10C03A2cc16B0Dbb91ae9A0B916448D17c1557cf",
      shibaSwapRouterAddress: "0x425141165d3DE9FEC831896C016617a52363b687"
    },
    {
      baseRatePerYear: 100,
      multiplierPerYear: 100,
      compoundingFrequency: 6500
    },
    {
      router: "0xf6b5d6eafE402d22609e685DE3394c8b359CaD31",
      xfund: "0xb07C72acF3D7A5E9dA28C56af6F93862f8cc8196",
      dataProvider: "0x611661f4B5D82079E924AcE2A6D113fAbd214b14",
      fee: 100000000000000
    },
    { from: deployer.address }
  );
  await koyodex.waitForDeployment();
  if (!koyodex.target) {
    throw new Error("Failed to deploy KoyoDex");
  }
  console.log("KoyoDex deployed to:", koyodex.target);

  // Grant roles to KoyoDex
  await (await emergencyManagementFacet.grantRole(koyodex.target)).wait();
  console.log("EmergencyManagementFacet role granted.");
  await (await feeManagementFacet.grantRole(koyodex.target)).wait();
  console.log("feeManagementFacet role granted.");
  await (await interestRateModelFacet.grantRole(koyodex.target)).wait();
  console.log("interestRateModelFacet role granted.");
  await (await lendingPoolFacet.grantRole(koyodex.target)).wait();
  console.log("lendingPoolFacet role granted.");
  await (await priceOracleFacet.grantRole(koyodex.target)).wait();
  console.log("priceOracleFacet role granted.");
  await (await marginAccountFacet.grantRole(koyodex.target)).wait();
  console.log("marginAccountFacet role granted.");
  await (await marginTradingFacet.grantRole(koyodex.target)).wait();
  console.log("marginTradingFacet role granted.");
  await (await roleManagementFacet.grantRole(koyodex.target)).wait();
  console.log("roleManagementFacet role granted.");
  await (await tokenRegistryFacet.grantRole(koyodex.target)).wait();
  console.log("tokenRegistryFacet role granted.");

  // Initialize KoyoDex
  await (await koyodex.initializeFacets()).wait();
  console.log("KoyoDex facets initialized.");
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


