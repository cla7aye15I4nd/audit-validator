// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";
import {GameStorage} from "../GameStorage.sol";
import {ICard} from "../../token/card/ICard.sol";
import {ShopTypes} from "../../shop/ShopTypes.sol";
import {IShop} from "../../shop/IShop.sol";

import {IGameRoomInternal} from "./IGameRoomInternal.sol";
import {GameSettlerInternal} from "../settle/GameSettlerInternal.sol";

contract GameRoomInternal is IGameRoomInternal, GameSettlerInternal {
    function _joinRoom(
        address account,
        GameTypes.RoomType roomType,
        uint16 roomId,
        GameTypes.JoinCard[] memory cards
    ) internal {
        GameStorage.Layout storage layout = GameStorage.layout();
        GameTypes.Room storage room = layout.rooms[roomType][roomId];

        if (room.state != GameTypes.States.EMPTY && room.state != GameTypes.States.WAITING) {
            revert RoomStatusError(room.state);
        }

        if (room.player1 != address(0) && room.player2 != address(0)) {
            revert RoomIsFull();
        }

        if (cards.length != GameStorage.PLAYER_CARD_COUNT) {
            revert RoomParamsError(1);
        }

        if (room.player1 == account || room.player2 == account) {
            revert CanNotJoinRoom();
        }

        // 记录用户所在的房间
        layout.playerStatistic[account].rooms.push(GameTypes.PlayerRoom({roomId: roomId, roomType: roomType}));

        // 处理房间信息
        uint8 offset = 0;
        if (room.player1 == address(0) && room.player2 == address(0)) {
            room.roomType = roomType;
            room.roomId = roomId;
            room.turn = 0;
            room.state = GameTypes.States.WAITING;
            room.player1 = account;
            room.turnStartedAt = 0;
            layout.roomStartedAt[roomType][roomId] = block.timestamp;
            layout.battleId[roomType][roomId] = uint256(
                keccak256(abi.encodePacked(account, roomType, roomId, block.timestamp))
            );
        } else if (room.player1 != address(0) && room.player2 == address(0)) {
            room.state = GameTypes.States.GAMING;
            room.player2 = account;
            room.turnStartedAt = block.timestamp;
            offset = GameStorage.PLAYER_CARD_COUNT;

            // 随机设定出牌方
            if (uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp))) % 2 == 1) {
                room.currentPlayer = room.player1;
            } else {
                room.currentPlayer = room.player2;
            }
        } else {
            revert RoomIsFull();
        }

        // 处理卡牌的验证, 转账, 以及信息记录
        uint8 level7Count = 0;
        for (uint8 i = 0; i < cards.length; i++) {
            ICard card = ICard(cards[i].card);
            ShopTypes.CardAttributes memory attr = card.getCardAttributes();

            IShop shop = IShop(GameStorage.layout().config.shop());
            if (!shop.isCardInPool(address(card))) {
                revert CardNotInPool(address(card));
            }

            if (cards[i].transferType == GameTypes.CardTransferType.USER) {
                card.transferFrom(account, address(this), card.getUnit());
            } else {
                if (layout.managedCardBalance[account][address(card)] < card.getUnit()) {
                    revert ManagedCardNotEnough(address(card));
                }
                layout.managedCardBalance[account][address(card)] -= card.getUnit();
            }

            room.allCards.push(
                GameTypes.Card({
                    index: i + offset,
                    card: cards[i].card,
                    cardTransferType: cards[i].transferType,
                    level: uint8(attr.level),
                    top: uint8(attr.top),
                    right: uint8(attr.right),
                    bottom: uint8(attr.bottom),
                    left: uint8(attr.left),
                    originalOwner: account,
                    currentHolder: address(0),
                    isPlaced: false,
                    x: 0,
                    y: 0
                })
            );

            room.handCards[account].push(i + offset);

            if (attr.level >= 7) {
                level7Count++;
            }
            if (level7Count > 2) {
                revert RoomParamsError(2);
            }
        }

        // 增加一个额外值, 在获取的时候返回默认值时使用
        if (room.allCards.length == (GameStorage.PLAYER_CARD_COUNT * 2)) {
            room.allCards.push(
                GameTypes.Card({
                    index: 0,
                    card: address(0),
                    cardTransferType: GameTypes.CardTransferType.USER,
                    level: 0,
                    top: 0,
                    right: 0,
                    bottom: 0,
                    left: 0,
                    originalOwner: address(0),
                    currentHolder: address(0),
                    isPlaced: false,
                    x: 0,
                    y: 0
                })
            );
        }

        emit PlayerJoined(roomType, roomId, account, layout.battleId[roomType][roomId]);

        if (room.player1 != address(0) && room.player2 != address(0)) {
            emit GameStarted(
                roomType,
                roomId,
                room.player1,
                room.player2,
                room.currentPlayer,
                layout.battleId[roomType][roomId]
            );
        }
    }

    function _leaveRoom(address account, GameTypes.RoomType roomType, uint16 roomId) internal {
        GameStorage.Layout storage layout = GameStorage.layout();
        GameTypes.Room storage room = layout.rooms[roomType][roomId];

        if (room.state != GameTypes.States.WAITING) {
            revert RoomStatusError(room.state);
        }

        if (room.player1 != account) {
            revert NotInRoom(account);
        }

        if (room.player2 != address(0)) {
            revert CanNotLeaveRoom();
        }

        for (uint8 i = 0; i < room.allCards.length; i++) {
            ICard card = ICard(room.allCards[i].card);
            if (room.allCards[i].cardTransferType == GameTypes.CardTransferType.USER) {
                card.transfer(account, card.getUnit());
            } else {
                layout.managedCardBalance[account][address(card)] += card.getUnit();
            }
        }

        _cleanRoom(room);

        emit PlayerLeft(roomType, roomId, account, layout.battleId[roomType][roomId]);
        delete layout.battleId[roomType][roomId];
    }

    function _requestTimeoutSettlement(GameTypes.RoomType roomType, uint16 roomId) internal {
        GameStorage.Layout storage layout = GameStorage.layout();
        GameTypes.Room storage room = layout.rooms[roomType][roomId];
        uint256 battleId = layout.battleId[roomType][roomId];

        if (!_shouldTimeoutSettlement(roomType, roomId)) {
            revert NotTimeout();
        }

        address winner = _otherPlayer(room, room.currentPlayer);
        address loser = room.currentPlayer;
        SettlementResult memory result = _settleCards(room, winner, loser);

        emit GameEnded(
            roomType,
            roomId,
            GameTypes.EndType.TIMEOUT,
            msg.sender,
            winner,
            loser,
            result.destroyCard,
            result.winnerCards,
            result.loserCards,
            battleId
        );
        delete layout.battleId[roomType][roomId];
    }

    function _shouldTimeoutSettlement(GameTypes.RoomType roomType, uint16 roomId) internal view returns (bool) {
        GameTypes.Room storage room = GameStorage.layout().rooms[roomType][roomId];

        if (room.turnStartedAt == 0) {
            return false;
        }

        if (block.timestamp < (room.turnStartedAt + GameStorage.TIMEOUT)) {
            return false;
        }

        if (room.state == GameTypes.States.EMPTY || room.state == GameTypes.States.WAITING) {
            return false;
        }

        if (room.state == GameTypes.States.GAMING) {
            return true;
        }

        return true;
    }
}
