 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IAvatarNFTProxy {
 
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