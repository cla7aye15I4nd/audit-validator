// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";
import {GameStorage} from "../GameStorage.sol";

import {IGameRules} from "./IGameRules.sol";
import {GameRulesInternal} from "./GameRulesInternal.sol";

contract GameRules is IGameRules, GameRulesInternal {
    function placeCard(
        GameTypes.RoomType roomType,
        uint16 roomId,
        uint8 x,
        uint8 y,
        uint8 cardIndex
    ) external override {
        _placeCard(msg.sender, roomType, roomId, x, y, cardIndex);
    }

    function getAllCardsOnBoard(
        GameTypes.RoomType roomType,
        uint16 roomId
    ) external view override returns (GameTypes.BoardCard[] memory boardCards) {
        GameTypes.Room storage room = GameStorage.layout().rooms[roomType][roomId];

        boardCards = new GameTypes.BoardCard[](GameStorage.MAX_X * GameStorage.MAX_Y);
        for (uint8 x = 0; x < GameStorage.MAX_X; x++) {
            for (uint8 y = 0; y < GameStorage.MAX_Y; y++) {
                GameTypes.Card memory card = _getCardOnBoard(room, x, y);
                boardCards[y * GameStorage.MAX_X + x] = GameTypes.BoardCard({x: x, y: y, cardInfo: card});
            }
        }
    }

    function getAllCardsInHand(
        GameTypes.RoomType roomType,
        uint16 roomId
    ) external view override returns (GameTypes.Card[] memory handCards) {
        GameTypes.Room storage room = GameStorage.layout().rooms[roomType][roomId];
        handCards = new GameTypes.Card[](room.handCards[msg.sender].length);
        for (uint i = 0; i < room.handCards[msg.sender].length; i++) {
            handCards[i] = room.allCards[room.handCards[msg.sender][i]];
        }
    }

    function getPlayerAllCardsInHand(
        GameTypes.RoomType roomType,
        uint16 roomId,
        address account
    ) external view override returns (GameTypes.Card[] memory) {
        GameTypes.Room storage room = GameStorage.layout().rooms[roomType][roomId];
        GameTypes.Card[] memory handCards = new GameTypes.Card[](room.handCards[account].length);
        for (uint i = 0; i < room.handCards[account].length; i++) {
            handCards[i] = room.allCards[room.handCards[account][i]];
        }
        return handCards;
    }

    function getPlayerStatistic(
        address account
    ) external view override returns (GameTypes.PlayerStatistic memory) {
        return GameStorage.layout().playerStatistic[account];
    }
}
