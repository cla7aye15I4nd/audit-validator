// SPDX-License-Identifier: MIT
// solhint-disable-next-line one-contract-per-file
pragma solidity ^0.8.20;

interface IExternalWhitelistImpl {
    function getWhitelistImpl() external view returns (address);
}

interface IExternalBlacklistImpl {
    function getBlacklistImpl() external view returns (address);
}