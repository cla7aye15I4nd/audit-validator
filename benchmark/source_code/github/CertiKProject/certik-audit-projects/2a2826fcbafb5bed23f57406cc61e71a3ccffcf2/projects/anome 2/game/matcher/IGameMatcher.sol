// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";

interface IGameMatcher {
    error AlreadyInMatchingQueue(uint16 roomId);
    error InvalidMatcherRoomType(GameTypes.RoomType roomType);
    error NoAvailableRoom();

    function enterMatchQueue(GameTypes.RoomType roomType, address[] memory cards) external;

    function leaveMatchQueue(GameTypes.RoomType roomType) external;

    function isInMatchQueue(GameTypes.RoomType roomType, address account) external view returns (bool);

    function getMatchQueueLength(GameTypes.RoomType roomType) external view returns (uint256);

    function getMatchWaitingTime(GameTypes.RoomType roomType, address account) external view returns (uint256);
}
