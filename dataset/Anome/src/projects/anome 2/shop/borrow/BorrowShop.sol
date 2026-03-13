// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";
import {ShopStorage} from "../ShopStorage.sol";
import {IUSDA} from "../../token/usda/IUSDA.sol";

import {IBorrowShop} from "../../shop/borrow/IBorrowShop.sol";
import {BorrowShopInternal} from "../../shop/borrow/BorrowShopInternal.sol";

contract BorrowShop is IBorrowShop, BorrowShopInternal {
    // Write

    function multiBorrow(ShopTypes.Card721[] memory cards) external {
        for (uint i = 0; i < cards.length; i++) {
            _borrow(cards[i].card, cards[i].id);
        }
    }

    function borrow(address card, uint256 cardId) external {
        _borrow(card, cardId);
    }

    function multiRepay(uint256[] memory orderIndexes) external {
        for (uint i = 0; i < orderIndexes.length; i++) {
            _repay(orderIndexes[i]);
        }
    }

    function repay(uint256 orderIndex) external {
        _repay(orderIndex);
    }

    // View

    function getBorrowInfo()
        external
        view
        override
        returns (
            uint256 borrowLtv,
            uint256 highBorrowLTV,
            uint256 borrowIndex,
            uint256 borrowRate,
            uint40 borrowIndexLastUpdateTimestamp
        )
    {
        ShopStorage.Layout storage data = ShopStorage.layout();
        borrowLtv = data.borrowLtv;
        highBorrowLTV = data.highBorrowLTV;
        borrowIndex = data.borrowIndex;
        borrowRate = data.borrowRate;
        borrowIndexLastUpdateTimestamp = data.borrowIndexLastUpdateTimestamp;
    }

    function getAccountBorrowInfo(
        address account
    ) external view override returns (uint256 borrowLtv, uint256 orderCount, uint256 borrowRate) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (data.highBorrowLTVLimit[account] > 0) {
            borrowLtv = data.highBorrowLTV;
        } else {
            borrowLtv = data.borrowLtv;
        }

        orderCount = data.borrowOrderBook[account].length;
        borrowRate = data.borrowRate;
    }

    function calculateBorrowAmount(
        address account,
        address[] memory cards
    ) external view override returns (uint256 borrowAmount) {
        return _calculateBorrowAmount(account, cards);
    }

    function getAllBorrowOrders(
        address account,
        uint256 page,
        uint256 size
    ) external view override returns (ShopTypes.BorrowOrder[] memory result) {
        ShopStorage.Layout storage data = ShopStorage.layout();

        uint256 totalLength = data.borrowOrderBook[account].length;
        if (totalLength == 0) {
            return new ShopTypes.BorrowOrder[](0);
        }

        uint256 start = page * size;
        if (start >= totalLength) {
            revert PageError();
        }

        uint256 end = _min(start + size, totalLength);

        result = new ShopTypes.BorrowOrder[](end - start);
        for (uint i = start; i < end; i++) {
            ShopTypes.BorrowOrder memory order = data.borrowOrderBook[account][i];
            result[i - start] = order;

            if (!order.isRepaid) {
                (uint256 repayAmount, ) = _getRepayAmount(account, i);
                result[i - start].repayAmount = repayAmount;
            }
        }
    }

    function getLatestBorrowOrder(address account) external view override returns (ShopTypes.BorrowOrder memory) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        return data.borrowOrderBook[account][data.borrowOrderBook[account].length - 1];
    }
}
