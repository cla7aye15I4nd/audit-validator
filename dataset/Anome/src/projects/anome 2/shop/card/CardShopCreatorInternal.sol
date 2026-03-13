// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";
import {ShopStorage} from "../ShopStorage.sol";

import {ICard} from "../../token/card/ICard.sol";

import {ICardShopCreatorInternal} from "./ICardShopCreatorInternal.sol";

contract CardShopCreatorInternal is ICardShopCreatorInternal {
    function _createPool(
        address card,
        uint256 initialPrice,
        uint256 sellStartsAt,
        bool isCardMintBanned
    ) internal returns (uint256 index) {
        if (initialPrice == 0) {
            revert InvalidCardCreatePrice();
        }

        ShopStorage.Layout storage data = ShopStorage.layout();

        if (data.cardsIndex[card] != 0) {
            revert AlreadyExists();
        }

        index = data.pools.length;
        ShopTypes.CardAttributes memory cardAttr = ICard(card).getCardAttributes();
        ShopTypes.CardPool memory pool = ShopTypes.CardPool({
            index: index,
            card: ICard(card),
            usdaBalance: 0,
            cardDecreaseVirtualBalance: 1,
            usdaIncreaseVirtualBalance: initialPrice,
            ipRevenue: 0
        });

        data.pools.push(pool);
        data.levelPools[cardAttr.level].push(index);
        data.cardsIndex[card] = index;
        data.sellStartsAt[index] = sellStartsAt;
        data.isCardMintBanned[index] = isCardMintBanned;
    }
}
