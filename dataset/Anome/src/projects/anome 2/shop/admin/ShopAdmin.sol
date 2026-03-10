// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IShopAdmin} from "./IShopAdmin.sol";
import {ShopStorage} from "../ShopStorage.sol";
import {IConfig} from "../../config/IConfig.sol";
import {IShop} from "../IShop.sol";

import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";

contract ShopAdmin is IShopAdmin, SafeOwnableInternal {
    function callerSetNoContractWhitelist(address account, bool isNoContract) external override {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (msg.sender != data.config.caller()) revert AdminOnlyCaller();
        data.isNoContractWhitelist[account] = isNoContract;
    }

    function adminSetPausePermission(address account, bool hasPermission) external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.hasPausePermission[account] = hasPermission;
    }

    function whitelistSetShopPaused(bool isPaused) external override {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (!data.hasPausePermission[msg.sender]) revert HasNoPausePermission();
        data.isShopPaused = isPaused;
    }

    function adminSetAccountBanned(address account, bool isBanned) external override onlyOwner {
        ShopStorage.layout().isAccountBanned[account] = isBanned;
    }
}
