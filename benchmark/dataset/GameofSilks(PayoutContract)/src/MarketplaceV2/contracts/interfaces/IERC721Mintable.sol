// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

interface IERC721Mintable {
    function _price() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function _maxSupply() external view returns (uint256);
}