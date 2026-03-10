// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";
import {GameStorage} from "../GameStorage.sol";

import {IGameRulesInternal} from "./IGameRulesInternal.sol";
import {GameSettlerInternal} from "../settle/GameSettlerInternal.sol";

contract GameRulesInternal is IGameRulesInternal, GameSettlerInternal {
    function _placeCard(
        address account,
        GameTypes.RoomType roomType,
        uint16 roomId,
        uint8 x,
        uint8 y,
        uint8 cardIndex
    ) internal {
        GameStorage.Layout storage layout = GameStorage.layout();
        GameTypes.Room storage room = layout.rooms[roomType][roomId];
        uint256 battleId = layout.battleId[roomType][roomId];

        // 检查Position是否在范围内
        if (x >= GameStorage.MAX_X || y >= GameStorage.MAX_Y) {
            revert PositionOutOfRange();
        }

        // 检查游戏状态
        if (room.state != GameTypes.States.GAMING) {
            revert RoomStatusError(room.state);
        }

        // 检查游戏是否结束
        if (room.turn > GameStorage.MAX_TURN) {
            revert GameOver();
        }

        // 检查是否是玩家
        if (account != room.player1 && account != room.player2) {
            revert NotInRoom(account);
        }

        // 检查是否是当前玩家回合
        if (room.currentPlayer != account) {
            revert NotYourTurn(account);
        }

        // 检查Position是否已经放置过
        if (_getCardOnBoard(room, x, y).isPlaced) {
            revert PositionAlreadyPlaced();
        }

        // 检查卡牌是否在玩家手中
        if (room.allCards[cardIndex].originalOwner != account) {
            revert CardNotInHand(account);
        }

        if (room.allCards[cardIndex].isPlaced) {
            revert CardAlreadyPlaced();
        }

        // 放置卡牌并翻面
        room.allCards[cardIndex].currentHolder = account;
        room.allCards[cardIndex].isPlaced = true;
        room.allCards[cardIndex].x = x;
        room.allCards[cardIndex].y = y;
        room.board[x][y] = cardIndex;

        emit CardPlaced(roomType, roomId, account, room.allCards[cardIndex], x, y, battleId);

        _tryFlip(room, x, y, battleId);

        // 如果游戏结束, 则结算
        // 如果游戏未结束, 则进入下一回合
        if (room.turn >= GameStorage.MAX_TURN) {
            address winner = _getWinnerByScore(room);
            address loser = _otherPlayer(room, winner);
            SettlementResult memory result = _settleCards(room, winner, loser);

            emit GameEnded(
                roomType,
                roomId,
                GameTypes.EndType.NORMAL,
                msg.sender,
                winner,
                loser,
                result.destroyCard,
                result.winnerCards,
                result.loserCards,
                battleId
            );
            delete layout.battleId[roomType][roomId];
        } else {
            room.turn++;
            room.turnStartedAt = block.timestamp;
            room.currentPlayer = _otherPlayer(room, room.currentPlayer);
        }
    }

    function _tryFlip(GameTypes.Room storage room, uint8 x, uint8 y, uint256 battleId) private {
        GameTypes.Card storage currentCard = _getCardOnBoard(room, x, y);

        // 检查四个方向
        for (uint8 i = 0; i < 4; i++) {
            uint8 nX = x;
            uint8 nY = y;

            if (i == 0) {
                // 左
                if (x == 0) continue;
                nX = x - 1;
            }
            if (i == 1) {
                // 上
                if (y == 0) continue;
                nY = y - 1;
            }
            if (i == 2) {
                // 右
                if (x >= GameStorage.MAX_X - 1) continue;
                nX = x + 1;
            }
            if (i == 3) {
                // 下
                if (y >= GameStorage.MAX_Y - 1) continue;
                nY = y + 1;
            }

            // 获取相邻卡牌
            GameTypes.Card storage neighborCard = _getCardOnBoard(room, nX, nY);

            // 检查相邻位置的卡牌状态
            if (
                !neighborCard.isPlaced ||
                neighborCard.currentHolder == address(0) ||
                neighborCard.currentHolder == currentCard.currentHolder
            ) {
                continue;
            }

            // 比较卡牌数值并翻转
            if (_compareCards(currentCard, neighborCard, i)) {
                neighborCard.currentHolder = currentCard.currentHolder;
                emit CardFlipped(room.roomType, room.roomId, nX, nY, currentCard.currentHolder, battleId);

                // 递归检查被翻转的卡牌
                _tryFlip(room, uint8(nX), uint8(nY), battleId);
            }
        }
    }

    function _compareCards(
        GameTypes.Card memory card,
        GameTypes.Card memory nCard,
        uint8 direction
    ) private pure returns (bool) {
        if (direction == 0) {
            // 左
            return card.left > nCard.right;
        } else if (direction == 1) {
            // 上
            return card.top > nCard.bottom;
        } else if (direction == 2) {
            // 右
            return card.right > nCard.left;
        } else if (direction == 3) {
            // 下
            return card.bottom > nCard.top;
        } else {
            revert AbnormalState();
        }
    }
}
