// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";

import {IGameRoomInternal} from "./IGameRoomInternal.sol";

interface IGameRoom is IGameRoomInternal {
    function requestTimeoutSettlement(GameTypes.RoomType roomType, uint16 roomId) external;

    function shouldTimeoutSettlement(GameTypes.RoomType roomType, uint16 roomId) external view returns (bool);

    function getRoomInfo(GameTypes.RoomType roomType, uint16 roomId) external view returns (RoomInfo memory);

    function getRoomInfoList(
        GameTypes.RoomType roomType,
        uint16 startId,
        uint16 endId
    ) external view returns (RoomInfo[] memory);

    function getPlayerRooms(address account) external view returns (RoomInfo[] memory);
}
