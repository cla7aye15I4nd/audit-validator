// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";
import {GameStorage} from "../GameStorage.sol";

import {IGameRoom} from "./IGameRoom.sol";
import {GameRoomInternal} from "./GameRoomInternal.sol";

contract GameRoom is IGameRoom, GameRoomInternal {
    function requestTimeoutSettlement(GameTypes.RoomType roomType, uint16 roomId) external override {
        _requestTimeoutSettlement(roomType, roomId);
    }

    function shouldTimeoutSettlement(
        GameTypes.RoomType roomType,
        uint16 roomId
    ) external view override returns (bool) {
        return _shouldTimeoutSettlement(roomType, roomId);
    }

    function getRoomInfo(
        GameTypes.RoomType roomType,
        uint16 roomId
    ) public view override returns (RoomInfo memory) {
        GameStorage.Layout storage layout = GameStorage.layout();
        GameTypes.Room storage room = layout.rooms[roomType][roomId];
        return
            RoomInfo({
                roomType: room.roomType,
                roomId: roomId,
                battleId: layout.battleId[roomType][roomId],
                state: room.state,
                player1: room.player1,
                player2: room.player2,
                turn: room.turn,
                turnStartedAt: room.turnStartedAt,
                currentPlayer: room.currentPlayer
            });
    }

    function getRoomInfoList(
        GameTypes.RoomType roomType,
        uint16 startId,
        uint16 endId
    ) external view override returns (RoomInfo[] memory) {
        RoomInfo[] memory roomInfos = new RoomInfo[](endId - startId + 1);
        for (uint16 i = startId; i <= endId; i++) {
            roomInfos[i - startId] = getRoomInfo(roomType, i);
        }
        return roomInfos;
    }

    function getPlayerRooms(address account) external view override returns (RoomInfo[] memory) {
        GameTypes.PlayerStatistic memory playerStatistic = GameStorage.layout().playerStatistic[account];
        RoomInfo[] memory roomInfos = new RoomInfo[](playerStatistic.rooms.length);
        for (uint i = 0; i < playerStatistic.rooms.length; i++) {
            GameTypes.PlayerRoom memory playerRoom = playerStatistic.rooms[i];
            roomInfos[i] = getRoomInfo(playerRoom.roomType, playerRoom.roomId);
        }
        return roomInfos;
    }
}
