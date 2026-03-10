// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../../lib/openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {ShopTypes} from "../ShopTypes.sol";
import {ShopStorage} from "../ShopStorage.sol";
import {IUSDA} from "../../token/usda/IUSDA.sol";
import {IConfig} from "../../config/IConfig.sol";

import {MathUtils} from "./MathUtils.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {IBorrowShopInternal} from "./IBorrowShopInternal.sol";
import {CardShopPriceInternal} from "../../shop/card/CardShopPriceInternal.sol";
import {ShopCommonInternal} from "../common/ShopCommonInternal.sol";

contract BorrowShopInternal is IBorrowShopInternal, CardShopPriceInternal, ShopCommonInternal {
    using SafeERC20 for IERC20;
    using SafeERC20 for IUSDA;
    using WadRayMath for uint256;

    function _borrow(address card, uint256 cardId) internal commonCheck noContractCall updateBorrowIndex {
        checkCardAndId(card, cardId);

        address account = msg.sender;
        ShopStorage.Layout storage data = ShopStorage.layout();
        uint256 poolIndex = data.cardsIndex[card];
        ShopTypes.CardPool storage pool = data.pools[poolIndex];

        // 执行借贷操作
        uint256 price = _priceOf(poolIndex);
        uint256 borrowAmount;
        if (data.highBorrowLTVLimit[account] >= price) {
            borrowAmount = (price * data.highBorrowLTV) / ShopStorage.DIVIDEND;
            data.highBorrowLTVLimit[account] -= borrowAmount;
        } else {
            borrowAmount = (data.highBorrowLTVLimit[account] * data.highBorrowLTV) / ShopStorage.DIVIDEND;
            uint256 remaining = price - data.highBorrowLTVLimit[account];
            borrowAmount += (remaining * data.borrowLtv) / ShopStorage.DIVIDEND;
            data.highBorrowLTVLimit[account] = 0;
        }

        pool.card.safeTransferFrom(account, address(this), cardId);
        pool.cardDecreaseVirtualBalance += 1;

        // 转走锚定物, 并且记录数量
        IUSDA(data.config.usda()).transfer(account, borrowAmount);

        // 创建订单
        ShopTypes.BorrowOrder[] storage orders = data.borrowOrderBook[account];
        data.borrowOrderIndex[account][card][cardId] = orders.length;

        // 创建订单
        ShopTypes.BorrowOrder memory order = ShopTypes.BorrowOrder({
            index: orders.length,
            pool: poolIndex,
            isRepaid: false,
            card: pool.card,
            cardId: cardId,
            cardPrice: price,
            borrowIndex: data.borrowIndex,
            borrowAmount: borrowAmount,
            borrowInterest: data.borrowRate,
            createsAt: block.timestamp,
            repayPrice: 0,
            repayIndex: 0,
            repayAmount: 0,
            repayAt: 0
        });
        orders.push(order);

        emit Borrowed(account, order);
    }

    function _calculateBorrowAmount(
        address account,
        address[] memory cards
    ) internal view returns (uint256 borrowAmount) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        uint256 highBorrowLTVLimit = data.highBorrowLTVLimit[account];
        for (uint256 i = 0; i < cards.length; i++) {
            address card = cards[i];
            uint256 poolIndex = data.cardsIndex[card];
            ShopTypes.CardPool storage pool = data.pools[poolIndex];

            if (card == address(0)) {
                continue;
            }

            if (card != address(pool.card)) {
                continue;
            }

            uint256 price = _priceOf(poolIndex);
            if (highBorrowLTVLimit >= price) {
                uint256 currentBorrowAmount = (price * data.highBorrowLTV) / ShopStorage.DIVIDEND;
                highBorrowLTVLimit -= currentBorrowAmount;
                borrowAmount += currentBorrowAmount;
            } else {
                uint256 currentBorrowAmount = (highBorrowLTVLimit * data.highBorrowLTV) / ShopStorage.DIVIDEND;
                uint256 remaining = price - highBorrowLTVLimit;
                currentBorrowAmount += (remaining * data.borrowLtv) / ShopStorage.DIVIDEND;
                highBorrowLTVLimit = 0;
                borrowAmount += currentBorrowAmount;
            }
        }
    }

    function _repay(uint256 orderIndex) internal commonCheck noContractCall updateBorrowIndex {
        address account = msg.sender;
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.BorrowOrder storage order = data.borrowOrderBook[account][orderIndex];
        ShopTypes.CardPool storage pool = data.pools[order.pool];
        uint256 price = _priceOf(order.pool);

        if (order.isRepaid) {
            revert AlreadyRepaid();
        }

        // 滑扣USDA, 本金留在合约中
        (uint256 repayAmount, uint256 interest) = _getRepayAmount(account, orderIndex);
        IUSDA(data.config.usda()).safeTransferFrom(account, address(this), repayAmount);
        IUSDA(data.config.usda()).safeTransfer(data.config.treasury(), interest);

        // 转回卡牌
        pool.card.transfer(account, 1e18);
        pool.cardDecreaseVirtualBalance -= 1;

        // 清理数据状态
        delete data.borrowOrderIndex[account][address(order.card)][order.cardId];
        order.isRepaid = true;
        order.repayPrice = price;
        order.repayIndex = data.borrowIndex;
        order.repayAmount = repayAmount;
        order.repayAt = block.timestamp;

        emit Repaid(account, order);
    }

    modifier updateBorrowIndex() {
        ShopStorage.Layout storage data = ShopStorage.layout();

        uint256 currentIndex = data.borrowIndex;
        if (currentIndex == 0) {
            currentIndex = 1e27;
        }

        uint256 interest = MathUtils.calculateCompoundedInterest(
            data.borrowRate,
            data.borrowIndexLastUpdateTimestamp
        );
        data.borrowIndex = interest.rayMul(currentIndex);
        data.borrowIndexLastUpdateTimestamp = uint40(block.timestamp);
        _;
    }

    function _getRepayAmount(
        address account,
        uint256 orderIndex
    ) internal view returns (uint256 repayAmount, uint256 interest) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.BorrowOrder memory order = data.borrowOrderBook[account][orderIndex];
        repayAmount = order.borrowAmount * 1e27;
        repayAmount = repayAmount.rayDiv(order.borrowIndex).rayMul(data.borrowIndex);
        repayAmount = repayAmount / 1e27;

        interest = repayAmount - order.borrowAmount;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
