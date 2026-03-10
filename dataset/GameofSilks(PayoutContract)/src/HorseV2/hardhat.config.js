/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require("dotenv").config({path: './.env'});
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require('hardhat-contract-sizer');
require("solidity-coverage");
require("hardhat-gas-reporter");

const diamondInfo = require("./diamondInfo.json");

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

module.exports = {
  solidity: "0.8.20",
  defaultNetwork: 'localhost',
  settings: {
    remappings: [],
    optimizer: {
      "enabled": true,
      "runs": 200
    },
    evmVersion: "byzantium",
    libraries: {},
    outputSelection: {
      "*": {
        "*": [
          "evm.bytecode",
          "evm.deployedBytecode",
          "devdoc",
          "userdoc",
          "metadata",
          "abi"
        ]
      }
    }
  },
  networks: {
    hardhat: {

    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.SILKS_PROJECT_ID}`,
      accounts: [
        `${process.env.SILKS_KEY}`
      ]
    },
    ropsten: {
      url: `https://ropsten.infura.io/v3/${process.env.SILKS_CLAIM_PROJECT_ID}`,
      accounts: [
        `${process.env.ROPSTEN_PRIVATE_KEY}`
      ]
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${process.env.SILKS_CLAIM_PROJECT_ID}`,
      accounts: [
        `${process.env.ROPSTEN_PRIVATE_KEY}`
      ]
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${process.env.SILKS_CLAIM_PROJECT_ID}`,
      accounts: [
        `${process.env.ROPSTEN_PRIVATE_KEY}`
      ]
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${process.env.SILKS_CLAIM_PROJECT_ID}`,
      accounts: [
        `${process.env.ROPSTEN_PRIVATE_KEY}`
      ]
    }
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.ETHERSCAN_TOKEN
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: true,
    except: [],
    only: [
      diamondInfo.name,
      ...diamondInfo.facets,
    ]
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
};
