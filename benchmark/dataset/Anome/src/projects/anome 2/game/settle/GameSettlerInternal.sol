// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";
import {IShop} from "../../shop/IShop.sol";
import {ICard} from "../../token/card/ICard.sol";
import {GameStorage} from "../GameStorage.sol";
import {IGameSettlerInternal} from "./IGameSettlerInternal.sol";

contract GameSettlerInternal is IGameSettlerInternal {
    struct SettlementResult {
        address destroyCard;
        uint8 destroyIndex;
        uint256 destroyValue;
        uint256 xnomeAmount;
        address[] winnerCards;
        address[] loserCards;
        uint256 winnerCardCost;
        uint256 loserCardCost;
        uint256 winnerVnomeAmount;
        uint256 loserVnomeAmount;
        uint256 winnerSuperiorVnomeAmount;
        uint256 loserSuperiorVnomeAmount;
        uint256 wkAmount;
    }

    function _settleCards(
        GameTypes.Room storage room,
        address winner,
        address loser
    ) internal returns (SettlementResult memory result) {
        GameStorage.Layout storage data = GameStorage.layout();
        IShop shop = IShop(data.config.shop());

        // 新手场不销毁卡牌, 也不产生vnome和wk, 所以也不需要调用shop
        if (room.roomType == GameTypes.RoomType.NEWBIE) {
            result = _distributeCards(result, room, shop, winner, result.destroyIndex);
        } else {
            result = _destroyCard(room, shop, winner, loser);
            result = _distributeCards(result, room, shop, winner, result.destroyIndex);

            (
                result.winnerVnomeAmount,
                result.loserVnomeAmount,
                result.winnerSuperiorVnomeAmount,
                result.loserSuperiorVnomeAmount,
                result.wkAmount
            ) = shop.onBattled(
                winner,
                loser,
                100e18,
                result.winnerCardCost,
                result.loserCardCost,
                result.destroyValue
            );
        }

        _cleanRoom(room);
        _savePlayerStatistic(room, winner, loser);

        return result;
    }

    function _destroyCard(
        GameTypes.Room storage room,
        IShop shop,
        address winner,
        address loser
    ) private returns (SettlementResult memory result) {
        if (room.allCards.length == 0) {
            return result;
        }

        // 找到价格最低的卡牌, 得到destroyIndex
        uint256 destroyIndex = 0;
        uint256 lowestPrice = type(uint256).max;
        for (uint i = 0; i < room.allCards.length; i++) {
            if (room.allCards[i].card == address(0)) {
                continue;
            }

            if (room.allCards[i].originalOwner == winner) {
                result.winnerCardCost += shop.getPriceByAddress(room.allCards[i].card);
            } else {
                result.loserCardCost += shop.getPriceByAddress(room.allCards[i].card);
            }

            uint256 price = shop.getPriceByAddress(room.allCards[i].card);
            if (price < lowestPrice) {
                lowestPrice = price;
                destroyIndex = i;
            }
        }

        // 销毁卡牌
        result.destroyCard = room.allCards[destroyIndex].card;
        result.destroyIndex = room.allCards[destroyIndex].index;
        address destoryCardOwner = room.allCards[destroyIndex].originalOwner;

        ICard destroyCardContract = ICard(result.destroyCard);
        destroyCardContract.approve(address(shop), destroyCardContract.getUnit());
        shop.destroyCard(destoryCardOwner, result.destroyCard, winner, loser);
    }

    function _distributeCards(
        SettlementResult memory result,
        GameTypes.Room storage room,
        IShop shop,
        address winner,
        uint8 destroyIndex
    ) private returns (SettlementResult memory) {
        GameStorage.Layout storage layout = GameStorage.layout();
        result.winnerCards = new address[](GameStorage.PLAYER_CARD_COUNT);
        uint256 winnerCardsIndex = 0;
        result.loserCards = new address[](GameStorage.PLAYER_CARD_COUNT);
        uint256 loserCardsIndex = 0;

        for (uint i = 0; i < room.allCards.length; i++) {
            if (room.allCards[i].card == address(0)) {
                continue;
            }

            if (i == destroyIndex) {
                result.destroyValue += shop.getPriceByAddress(room.allCards[i].card);
                continue;
            } else {
                if (room.allCards[i].originalOwner == winner) {
                    result.winnerCards[winnerCardsIndex++] = room.allCards[i].card;
                } else {
                    result.loserCards[loserCardsIndex++] = room.allCards[i].card;
                }

                ICard card = ICard(room.allCards[i].card);
                if (room.allCards[i].cardTransferType == GameTypes.CardTransferType.USER) {
                    card.transfer(winner, card.getUnit());
                } else {
                    layout.managedCardBalance[winner][address(card)] += card.getUnit();
                }
            }
        }

        return result;
    }

    function _cleanRoom(GameTypes.Room storage room) internal {
        room.state = GameTypes.States.EMPTY;
        delete room.allCards;
        delete room.handCards[room.player1];
        delete room.handCards[room.player2];
        room.player1 = address(0);
        room.player2 = address(0);
        room.turn = 0;
        room.turnStartedAt = 0;
        room.currentPlayer = address(0);

        for (uint8 r = 0; r < GameStorage.MAX_X; r++) {
            for (uint8 c = 0; c < GameStorage.MAX_Y; c++) {
                delete room.board[r][c];
            }
        }
    }

    function _savePlayerStatistic(GameTypes.Room storage room, address winner, address loser) internal {
        GameStorage.Layout storage layout = GameStorage.layout();
        layout.playerStatistic[winner].wins++;
        layout.playerStatistic[loser].losses++;

        GameTypes.PlayerRoom[] storage winnerRooms = layout.playerStatistic[winner].rooms;
        for (uint i = 0; i < winnerRooms.length; i++) {
            if (winnerRooms[i].roomId == room.roomId && winnerRooms[i].roomType == room.roomType) {
                winnerRooms[i] = winnerRooms[winnerRooms.length - 1];
                winnerRooms.pop();
                break;
            }
        }

        GameTypes.PlayerRoom[] storage loserRooms = layout.playerStatistic[loser].rooms;
        for (uint i = 0; i < loserRooms.length; i++) {
            if (loserRooms[i].roomId == room.roomId && loserRooms[i].roomType == room.roomType) {
                loserRooms[i] = loserRooms[loserRooms.length - 1];
                loserRooms.pop();
                break;
            }
        }

        if (layout.playerStatistic[winner].rooms.length > 0) {
            layout.playerStatistic[winner].rooms.pop();
        }
        if (layout.playerStatistic[loser].rooms.length > 0) {
            layout.playerStatistic[loser].rooms.pop();
        }
    }

    function _getWinnerByScore(GameTypes.Room storage room) internal view returns (address winner) {
        uint score1 = 0;
        uint score2 = 0;

        for (uint8 r = 0; r < GameStorage.MAX_X; r++) {
            for (uint8 c = 0; c < GameStorage.MAX_Y; c++) {
                GameTypes.Card memory card = _getCardOnBoard(room, r, c);
                if (!card.isPlaced) {
                    continue;
                }

                if (card.currentHolder == room.player1) {
                    score1++;
                } else if (card.currentHolder == room.player2) {
                    score2++;
                }
            }
        }

        if (score1 > score2) {
            return room.player1;
        } else if (score2 > score1) {
            return room.player2;
        } else {
            revert AbnormalState();
        }
    }

    function _otherPlayer(GameTypes.Room storage room, address player) internal view returns (address) {
        return (player == room.player1) ? room.player2 : room.player1;
    }

    function _getCardOnBoard(
        GameTypes.Room storage room,
        uint8 x,
        uint8 y
    ) internal view returns (GameTypes.Card storage card) {
        uint8 cardId = room.board[x][y];
        card = room.allCards[cardId];

        // 如果room.board[x][y]为0, 有可能是此处没有卡牌所返回的默认值
        // 所以需要过滤掉这种异常情况
        // 在cardId为0的情况下:
        //   如果卡牌未放置, 则不可能从board上拿到
        //   如果卡牌已放置, 但是位置不对, 则说明是默认值
        //   如果卡牌已放置, 且位置正确, 则是正常值
        // 在cardId不为0的情况下一定是正常值
        if (cardId == 0) {
            if (!card.isPlaced) {
                return room.allCards[GameStorage.PLAYER_CARD_COUNT * 2];
            }
            if (card.isPlaced && (card.x != x || card.y != y)) {
                return room.allCards[GameStorage.PLAYER_CARD_COUNT * 2];
            }
            return card;
        } else {
            return card;
        }
    }
}
