// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";

interface IGameFacet {
    error InvalidFacetRoomType(GameTypes.RoomType roomType);

    function joinRoom(GameTypes.RoomType roomType, uint16 roomId, address[] memory cards) external;

    function leaveRoom(GameTypes.RoomType roomType, uint16 roomId) external;
}
