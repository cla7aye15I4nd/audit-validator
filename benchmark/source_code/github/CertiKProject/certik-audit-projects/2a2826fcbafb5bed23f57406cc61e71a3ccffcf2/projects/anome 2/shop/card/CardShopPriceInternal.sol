// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICard} from "../../token/card/ICard.sol";
import {ShopTypes} from "../ShopTypes.sol";
import {ShopStorage} from "../ShopStorage.sol";

import {ICardShopPriceInternal} from "./ICardShopPriceInternal.sol";

contract CardShopPriceInternal is ICardShopPriceInternal {

    /**
     * 价格 = BaseToken余额 / Card流通量
     * Card流通量 = Card总量 - Card合约余额 - Card销毁量
     *
     * 购买卡牌时, 流通量+1, BaseToken余额 + 价格, 所以价格不变
     * 卖出卡牌时, 流通量-1 -> 池子, BaseToken余额 - 价格, 所以价格不变
     * 销毁卡牌时, 流通量-1 -> 池子, BaseToken余额 - (价格 * 60%), 所以价格上涨
     */
    function _priceOf(uint256 index) internal view returns (uint256 price) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.CardPool storage pool = data.pools[index];

        uint256 usdaBalance = pool.usdaBalance + pool.usdaIncreaseVirtualBalance;
        if (usdaBalance == 0) revert InvalidPriceUsdaBalance();

        (uint256 supply, uint256 stock, uint256 destruction, uint256 circulation) = _circulationInfoOf(index);
        if ((stock + destruction) > supply) revert InvalidPriceCardSupply();
        if (circulation == 0) revert InvalidPriceCardCirculation();

        price = usdaBalance / circulation;
        if (price == 0) revert InvalidPrice();

        return price;
    }

    /**
     * 此方法返回的所有量都是NFT个数, 已经去除单位
     * @return supply 供应量
     * @return stock 库存量
     * @return destruction 销毁量
     * @return circulation 流通量
     */
    function _circulationInfoOf(
        uint256 index
    ) internal view returns (uint256 supply, uint256 stock, uint256 destruction, uint256 circulation) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.CardPool storage pool = data.pools[index];
        ICard card = pool.card;

        supply = card.totalSupply() / card.getUnit();
        destruction = card.balanceOf(ShopStorage.HOLE) / card.getUnit();

        stock = card.balanceOf(address(this)) / card.getUnit() - pool.cardDecreaseVirtualBalance;
        if (card.balanceOf(address(this)) % card.getUnit() > 0) {
            stock += 1;
        }

        if ((stock + destruction) <= supply) {
            circulation = supply - (stock + destruction);
        }
    }
}
