// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";

import {IGameFacet} from "./IGameFacet.sol";
import {GameRoom} from "../room/GameRoom.sol";

contract GameFacet is IGameFacet, GameRoom {
    function joinRoom(GameTypes.RoomType roomType, uint16 roomId, address[] memory cards) external override {
        GameTypes.CardTransferType transferType;
        if (roomType == GameTypes.RoomType.STANDARD) {
            transferType = GameTypes.CardTransferType.USER;
        } else if (roomType == GameTypes.RoomType.NEWBIE) {
            transferType = GameTypes.CardTransferType.MANAGED;
        } else {
            revert InvalidFacetRoomType(roomType);
        }

        GameTypes.JoinCard[] memory joinCards = new GameTypes.JoinCard[](cards.length);
        for (uint256 i = 0; i < cards.length; i++) {
            joinCards[i] = GameTypes.JoinCard({card: cards[i], transferType: transferType});
        }
        _joinRoom(msg.sender, roomType, roomId, joinCards);
    }

    function leaveRoom(GameTypes.RoomType roomType, uint16 roomId) external override {
        _leaveRoom(msg.sender, roomType, roomId);
    }
}
