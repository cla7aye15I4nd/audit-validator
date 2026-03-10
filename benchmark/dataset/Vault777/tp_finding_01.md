# Incorrect Card Removal Logic in Deck Processing


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `5a815670-b8c1-11f0-8573-4b86029e92fb` |
| Commit | `2d3e7fff1ad0050489bf0a767a4693f25d5c8f79` |

## Location

- **Local path:** `./source_code/github/VAULT777Team/casino-contracts/2d3e7fff1ad0050489bf0a767a4693f25d5c8f79/contracts/VideoPoker.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/5a815670-b8c1-11f0-8573-4b86029e92fb/source?file=$/github/VAULT777Team/casino-contracts/2d3e7fff1ad0050489bf0a767a4693f25d5c8f79/contracts/VideoPoker.sol
- **Lines:** 270–283

## Description

The card removal logic in `fulfillRandomWords()` contains a critical flaw where cards moved from the end of the deck to replace removed cards are not properly processed, potentially causing skipped cards and incorrect deck state.

```solidity
for (uint256 g = 0; g < 5; g++) {
    for (uint256 j = 0; j < 52; j++) {
        if (game.cardsInHand[g].number == deck[j].number && game.cardsInHand[g].suit == deck[j].suit) {
            deck[j] = deck[deck.length - 1];
            assembly {
                mstore(deck, sub(mload(deck), 1))
            }
            break;
        }
    }
}
```

**Issues:**
1. **Skipped Card Processing**: When a card is moved from position `deck.length - 1` to position `j`, the loop continues from `j+1` without checking the moved card
2. **Fixed Loop Bound**: The inner loop iterates up to 52, but the deck length decreases with each removal, potentially causing out-of-bounds access
3. **Inconsistent Array State**: The deck array length is modified during iteration, creating an inconsistent state between iterations

**Example Scenario:**
- Deck has cards [A, B, C, D, E] (length 5)
- Card B is found and replaced with card E
- Array becomes [A, E, C, D] (length 4)
- The moved card E is never checked for the current player hand card

## Recommendation

Fix the card removal logic.

## Vulnerable Code

```
}
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }
        emit VideoPoker_Refund_Event(msgSender, wager, tokenAddress);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        address player = videoPokerIDs[requestId];
        if (player == address(0)) revert();
        delete (videoPokerIDs[requestId]);
        VideoPokerGame storage game = videoPokerGames[player];

        if (game.isFirstRequest) {
            Card[] memory deck = initialDeck;

            for (uint8 i = 0; i < 5; i++) {
                _pickCard(i, randomWords[i], player, deck);
            }

            game.requestID = 0;
            game.isFirstRequest = false;
            emit VideoPoker_Start_Event(player, game.cardsInHand);
        } else {
            Card[] memory deck = initialDeck;

            for (uint256 g = 0; g < 5; g++) {
                for (uint256 j = 0; j < 52; j++) {
                    if (
                        game.cardsInHand[g].number == deck[j].number &&
                        game.cardsInHand[g].suit == deck[j].suit
                    ) {
                        deck[j] = deck[deck.length - 1];
                        assembly {
                            mstore(deck, sub(mload(deck), 1))
                        }
                        break;
                    }
                }
            }

            for (uint8 i = 0; i < 5; i++) {
                if (game.toReplace[i]) {
                    _pickCard(i, randomWords[i], player, deck);
                }
            }

            uint256 wager = game.wager;
            address tokenAddress = game.tokenAddress;
            (uint256 multiplier, uint256 outcome) = _determineHandPayout(
                game.cardsInHand
            );
            emit VideoPoker_Outcome_Event(
                player,
                wager,
                wager * multiplier,
                tokenAddress,
                game.cardsInHand,
                outcome
            );
            _transferToBankroll(tokenAddress, game.wager);
            delete (videoPokerGames[player]);
            _transferPayout(player, wager * multiplier, tokenAddress);
        }
    }

    function _pickCard(
        uint8 handPosition,
        uint256 rng,
        address player,
```
