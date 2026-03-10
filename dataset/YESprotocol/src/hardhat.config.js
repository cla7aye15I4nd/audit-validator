require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-ethers");
require('@openzeppelin/hardhat-upgrades');
require("dotenv").config();

const REPORT_GAS = process.env.REPORT_GAS || false;
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        version: "0.8.30",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    networks: {
        localhost: {
            url: "http://127.0.0.1:8545",
        },
        hardhat: {
            allowUnlimitedContractSize: false,
        },
        mainnet: {
            url: `https://mainnet.infura.io/v3/`,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
        },
        goerli: {
            url: `https://goerli.infura.io/v3/`,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
        },
        bsctest: {
            url: "https://bsc-testnet.public.blastapi.io",
            chainId: 97,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
        },
        bsctestnet: {
            url: "https://data-seed-prebsc-1-s3.binance.org:8545",
            chainId: 97,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
        },
        bscmain: {
            url: "https://bsc-dataseed.binance.org/",
            chainId: 56,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
        },
        arbitrumGoerli: {
            url: "https://goerli-rollup.arbitrum.io/rpc",
            chainId: 421613,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
        },
        arbitrumOne: {
            url: "https://arb1.arbitrum.io/rpc",
            chainId: 42161,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
        },
        emcTest: {
            url: "https://rpc1-sepolia.emc.network",
            chainId: 99879,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
        },
    },
    etherscan: {
        apiKey: {
            mainnet: "D6VKNQPKK2CG3911MBZAEDJ6HZK5JY78AU",
            ropsten: "YOUR_ETHERSCAN_API_KEY",
            rinkeby: "YOUR_ETHERSCAN_API_KEY",
            goerli: "D6VKNQPKK2CG3911MBZAEDJ6HZK5JY78AU",
            kovan: "YOUR_ETHERSCAN_API_KEY",
            // binance smart chain
            bsc: "ADM75SHFIVETCWRUJCUVUXWKHX6E7X4I5V",
            bscTestnet: "ADM75SHFIVETCWRUJCUVUXWKHX6E7X4I5V",
            // huobi eco chain
            heco: "YOUR_HECOINFO_API_KEY",
            hecoTestnet: "YOUR_HECOINFO_API_KEY",
            // fantom mainnet
            opera: "YOUR_FTMSCAN_API_KEY",
            ftmTestnet: "YOUR_FTMSCAN_API_KEY",
            // optimism
            optimisticEthereum: "YOUR_OPTIMISTIC_ETHERSCAN_API_KEY",
            // polygon
            polygon: "YOUR_POLYGONSCAN_API_KEY",
            polygonMumbai: "YOUR_POLYGONSCAN_API_KEY",
            // arbitrum
            arbitrumOne: "E9RW975ZUE1VJPKU45Y336IXEI9CZ4YNWV",
            arbitrumGoerli: "E9RW975ZUE1VJPKU45Y336IXEI9CZ4YNWV",
            // avalanche
            avalanche: "YOUR_SNOWTRACE_API_KEY",
            avalancheFujiTestnet: "YOUR_SNOWTRACE_API_KEY",
            // moonbeam
            moonbeam: "YOUR_MOONBEAM_MOONSCAN_API_KEY",
            moonriver: "YOUR_MOONRIVER_MOONSCAN_API_KEY",
            moonbaseAlpha: "YOUR_MOONBEAM_MOONSCAN_API_KEY",
            // harmony
            harmony: "YOUR_HARMONY_API_KEY",
            harmonyTest: "YOUR_HARMONY_API_KEY",
            // xdai and sokol don't need an API key, but you still need
            // to specify one; any string placeholder will work
            xdai: "api-key",
            sokol: "api-key",
            aurora: "api-key",
            auroraTestnet: "api-key",
        },
    },
    sourcify: {
      enabled: true
    },
};