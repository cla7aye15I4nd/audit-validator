// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../../lib/openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {ShopTypes} from "../ShopTypes.sol";
import {ShopStorage} from "../ShopStorage.sol";
import {ICard} from "../../token/card/ICard.sol";
import {IUSDA} from "../../token/usda/IUSDA.sol";
import {UtilsLib} from "../../utils/UtilsLib.sol";

import {ICardShopInternal} from "./ICardShopInternal.sol";
import {CardShopPriceInternal} from "./CardShopPriceInternal.sol";
import {CardShopCreatorInternal} from "./CardShopCreatorInternal.sol";
import {ShopCommonInternal} from "../common/ShopCommonInternal.sol";

contract CardShopInternal is
    ICardShopInternal,
    CardShopPriceInternal,
    CardShopCreatorInternal,
    ShopCommonInternal
{
    using SafeERC20 for IERC20;

    function _buyCard(uint256 index, uint256 count, address recipient) internal commonCheck {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.CardPool storage pool = data.pools[index];

        if (address(pool.card) == address(0)) revert InvalidCardAddress();
        if (data.isCardMintBanned[index] && msg.sender != data.config.caller()) revert CardMintBanned();

        (, uint256 stock, , ) = _circulationInfoOf(index);
        if (count == 0) revert InvalidShopAmount();
        if (count > stock) revert SoldOut();

        uint256 usdaPrice = _priceOf(index) * count;
        uint256 baseTokenAmount = UtilsLib.convertDecimals(usdaPrice, data.config.usda(), data.config.baseToken());
        pool.usdaBalance += usdaPrice;

        // 为了支持1:1兑换, 所以需要将baseToken转到合约
        // IERC20(data.config.baseToken()).safeTransferFrom(msg.sender, address(this), baseTokenAmount);
        IERC20(data.config.baseToken()).safeTransferFrom(msg.sender, data.config.buyCardPayee(), baseTokenAmount);
        IUSDA(data.config.usda()).mint(address(this), usdaPrice);

        pool.card.transfer(recipient, count * pool.card.getUnit());

        emit CardBought(recipient, address(pool.card), count * pool.card.getUnit(), baseTokenAmount);
    }

    // function _buyCardByBaseToken(
    //     uint256 index,
    //     uint256 baseTokenAmount,
    //     address recipient
    // ) internal returns (uint256 cardAmount) {
    //     ShopStorage.Layout storage data = ShopStorage.layout();
    //     ShopTypes.CardPool storage pool = data.pools[index];

    //     if (address(pool.card) == address(0)) revert InvalidCardAddress();
    //     if (data.isCardMintBanned[index] && msg.sender != data.config.caller()) revert CardMintBanned();

    //     uint256 usdaAmount = UtilsLib.convertDecimals(
    //         baseTokenAmount,
    //         data.config.baseToken(),
    //         data.config.usda()
    //     );
    //     cardAmount = ((usdaAmount * pool.card.getUnit()) / _priceOf(index)) - 1;
    //     if (cardAmount == 0) revert InvalidShopAmount();

    //     (, uint256 stock, , ) = _circulationInfoOf(index);
    //     if (cardAmount > stock * pool.card.getUnit()) revert SoldOut();

    //     pool.usdaBalance += usdaAmount;
    //     // 为了支持1:1兑换, 所以需要将baseToken转到合约
    //     // IERC20(data.config.baseToken()).safeTransferFrom(msg.sender, address(this), baseTokenAmount);
    //     IERC20(data.config.baseToken()).safeTransferFrom(msg.sender, data.config.buyCardPayee(), baseTokenAmount);
    //     IUSDA(data.config.usda()).mint(address(this), usdaAmount);

    //     pool.card.transfer(recipient, cardAmount);

    //     emit CardBought(recipient, address(pool.card), cardAmount, baseTokenAmount);
    // }

    function _sellCard(uint256 index, uint256 count) internal commonCheck noContractCall {
        if (count == 0) revert InvalidShopAmount();

        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.CardPool storage pool = data.pools[index];

        if (data.sellStartsAt[index] > block.timestamp) revert CardRefundNotStarted();
        if (address(pool.card) == address(0)) revert InvalidCardAddress();

        uint256 price = _priceOf(index) * count;
        pool.usdaBalance -= price;
        IUSDA(data.config.usda()).transfer(data.config.treasury(), (price * 5) / 100);
        IUSDA(data.config.usda()).transfer(msg.sender, (price * 95) / 100);

        pool.card.safeTransferFrom(msg.sender, address(this), count * pool.card.getUnit(), "");

        emit CardSell(msg.sender, address(pool.card), count * pool.card.getUnit(), price);
    }

    function _fillCardItemInfo(uint256 id) internal view returns (ShopTypes.CardItem memory item) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (data.isPoolHide[id]) {
            return item;
        }

        ShopTypes.CardPool memory pool = data.pools[id];
        (uint256 supply, uint256 stock, uint256 destruction, uint256 circulation) = _circulationInfoOf(id);

        item = ShopTypes.CardItem({
            index: id,
            card: pool.card,
            initialPrice: pool.usdaIncreaseVirtualBalance,
            currentPrice: _priceOf(id),
            tokenUri: pool.card.tokenURI(0),
            supply: supply,
            stock: stock,
            destruction: destruction,
            circulation: circulation,
            userBalance: pool.card.balanceOf(msg.sender),
            ipRevenue: pool.ipRevenue,
            attr: pool.card.getCardAttributes()
        });
    }
}
