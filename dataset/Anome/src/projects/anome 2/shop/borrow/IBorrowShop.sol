// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";

import {IBorrowShopInternal} from "./IBorrowShopInternal.sol";

interface IBorrowShop is IBorrowShopInternal {
    // Write

    function multiBorrow(ShopTypes.Card721[] memory cards) external;

    function borrow(address card, uint256 cardId) external;

    function multiRepay(uint256[] memory orderIndexes) external;

    function repay(uint256 orderIndex) external;

    // view

    function getBorrowInfo()
        external
        view
        returns (
            uint256 borrowLtv,
            uint256 highBorrowLTV,
            uint256 borrowIndex,
            uint256 borrowRate,
            uint40 borrowIndexLastUpdateTimestamp
        );

    function getAccountBorrowInfo(
        address account
    ) external view returns (uint256 borrowLtv, uint256 orderCount, uint256 borrowRate);

    function calculateBorrowAmount(
        address account,
        address[] memory cards
    ) external view returns (uint256 borrowAmount);

    function getAllBorrowOrders(
        address account,
        uint256 page,
        uint256 size
    ) external view returns (ShopTypes.BorrowOrder[] memory);

    function getLatestBorrowOrder(address account) external view returns (ShopTypes.BorrowOrder memory);
}
