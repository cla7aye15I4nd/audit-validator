// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";

interface IGameRoomInternal {
    error RoomIsFull();
    // 1 -> 卡牌数量错误
    // 2 -> 超过两张七级卡牌
    error RoomParamsError(uint256 code);
    error CanNotLeaveRoom();
    error CanNotJoinRoom();
    error NotTimeout();
    error ManagedCardNotEnough(address card);
    error RoomContractManagedCardNotEnough(address card);
    error CardNotInPool(address card);

    struct RoomInfo {
        GameTypes.RoomType roomType;
        uint16 roomId;
        uint256 battleId;
        GameTypes.States state;
        address player1;
        address player2;
        uint8 turn;
        uint256 turnStartedAt;
        address currentPlayer;
    }

    event PlayerJoined(
        GameTypes.RoomType roomType,
        uint16 roomId,
        address player,
        uint256 battleId
    );

    event PlayerLeft(
        GameTypes.RoomType roomType,
        uint16 roomId,
        address player,
        uint256 battleId
    );
}
