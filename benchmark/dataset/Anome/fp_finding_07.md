# Off-by-One Turn Check Allows Extra Card Placement After Game End


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | When room.turn == MAX_TURN, the game is over |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./src/projects/anome 2/game/rules/GameRules.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/game/rules/GameRules.sol
- **Lines:** 11–19

## Description

Vulnerability:
The function checks for game over using `if (room.turn > GameStorage.MAX_TURN) revert;`, but treats `room.turn == MAX_TURN` as a valid turn. After the 8th (final) turn, the code enters the settlement branch without incrementing `room.turn` or updating `room.state`. Because `room.turn` remains equal to `MAX_TURN`, a player can call `placeCard` again and bypass the intended game-over logic.

Exploit Demonstration:
1. Two players (P1 and P2) start a game; turns alternate, and `room.turn` increments from 1 up to `MAX_TURN` (8).
2. On turn 8 (the last allowed turn), the current player (e.g., P2) places their 4th card. The code enters the settlement branch (`room.turn >= MAX_TURN`), emits `GameEnded`, and deletes `battleId`. However, `room.turn` remains 8 and `room.currentPlayer` remains P2.
3. Immediately after settlement, P2 still satisfies:
   • `room.state == GAMING`
   • `room.turn (8) <= MAX_TURN (8)`
   • `room.currentPlayer == msg.sender`
   • The only remaining board position `(x,y)` is unoccupied
   • P2 has one unplaced card in `room.allCards` with `originalOwner == P2` and `isPlaced == false`
4. P2 calls `placeCard(roomType, roomId, x, y, cardIndex)` with that last card. All checks pass, so the extra placement succeeds, flips adjacent cards via `_tryFlip`, and re-triggers settlement.
5. The second settlement uses an effectively zero `battleId`, but awards win/loss based on the updated board (P2 now has 5 cards vs. P1’s 4), allowing P2 to reverse or bolster the outcome.

Impact:
By exploiting this off-by-one turn check and missing state update, the last-mover can place an additional card beyond the intended final turn, manipulating flips and final scores to their advantage.

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
