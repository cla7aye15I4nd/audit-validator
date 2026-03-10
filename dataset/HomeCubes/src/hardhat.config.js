require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  defaultNetwork: "baseSepolia",
  networks: {
    hardhat: {
    },
    sepolia: {
      url: "",
      accounts: [""]
    },
    bscTestnet: {
      url: "",
      accounts: [""]
    },
    baseSepolia: {
      url: "",
      accounts: [""]
    }
  },
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    },
    "viaIR": true
  },
  etherscan: {
    apiKey: {
      sepolia: '',
      bscTestnet: "",
      baseSepolia: ""
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 40000
  }
}
