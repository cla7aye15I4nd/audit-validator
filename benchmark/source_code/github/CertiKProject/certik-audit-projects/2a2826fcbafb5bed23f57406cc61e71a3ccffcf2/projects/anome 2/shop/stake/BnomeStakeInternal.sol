// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../../lib/openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router01} from "../../../lib/uniswap_v2/interfaces/IUniswapV2Router01.sol";

import {ICard} from "../../token/card/ICard.sol";
import {IConfig} from "../../config/IConfig.sol";
import {ShopStorage} from "../ShopStorage.sol";
import {ShopTypes} from "../ShopTypes.sol";
import {UtilsLib} from "../../utils/UtilsLib.sol";

import {IBnomeStakeInternal} from "./IBnomeStakeInternal.sol";
import {CardShopPriceInternal} from "../card/CardShopPriceInternal.sol";
import {ShopCommonInternal} from "../common/ShopCommonInternal.sol";

contract BnomeStakeInternal is IBnomeStakeInternal, CardShopPriceInternal, ShopCommonInternal {
    using SafeERC20 for IERC20;

    function _stakeBnome(uint256 amount) internal commonCheck noContractCall {
        ShopStorage.Layout storage l = ShopStorage.layout();
        IConfig config = IConfig(l.config);
        address account = msg.sender;

        IERC20(config.bnome()).safeTransferFrom(account, address(this), amount);

        // 计算高LTV额度
        uint256 value = UtilsLib.convertDecimals(
            _getSwapTokenOut(config.bnome(), config.baseToken(), amount),
            config.baseToken(),
            config.usda()
        );
        uint256 highBorrowLTVLimit = value * 5;
        l.highBorrowLTVLimit[account] += highBorrowLTVLimit;

        // 随机一张卡牌
        uint256 anchorCard = _randomCard();
        uint256 destruction = ICard(l.pools[anchorCard].card).balanceOf(ShopStorage.HOLE) /
            ICard(l.pools[anchorCard].card).getUnit();

        // 创建质押订单
        l.bnomeStakeOrders[account].push(
            ShopTypes.BnomeStakeOrder({
                index: l.bnomeStakeOrders[account].length,
                createdAt: block.timestamp,
                bnomeAmount: amount,
                unstakedAmount: 0,
                anchorCard: anchorCard,
                anchorCardInitialDestruction: destruction
            })
        );

        // 统计
        l.bnomeTotalStaked += amount;
        l.bnomeAccountTotalStaked[account] += amount;
        l.bnomeAccountTotalHighBorrowLTVLimit[account] += highBorrowLTVLimit;
    }

    function _unstakeBnome(uint256 index) internal commonCheck noContractCall {
        ShopStorage.Layout storage l = ShopStorage.layout();
        IConfig config = IConfig(l.config);
        address account = msg.sender;
        ShopTypes.BnomeStakeOrder storage order = l.bnomeStakeOrders[account][index];

        if (order.unstakedAmount >= order.bnomeAmount) {
            revert AlreadyUnstaked();
        }

        uint256 unlockedBnome = _getUnlockedBnome(index);
        if ((unlockedBnome + order.unstakedAmount) > order.bnomeAmount) {
            unlockedBnome = order.bnomeAmount - order.unstakedAmount;
        }

        IERC20(config.bnome()).safeTransfer(account, unlockedBnome);

        order.unstakedAmount += unlockedBnome;
        l.bnomeTotalUnstaked += unlockedBnome;
        l.bnomeAccountTotalUnstaked[account] += unlockedBnome;
    }

    function _getUnlockedBnome(uint256 index) internal view returns (uint256) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        ShopTypes.BnomeStakeOrder storage order = l.bnomeStakeOrders[msg.sender][index];
        (uint256 supply, , uint256 destruction, ) = _circulationInfoOf(order.anchorCard);
        uint256 orderDestruction = destruction - order.anchorCardInitialDestruction;
        uint256 totalUnlocked = (order.bnomeAmount * orderDestruction) / supply;
        return totalUnlocked - order.unstakedAmount;
    }

    function _randomCard() internal returns (uint256) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        
        if (l.pools.length == 0) {
            revert("No pools available");
        }
        
        uint256 anchorCard = UtilsLib.genRandomUint(0, l.pools.length - 1);

        if (l.sellStartsAt[anchorCard] > block.timestamp) {
            return _randomCard();
        }

        if (l.isPoolHide[anchorCard]) {
            return _randomCard();
        }

        if (l.isCardMintBanned[anchorCard]) {
            return _randomCard();
        }

        return anchorCard;
    }

    function _getSwapTokenOut(address tokenA, address tokenB, uint256 amountA) internal view returns (uint256) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        IConfig config = IConfig(l.config);
        IUniswapV2Router01 router = IUniswapV2Router01(config.anomeDexRouter());
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        return router.getAmountsOut(amountA, path)[1];
    }
}
