require('dotenv').config(); // Load environment variables from .env file
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: "0.8.26", 
  paths: { // These paths are usually fine as defaults
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  networks: {
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`, // Use Alchemy for reliable RPC
      accounts: [process.env.PRIVATE_KEY] // Load private key from environment
    },
    // Optional: Add a "hardhat" network for local development
    hardhat: {
      chainId: 1337 // Standard chainId for Hardhat network
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY // For contract verification (optional)
  }
};
