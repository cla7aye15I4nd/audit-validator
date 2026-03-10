# Player Can Play Cards Outside Their Designated Hand


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | // 检查卡牌是否在玩家手中 if (room.allCards[cardIndex].originalOwner != account) { revert CardNotInHand(account); } The card should added to the room first before the game |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./src/projects/anome 2/game/rules/GameRules.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/game/rules/GameRules.sol
- **Lines:** 11–19

## Description

The `_placeCard` function validates a player's move by checking if they are the `originalOwner` of the card. However, it completely omits a crucial check to verify if the specified `cardIndex` is part of the player's current hand, which is tracked in the `room.handCards` state variable (as evidenced by the `getAllCardsInHand` view function). This oversight allows a player to play any card from their entire original set of cards at any time, even if the game's rules intend to restrict them to a smaller, rotating hand. A player can exploit this by directly calling the contract to play the most strategically advantageous card they own, rather than being limited to the cards currently in their hand, thereby gaining a significant and unfair advantage over an opponent following the intended rules.

**Exploit Demonstration:**
1. A game starts between Player A and Player B. Player A is assigned five cards, with indices 0 through 4. According to the game's intended rules, Player A's active hand for the turn consists of only three of these cards, for example, those with indices `[0, 1, 2]`, which are stored in `room.handCards[playerA]`.
2. An honest player using the official game interface would only be presented with cards 0, 1, and 2 as playable options.
3. Player A analyzes the board and determines that playing card `3`—which is not in their current hand—is the optimal move.
4. Player A bypasses the game's interface and directly calls the `placeCard` function on the contract, passing `3` as the `cardIndex`.
5. Inside the `_placeCard` function, the validation logic proceeds:
    - The `originalOwner` check (`room.allCards[3].originalOwner == playerA`) passes because Player A is the original owner of card 3.
    - The `isPlaced` check passes because card 3 has not yet been played.
    - All other checks, such as turn and position validity, also pass.
6. The transaction succeeds, and card 3 is placed on the board. Player A has successfully played a card that was not in their hand, subverting the game's core mechanics for an unfair strategic advantage.

## Vulnerable Code

```
function placeCard(
        GameTypes.RoomType roomType,
        uint16 roomId,
        uint8 x,
        uint8 y,
        uint8 cardIndex
    ) external override {
        _placeCard(msg.sender, roomType, roomId, x, y, cardIndex);
    }
```

## Related Context

```
_placeCard -> function _placeCard(
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
```
