// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../../lib/openzeppelin/token/ERC20/IERC20.sol";

import {IConfig} from "../../config/IConfig.sol";
import {ShopTypes} from "../ShopTypes.sol";
import {ShopStorage} from "../ShopStorage.sol";
import {IUSDA} from "../../token/usda/IUSDA.sol";
import {UtilsLib} from "../../utils/UtilsLib.sol";

import {IShopUser} from "./IShopUser.sol";
import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";
import {ShopCommonInternal} from "../common/ShopCommonInternal.sol";

contract ShopUser is IShopUser, SafeOwnableInternal, ShopCommonInternal {
    function convertUsdaToBaseToken(uint256 amount) external override commonCheck noContractCall {
        if (amount < 1e3) {
            revert InvalidUserAmount();
        }

        ShopStorage.Layout storage data = ShopStorage.layout();
        IUSDA(data.config.usda()).transferFrom(msg.sender, address(this), amount);
        IUSDA(data.config.usda()).burn(amount);
        uint256 baseTokenAmount = UtilsLib.convertDecimals(amount, data.config.usda(), data.config.baseToken());
        IERC20(data.config.baseToken()).transfer(msg.sender, baseTokenAmount);
        emit UsdaConverted(msg.sender, amount, baseTokenAmount);
    }

    function setUserProfile(ShopTypes.UserProfile memory profile) external override {
        ShopStorage.layout().userProfile[msg.sender] = profile;
    }

    function getUserProfile(address account) external view override returns (ShopTypes.UserProfile memory) {
        return ShopStorage.layout().userProfile[account];
    }
}
