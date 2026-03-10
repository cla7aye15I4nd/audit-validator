// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";

interface IShopUser {
    error InvalidUserAmount();

    event UsdaConverted(address indexed account, uint256 usdaAmount, uint256 baseTokenAmount);

    function convertUsdaToBaseToken(uint256 amount) external;

    function setUserProfile(ShopTypes.UserProfile memory profile) external;

    function getUserProfile(address account) external view returns (ShopTypes.UserProfile memory);
}
