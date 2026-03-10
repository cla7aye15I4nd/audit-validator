// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IPool {
    function processBuy(address from, address to, uint256 tokenAmount, uint256 usdtAmount) external;
    function processSellFee(address from, address to, uint256 feeAmount) external;
}
