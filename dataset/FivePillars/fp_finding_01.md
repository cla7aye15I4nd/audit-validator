# Un-reset `curReward` Leads to Compounding Pool Reward Inflation


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | 🟢 Minor |
| Triage Verdict | ❌ Invalid |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./src/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The `_updatePoolReward` function is responsible for distributing accumulated pool rewards to participants at the end of each reward round. It calculates the reward per investor for the concluded rounds using `poolInfo.curReward * endedRounds / poolInfo.participantsCount` and adds this to `poolInfo.rewardPerInvestorStored`. However, the function fails to reset `poolInfo.curReward` to zero after this distribution. The `poolInfo.curReward` state variable is an accumulator that grows with every deposit and redistribution event. Because it is not reset, the rewards accumulated in one round are carried over and redistributed again in every subsequent round, in addition to any new rewards. This creates a compounding effect, artificially inflating the pool rewards over time and allowing pool participants to claim far more rewards than they are entitled to, at the expense of the protocol's reward funds.

**Exploit Demonstration:**
An auditor can confirm this vulnerability by simulating the progression of time and deposits across multiple reward rounds.
1. **Initial State:** Ensure at least one user, Alice, is a participant in an active pool (e.g., Pool 0). Note the initial `pools[0].rewardPerInvestorStored` and `pools[0].curReward` (initially 0).
2. **Round 1:** A user makes a deposit, causing `_updatePoolRewards` to be called. This adds a value, say `R1`, to `pools[0].curReward`. The transaction is completed, and `lastUpdatePoolRewardTimestamp` is updated.
3. **Advance Time:** Advance the blockchain time by more than `roundDuration` (e.g., 25 hours) to end the current reward round.
4. **Round 2:** Another user makes a deposit. This triggers `_updatePoolReward` with `endedRounds` >= 1. `pools[0].rewardPerInvestorStored` increases by `R1 / participantsCount`, distributing the reward from the first round. However, `pools[0].curReward` is not reset and is instead increased by the new deposit's contribution, becoming `R1 + R2`.
5. **Advance Time Again:** Advance time by another `roundDuration`.
6. **Round 3:** A third user makes a deposit. This again calls `_updatePoolReward`. `pools[0].rewardPerInvestorStored` now increases by `(R1 + R2) / participantsCount`. The reward `R1` from the first round has now been distributed a second time.
7. **Conclusion:** By repeating this process, it can be demonstrated that `curReward` grows indefinitely and previously distributed rewards are re-distributed in every subsequent round. Alice can then call `claimReward` to receive these excessively inflated rewards.

## Vulnerable Code

```
function _updatePoolReward(PoolInfo storage poolInfo, uint256 endedRounds) internal {
        if (endedRounds > 0) {
            poolInfo.rewardPerInvestorStored += poolInfo.curReward * endedRounds / poolInfo.participantsCount;
            poolInfo.lastReward = poolInfo.curReward / poolInfo.participantsCount;
        }
    }
```
