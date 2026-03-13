require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const MAINNET_RPC_URL = process.env.MAINNET_RPC_URL || "https://eth-mainnet.g.alchemy.com/v2/your-api-key";
const SEPOLIA_RPC_URL = `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`;
const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY || "0x0000000000000000000000000000000000000000000000000000000000000000";

// Auto-generate and fund test accounts
function generateTestAccounts(numAccounts = 10) {
  const { ethers } = require("ethers");
  return Array(numAccounts).fill().map(() => ({
    privateKey: ethers.Wallet.createRandom().privateKey,
    balance: ethers.parseEther("10000").toString()
  }));
}

const TEST_ACCOUNTS = generateTestAccounts();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
        details: {
          yul: true,
          yulDetails: {
            stackAllocation: true,
            optimizerSteps: "dhfoDgvulfnTUtnIf"
          }
        }
      },
      viaIR: true
    }
  },
  networks: {
    hardhat: {
      forking: {
        url: MAINNET_RPC_URL,
        blockNumber: 18990000,
        enabled: true,
      },
      accounts: TEST_ACCOUNTS,
      mining: {
        auto: true,
        interval: 5000
      },
      chainId: 1,
      gas: "auto",
      gasPrice: "auto",
      gasMultiplier: 1.1
    },
    sepolia: {
      url: SEPOLIA_RPC_URL,
      accounts: [PRIVATE_KEY],
      chainId: 11155111,
      blockConfirmations: 6,
      gas: "auto",
      gasPrice: "auto",
      gasMultiplier: 1.1,
      verify: {
        etherscan: {
          apiKey: process.env.ETHERSCAN_API_KEY
        }
      }
    }
  },
  gasReporter: {
    enabled: true,
    currency: 'USD',
    gasPrice: 21,
    excludeContracts: ['contracts/mocks/'],
    src: './contracts'
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
    customChains: [
      {
        network: "sepolia",
        chainId: 11155111,
        urls: {
          apiURL: "https://api-sepolia.etherscan.io/api",
          browserURL: "https://sepolia.etherscan.io"
        }
      }
    ]
  },
  mocha: {
    timeout: 200000
  }
};


// Tasks
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();
  for (const account of accounts) {
    const balance = await hre.ethers.provider.getBalance(account.address);
    console.log(`${account.address}: ${hre.ethers.formatEther(balance)} ETH`);
  }
});

task("fund-accounts", "Funds test accounts")
  .addParam("amount", "Amount of ETH to send")
  .setAction(async (taskArgs, hre) => {
    const accounts = await hre.ethers.getSigners();
    const amount = hre.ethers.parseEther(taskArgs.amount);
    
    for (let i = 1; i < accounts.length; i++) {
      await accounts[0].sendTransaction({
        to: accounts[i].address,
        value: amount
      });
      console.log(`Funded ${accounts[i].address} with ${taskArgs.amount} ETH`);
    }
});