// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import 'dotenv/config'

import 'hardhat-deploy'
import 'hardhat-contract-sizer'
import '@nomiclabs/hardhat-ethers'
import "@nomicfoundation/hardhat-verify";
import '@layerzerolabs/toolbox-hardhat'
import { HardhatUserConfig, HttpNetworkAccountsUserConfig } from 'hardhat/types'

import { EndpointId } from '@layerzerolabs/lz-definitions'

import './tasks/index'

// Set your preferred authentication method
//
// If you prefer using a mnemonic, set a MNEMONIC environment variable
// to a valid mnemonic
const MNEMONIC = process.env.MNEMONIC

// If you prefer to be authenticated using a private key, set a PRIVATE_KEY environment variable
const PRIVATE_KEY = process.env.PRIVATE_KEY

const accounts: HttpNetworkAccountsUserConfig | undefined = MNEMONIC
    ? { mnemonic: MNEMONIC }
    : PRIVATE_KEY
      ? [PRIVATE_KEY]
      : undefined

if (accounts == null) {
    console.warn(
        'Could not find MNEMONIC or PRIVATE_KEY environment variables. It will not be possible to execute transactions in your example.'
    )
}

const config: HardhatUserConfig = {
    sourcify: { enabled: true },
    paths: {
        cache: 'cache/hardhat',
    },
    solidity: {
        compilers: [
            {
                version: '0.8.22',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    networks: {
		sepolia: {
			url: process.env.RPC_URL_SEPOLIA!,
			accounts,
			chainId: 11155111,
		},
		base: {
			eid: EndpointId.BASE_V2_MAINNET,
			url: process.env.RPC_URL_BASE!,
			accounts,
			chainId: 8453,
		},
		bsc: {
			eid: EndpointId.BSC_V2_MAINNET,
			url: process.env.RPC_URL_BSC!,
			accounts,
			chainId: 56,
		},
        hardhat: {
            // Need this for testing because TestHelperOz5.sol is exceeding the compiled contract size limit
            allowUnlimitedContractSize: true,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0, // wallet address of index[0], of the mnemonic in .env
        },
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY,
        /*customChains: [
            {
            network: "base",
            chainId: 8453,
            urls: {
                apiURL: "https://api.basescan.org/api",
                browserURL: "https://basescan.org",
            },
            },
            {
            network: "bsc",
            chainId: 56,
            urls: {
                apiURL: "https://api.bscscan.com/api",
                browserURL: "https://bscscan.com",
            },
            },
        ],*/
    },
}

export default config
