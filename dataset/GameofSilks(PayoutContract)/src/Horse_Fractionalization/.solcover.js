// https://github.com/sc-forks/solidity-coverage/blob/master/HARDHAT_README.md
module.exports = {
    skipFiles: [
        "Diamond.sol",
        "Migrations.sol",
        "facets/DiamondLoupeFacet.sol",
        "facets/DiamondCutFacet.sol",
        "facets/DiamondInit.sol",
        "facets/OwnershipFacet.sol",
        "facets/HorseFractionalizeFacet.sol",
        "facets/HorsePartnershipConfigFacet.sol",
        "facets/HorsePartnershipTokenFacet.sol",
        "facets/HorseReconstituteFacet.sol",
        "facets/HorsePartnershipAccessControlFacet.sol",
        "libraries/LibDiamond.sol",
        "libraries/LibAccessControl.sol",
        "libraries/LibHorsePartnership.sol",
        "upgradeinitializers/DiamondInit.sol",
        "test_contracts/HorseDummy.sol",
        "test_contracts/Index.sol",
        "test_contracts/MarketPlaceDummy.sol",
        "test_contracts/TestFacetV1.sol",
        "test_contracts/TestFacetV2.sol"
    ]
};