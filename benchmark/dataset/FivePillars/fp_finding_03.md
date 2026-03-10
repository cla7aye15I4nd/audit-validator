# Conflicting Pool Reward Updates Causing Skipped Rounds


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | low |
| Triage Verdict | ❌ Invalid |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./source_code/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The claimReward function calls both _updateInvestorRewards (which itself calls _updatePoolRewards) and then calls _updatePoolRewards(amount, investor, referer) again, causing lastUpdatePoolRewardTimestamp to be updated twice in one transaction and skipping reward accrual for intermediate rounds.Remove the redundant _updatePoolRewards invocation in claimReward or ensure that lastUpdatePoolRewardTimestamp is only updated once after all reward calculations.1. Alice has pending pool rewards accrued for 2 rounds.
2. Alice calls claimReward().
3. _updateInvestorRewards triggers _updatePoolRewards, capturing 2 endedRounds and updates pools.
4. lastUpdatePoolRewardTimestamp is set.  Immediately after, claimReward calls the other _updatePoolRewards with endedRounds=0 (since timestamp just updated), so no further accrual.
5. Any rewards from the moment of the first _updatePoolRewards to the second call are dropped, effectively skipping potential reward rounds.

## Recommendation

Remove the redundant _updatePoolRewards invocation in claimReward or ensure that lastUpdatePoolRewardTimestamp is only updated once after all reward calculations.

## Vulnerable Code

```
claimReward() -> _updateInvestorRewards() -> _updatePoolRewards() -> lastUpdatePoolRewardTimestamp = block.timestamp;
... 
claimReward() -> _updatePoolRewards(toRedistribute, investorAddress, investor.referer) -> lastUpdatePoolRewardTimestamp = block.timestamp;
```
