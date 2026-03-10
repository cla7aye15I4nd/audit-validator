# Uninitialized destroyIndex in newbie mode causes first card to be skipped and locked


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | — |
| Triage Verdict | ✅ Valid |
| Triage Reason | Valid finding |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./src/projects/anome 2/game/settle/GameSettlerInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/game/settle/GameSettlerInternal.sol
- **Lines:** 105–143

## Description

In the _distributeCards function, the destroyIndex parameter is used to identify which card to treat as “destroyed” and skip distribution. However, when settling a _newbie_ room, destroyIndex is never initialized (it remains at its default value 0). This causes the card at index 0 in room.allCards to be falsely treated as destroyed:

• At i==0 the code executes the “destroy” branch, adding that card’s price to result.destroyValue and then continues, without ever transferring or crediting the NFT.
• No actual destruction takes place in newbie mode (shop.destroyCard is never called), so the card is left stuck in the game contract.

Exploit Demonstration (confirming the bug in a test scenario):
1. Create or join a room with roomType==NEWBIE.
2. As the first player, submit the NFT you wish to test as your first card—this ensures it occupies room.allCards[0].
3. Both players play normally; finish the match, making the first player (who owns index 0) the winner.
4. After settlement, observe:
   – result.destroyValue equals the price of the card at index 0, even though no destroy occurred.
   – The NFT originally at room.allCards[0] is not transferred back to its owner and remains in the contract.
5. All other cards are correctly transferred to the winner, but the first card is irrevocably locked.

By reproducing these steps an auditor can confirm that in newbie games the very first card is never distributed, nor destroyed, and ends up permanently trapped in the contract’s storage.

## Vulnerable Code

```
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
```

## Related Context

```
layout ->     function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

getPriceByAddress -> None

getUnit ->     function getUnit() external view returns (uint256);
```
