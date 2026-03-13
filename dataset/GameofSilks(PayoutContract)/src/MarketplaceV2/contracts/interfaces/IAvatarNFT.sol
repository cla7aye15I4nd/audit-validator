// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IAvatarNFT {
    // onlyOwner Functions
    // Create getter functions for the above variables
    function _publicSaleTime() external view returns (uint256);

    function _preSaleTime() external view returns (uint256);

    function _maxPerAddress() external view returns (uint256);

    function _presaleMaxPerAddress() external view returns (uint256);

    function _presalePrice() external view returns (uint256);

    function _merkleRoot() external view returns (bytes32);

    function _maxTxPerAddress() external view returns (uint256);

    /**
     * onlyOwner function to mint Avatar NFTS
     * @param to address to mint to
     * @param count amount to mint
     */
    function mint(address to, uint256 count) external;

    function PRICE() external view returns (uint256);

    function _price() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function _maxSupply() external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address);

    function owner() external view returns (address);

    function balanceOf(address owner) external view returns (uint256);

    // Admin Proxy functions
    function setSaleInformation(
        uint256 publicSaleTime,
        uint256 preSaleTime,
        uint256 maxPerAddress,
        uint256 presaleMaxPerAddress,
        uint256 price,
        uint256 presalePrice,
        bytes32 merkleRoot,
        uint256 maxTxPerAddress
    ) external;

    function setBaseUri(string memory baseUri) external;

    function setMerkleRoot(bytes32 merkleRoot) external;

    function pause() external;

    function unpause() external;

    function transferOwnership(address newOwner) external;
}
