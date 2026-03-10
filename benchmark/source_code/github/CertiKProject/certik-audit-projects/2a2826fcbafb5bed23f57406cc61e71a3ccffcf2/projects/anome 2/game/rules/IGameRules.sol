// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";

import {IGameRulesInternal} from "./IGameRulesInternal.sol";

interface IGameRules is IGameRulesInternal {
    function placeCard(GameTypes.RoomType roomType, uint16 roomId, uint8 x, uint8 y, uint8 cardIndex) external;

    function getAllCardsOnBoard(
        GameTypes.RoomType roomType,
        uint16 roomId
    ) external view returns (GameTypes.BoardCard[] memory);

    function getAllCardsInHand(
        GameTypes.RoomType roomType,
        uint16 roomId
    ) external view returns (GameTypes.Card[] memory);

    function getPlayerAllCardsInHand(
        GameTypes.RoomType roomType,
        uint16 roomId,
        address account
    ) external view returns (GameTypes.Card[] memory);

    function getPlayerStatistic(address account) external view returns (GameTypes.PlayerStatistic memory);
}
