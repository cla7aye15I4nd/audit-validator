// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";
import {GameStorage} from "../GameStorage.sol";

import {IGameMatcher} from "./IGameMatcher.sol";
import {GameRoom} from "../room/GameRoom.sol";

contract GameMatcher is IGameMatcher, GameRoom {
    function enterMatchQueue(
        GameTypes.RoomType roomType,
        address[] memory cards
    ) external avoidRepeatMatch(msg.sender) {
        // 清理旧房间
        _cleanRoom(roomType, 100);

        (uint16 defaultRoomId, uint16 targetRoomId) = _findRoomByState(roomType, GameTypes.States.WAITING, 100);

        if (targetRoomId == defaultRoomId) {
            (defaultRoomId, targetRoomId) = _findRoomByState(roomType, GameTypes.States.EMPTY, 100);
        }

        if (targetRoomId == defaultRoomId) {
            revert NoAvailableRoom();
        }

        // _joinRoom既可以加入等待中的房间, 也可以创建新房间
        GameTypes.CardTransferType transferType;
        if (roomType == GameTypes.RoomType.NEWBIE) {
            transferType = GameTypes.CardTransferType.MANAGED;
        } else if (roomType == GameTypes.RoomType.STANDARD) {
            transferType = GameTypes.CardTransferType.USER;
        } else {
            revert InvalidMatcherRoomType(roomType);
        }

        GameTypes.JoinCard[] memory joinCards = new GameTypes.JoinCard[](cards.length);
        for (uint256 i = 0; i < cards.length; i++) {
            joinCards[i] = GameTypes.JoinCard({card: cards[i], transferType: transferType});
        }
        _joinRoom(msg.sender, roomType, targetRoomId, joinCards);
    }

    function _findRoomByState(
        GameTypes.RoomType roomType,
        GameTypes.States state,
        uint16 checkTimes
    ) internal view returns (uint16 defaultRoomId, uint16 targetRoomId) {
        GameStorage.Layout storage data = GameStorage.layout();
        defaultRoomId = type(uint16).max;
        targetRoomId = defaultRoomId;
        for (uint16 i = 0; i < checkTimes; i++) {
            GameTypes.Room storage room = data.rooms[roomType][i];
            if (room.state == GameTypes.States.GAMING) {
                continue;
            }

            if (room.state == GameTypes.States.WAITING && room.player1 == msg.sender) {
                revert AlreadyInMatchingQueue(i);
            }

            if (room.state == state) {
                targetRoomId = i;
                break;
            }
        }
    }

    function _cleanRoom(GameTypes.RoomType roomType, uint16 checkTimes) internal {
        for (uint16 i = 0; i < checkTimes; i++) {
            if (_shouldTimeoutSettlement(roomType, i)) {
                _requestTimeoutSettlement(roomType, i);
            }
        }
    }

    function leaveMatchQueue(GameTypes.RoomType roomType) external {
        GameStorage.Layout storage data = GameStorage.layout();

        uint256 len = data.playerStatistic[msg.sender].rooms.length;
        if (len == 0) return;

        for (uint256 i = len - 1; i >= 0; i--) {
            uint16 roomId = data.playerStatistic[msg.sender].rooms[i].roomId;
            if (data.playerStatistic[msg.sender].rooms[i].roomType != roomType) {
                continue;
            }

            if (data.rooms[roomType][roomId].state == GameTypes.States.GAMING) {
                continue;
            }

            _leaveRoom(msg.sender, roomType, roomId);

            uint256 lastIndex = data.playerStatistic[msg.sender].rooms.length - 1;
            if (lastIndex == i) {
                data.playerStatistic[msg.sender].rooms.pop();
                break;
            } else {
                data.playerStatistic[msg.sender].rooms[i] = data.playerStatistic[msg.sender].rooms[lastIndex];
                data.playerStatistic[msg.sender].rooms.pop();
            }
        }
    }

    function isInMatchQueue(GameTypes.RoomType roomType, address account) external view returns (bool) {
        GameStorage.Layout storage data = GameStorage.layout();

        for (uint i = 0; i < data.playerStatistic[account].rooms.length; i++) {
            if (data.playerStatistic[account].rooms[i].roomType == roomType) {
                return true;
            }
        }

        return false;
    }

    function getMatchQueueLength(GameTypes.RoomType roomType) external view returns (uint256) {
        GameStorage.Layout storage data = GameStorage.layout();

        uint256 count = 0;
        for (uint16 i = 0; i < 1000; i++) {
            if (data.rooms[roomType][i].state == GameTypes.States.WAITING) {
                count++;
            }
        }

        return count;
    }

    function getMatchWaitingTime(GameTypes.RoomType roomType, address account) external view returns (uint256) {
        GameStorage.Layout storage data = GameStorage.layout();

        for (uint i = 0; i < data.playerStatistic[account].rooms.length; i++) {
            if (data.playerStatistic[account].rooms[i].roomType == roomType) {
                uint16 roomId = data.playerStatistic[account].rooms[i].roomId;
                return block.timestamp - data.roomStartedAt[roomType][roomId];
            }
        }

        return 0;
    }

    modifier avoidRepeatMatch(address account) {
        GameStorage.Layout storage data = GameStorage.layout();
        if (data.playerStatistic[account].rooms.length > 0) {
            revert AlreadyInMatchingQueue(data.playerStatistic[account].rooms[0].roomId);
        }
        _;
    }
}
