// https://github.com/sc-forks/solidity-coverage/blob/master/HARDHAT_README.md
module.exports = {
    skipFiles: [
        "DummyExternalTest.sol",
        "facets/DiamondEtherscanFacet.sol",
        "libraries/LibDiamondEtherscan.sol",
        "dummy/EtherscanImplementation.sol"
    ]
};