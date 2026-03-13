import '@nomicfoundation/hardhat-chai-matchers'
import '@matterlabs/hardhat-zksync-solc'
import '@matterlabs/hardhat-zksync-node'
import '@matterlabs/hardhat-zksync-ethers'
import '@matterlabs/hardhat-zksync-verify'
import 'hardhat-deploy'
import '@nomiclabs/hardhat-solhint'
import './tasks'

import { HardhatUserConfig } from 'hardhat/config'

const accounts = [process.env.DEPLOYER_KEY || '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80']
const useZksync = process.env.HARDHAT_ZKSYNC == 'true'

const config: HardhatUserConfig = {
  namedAccounts: {
    deployer: { default: 0 },
    admin: {
      default: 0,
      11155111: '0x49015c3dBbeE8B7c5FEA76d014f6B17bdE783E8d', // sepolia testnet
      300: '0x49015c3dBbeE8B7c5FEA76d014f6B17bdE783E8d', // zksync testnet
      260: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266', // anvil-zksync local node
    },
    token: {
      default: 0,
      11155111: '0xd4F7c57601cB1Fda90C2f19ef4d1ac88593FEeF9', // dev purpose ATH
      // 11155111: "0x927f83B92BF3b09B7810FCb20d1A9d17d6789Fb2", // official testnet ATH token
      300: '0x78E06506Adb9eDE5d8bD7081eD50FD785778b646',
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  zksolc: {
    compilerSource: 'binary',
    settings: {
      enableEraVMExtensions: true,
      optimizer: {
        enabled: true,
      },
      codegen: 'yul',
    },
  },
  defaultNetwork: 'hardhat',
  zksyncAnvil: {
    version: '0.4.*',
    binaryPath: 'anvil-zksync',
  },
  networks: {
    hardhat: {
      zksync: useZksync,
    },
    localhost: {
      url: 'http://127.0.0.1:8011',
      accounts,
      live: false,
      saveDeployments: true,
      zksync: true,
    },
    'arbitrum:sepolia': {
      chainId: 421614,
      url: 'https://newest-frequent-road.arbitrum-sepolia.quiknode.pro/9cc668fad730c7cdb200cc119eac221cceb9874d/',
      accounts,
      live: true,
      saveDeployments: true,
    },
    sepolia: {
      chainId: 11155111,
      url: 'https://burned-neat-uranium.ethereum-sepolia.quiknode.pro/06b62ec38390afbfc4cf6f46acd27059a99f5414/',
      accounts,
      live: true,
      saveDeployments: true,
    },
    'zksync:sepolia:stage': {
      url: 'https://sepolia.era.zksync.dev', // The testnet RPC URL of ZKsync Era network.
      ethNetwork: 'sepolia', // The Ethereum Web3 RPC URL, or the identifier of the network (e.g. `mainnet` or `sepolia`)
      zksync: true,
      accounts: accounts,
      saveDeployments: true,
    },
    'zksync:sepolia': {
      url: 'https://sepolia.era.zksync.dev', // The testnet RPC URL of ZKsync Era network.
      ethNetwork: 'sepolia', // The Ethereum Web3 RPC URL, or the identifier of the network (e.g. `mainnet` or `sepolia`)
      zksync: true,
      accounts: accounts,
      saveDeployments: true,
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.8.27',
        eraVersion: '1.0.1',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          metadata: {
            bytecodeHash: 'none',
          },
          viaIR: true,
        },
      },
    ],
  },
}

export default config
