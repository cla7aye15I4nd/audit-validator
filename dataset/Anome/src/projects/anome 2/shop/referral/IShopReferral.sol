// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";

import {IShopReferralInternal} from "./IShopReferralInternal.sol";

interface IShopReferral is IShopReferralInternal {
    // Write

    function buyCode() external payable;

    function bindSponsor(uint256 code) external;

    function bindRecruit(address recruit, address card, uint256 amount) external;

    // View

    function isAccountCreated(address account) external view returns (bool);

    function getAccountCode(address account) external view returns (uint256);

    function getAccountByCode(uint256 code) external view returns (address);

    function getSponsor(address account) external view returns (address);

    function getRecruits(address account) external view returns (ShopTypes.Recruit[] memory);

    function getDownlines(address account) external view returns (ShopTypes.Downline[] memory);

    function getUplines(address account, uint256 length) external view returns (address[] memory);

    function adminCreateCode(address account) external;

    function adminRecreateCode(address account) external;

    function adminSetCode(address account, uint256 code) external;

    function adminRemoveCode(address account, bool isRemoveRelation) external;

    function adminBindSponsor(address account, address sponsor) external;

    function adminSetReferral(address account, address sponsor) external;

    function adminRemoveRelation(address account) external;

    function callerBindSponsor(address account, uint256 sponsorCode) external;

    function callerBatchBindSponsor(address[] memory accounts, address[] memory sponsors) external;

    function callerSetCode(address[] memory accounts, uint256[] memory codes) external;
}
