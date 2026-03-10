// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IWNativeRelayer {
    function withdraw(uint256 _amount) external;
}
