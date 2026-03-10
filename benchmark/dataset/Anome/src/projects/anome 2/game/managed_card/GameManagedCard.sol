// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";
import {GameStorage} from "../GameStorage.sol";
import {ICard} from "../../token/card/ICard.sol";
import {IShop} from "../../shop/IShop.sol";

import {IGameManagedCard} from "./IGameManagedCard.sol";

contract GameManagedCard is IGameManagedCard {
    function getManagedCard(address account) external view returns (GameTypes.ManagedCard[] memory) {
        GameStorage.Layout storage layout = GameStorage.layout();
        uint256 cardCount = IShop(layout.config.shop()).getPoolSize();
        GameTypes.ManagedCard[] memory managedCards = new GameTypes.ManagedCard[](cardCount);
        for (uint256 i = 0; i < cardCount; i++) {
            address card = IShop(layout.config.shop()).getPoolCardSimple(i);
            managedCards[i] = GameTypes.ManagedCard({
                card: card,
                balance: layout.managedCardBalance[account][card]
            });
        }
        return managedCards;
    }
}
