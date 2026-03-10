// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IShopAdmin {
    error AdminOnlyCaller();
    error HasNoPausePermission();

    function callerSetNoContractWhitelist(address account, bool isNoContract) external;
    function adminSetPausePermission(address account, bool hasPermission) external;
    function whitelistSetShopPaused(bool isPaused) external;
    function adminSetAccountBanned(address account, bool isBanned) external;
}
