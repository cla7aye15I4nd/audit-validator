# Investors Receive Fewer Pool Rewards Due to Integer Division


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | high |
| Triage Verdict | ❌ Invalid |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./src/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The function `_updatePoolReward` calculates the per-investor share of pool rewards using integer division (`/ poolInfo.participantsCount`). This operation truncates any remainder, causing a small amount of the pool's accumulated rewards to be lost in every round. This lost dust accumulates over time, becoming permanently inaccessible to investors.To fix this, the contract should use a more precise method for reward distribution. A common pattern is to track rewards per share and update a user's individual reward based on their shares when they interact with the contract, avoiding premature division of the total reward pool. Alternatively, track the remainder and add it to the next round's reward pool.1. Assume a pool is active with `participantsCount` = 3.
2. The pool accumulates `curReward` = 100 tokens in a round (`endedRounds` = 1).
3. The `_updatePoolReward` function is triggered during a deposit or claim.
4. The reward to be added to `rewardPerInvestorStored` is calculated as `100 * 1 / 3`, which Solidity truncates to `33`.
5. Each of the 3 investors in the pool can eventually claim 33 tokens from this round's reward. The total reward claimed is `33 * 3 = 99`.
6. One token (`100 - 99`) is lost due to the integer division. This token remains in the contract's accounting but can never be distributed to investors, causing them to receive fewer tokens than they were collectively entitled to.

## Recommendation

To fix this, the contract should use a more precise method for reward distribution. A common pattern is to track rewards per share and update a user's individual reward based on their shares when they interact with the contract, avoiding premature division of the total reward pool. Alternatively, track the remainder and add it to the next round's reward pool.

## Vulnerable Code

```
poolInfo.rewardPerInvestorStored += poolInfo.curReward * endedRounds / poolInfo.participantsCount;
```
