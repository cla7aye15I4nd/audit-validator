// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";

interface IGameRulesInternal {
    error GameOver();
    error GameNotOver();
    error NotYourTurn(address account);
    error CardAlreadyPlaced();
    error PositionOutOfRange();
    error PositionAlreadyPlaced();
    error CardNotInHand(address account);

    event CardPlaced(
        GameTypes.RoomType roomType,
        uint16 roomId,
        address player,
        GameTypes.Card cardInfo,
        uint8 x,
        uint8 y,
        uint256 battleId
    );

    event CardFlipped(
        GameTypes.RoomType roomType,
        uint16 roomId,
        uint8 x,
        uint8 y,
        address newHolder,
        uint256 battleId
    );
}
