# Incorrect Retrospective Application of Pool Membership in Referral Reward Calculation


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | 🟢 Minor |
| Triage Verdict | ❌ Invalid |
| Source | scanner.smart_audit |
| Scan Model | grok-4 |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./src/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The logical vulnerability lies in the _updateInvestorRefReward function, which calculates referral rewards for past rounds using the investor's current membership status in pool 2 to determine eligibility for downline referral rewards. Specifically, when computing roundReward, it checks the current isInvestorInPool[investor][2] to include downlineRefsDeposit * 675 / BASIS_POINTS. This status is applied retroactively to all ended rounds since the last updateRefRewardTimestamp, even if the investor was not in pool 2 during those past rounds. As a result, an investor who joins pool 2 after a period of ineligibility can claim downline rewards for historical rounds during which they were not qualified, leading to incorrect and excessive reward allocation.

Exploit Demonstration:
1. The attacker sets up their account with at least one direct referral who has further downline referrals, ensuring downlineRefsDeposit > 0 and directRefsDeposit > 0, but ensures their totalDeposit is below the personalInvestRequired for pool 2 (3 * 10**24 based on initial criteria), so they do not qualify for pool 2.
2. The attacker waits for multiple reward rounds (e.g., several days, as roundDuration is 24 hours) without calling claimReward on their account and assuming no new deposits occur under their referral tree that would trigger _updateInvestorRefReward for their account, keeping updateRefRewardTimestamp outdated.
3. The attacker calls deposit with a sufficient amount (e.g., enough to make totalDeposit >= 3 * 10**24) and their referer (if applicable), while ensuring they meet other criteria (directRefsCount >= 5, directRefsDeposit >= 6 * 10**24), causing _checkAndAddInvestorToPool to add them to pool 2 during the _updatePoolRewards call in deposit. This updates isInvestorInPool[attacker][2] to true without updating the attacker's referral rewards.
4. The attacker calls claimReward, which invokes _updateInvestorRewards and thus _updateInvestorRefReward. This calculates a large number of endedRounds based on the outdated updateRefRewardTimestamp, includes the downline component in roundReward due to the now-true isInvestorInPool[attacker][2], and adds the excessive totalRefRewards to accumulatedReward, allowing the attacker to claim undeserved downline rewards for the historical periods before joining pool 2.

## Vulnerable Code

```
function _updateInvestorRewards(address investor) internal {
        InvestorInfo memory investorInfo = accountToInvestorInfo[investor];
        (uint256 totalDailyReward, uint256 roundReward) = _calcInvestorDailyReward(investorInfo);
        accountToInvestorInfo[investor].accumulatedReward += totalDailyReward;
        if (totalDailyReward > 0) {
            accountToInvestorInfo[investor].lastDailyReward = roundReward;
        }
        _updateInvestorRefReward(investor);
        _updatePoolRewards();
        _updateInvestorPoolRewards(investor);
    }
```

## Related Context

```
_calcInvestorDailyReward ->     function _calcInvestorDailyReward(InvestorInfo memory investorInfo) internal view returns(uint256, uint256) {
        uint32 lastUpdate = investorInfo.lastDepositTimestamp > investorInfo.lastClaimTimestamp ? investorInfo.lastDepositTimestamp : investorInfo.lastClaimTimestamp;
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(lastUpdate);
        uint256 roundReward = investorInfo.totalDeposit * 30000 / BASIS_POINTS;

        return (roundReward * endedRounds, roundReward);
    }

_updateInvestorRefReward ->     function _updateInvestorRefReward(address investor) internal {
        InvestorInfo memory investorInfo = accountToInvestorInfo[investor];
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(investorInfo.updateRefRewardTimestamp);

        if (endedRounds > 0) {
            (uint256 totalRefRewards, uint256 lastRefReward) = _calcInvestorRefRewards(investorInfo, investor);
            accountToInvestorInfo[investor].lastRefReward = lastRefReward;
            accountToInvestorInfo[investor].accumulatedReward += totalRefRewards;
        }

        accountToInvestorInfo[investor].updateRefRewardTimestamp = uint32(block.timestamp);
    }

_updatePoolRewards ->     function _updatePoolRewards(uint256 amount, address investor, address referer) internal {
        InvestorInfo memory investorInfo = accountToInvestorInfo[investor];
        InvestorInfo memory refererInfo = accountToInvestorInfo[referer];
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(uint32(lastUpdatePoolRewardTimestamp));
        for (uint8 i = 0; i < 7; i++) {
            PoolInfo storage poolInfo = pools[i];
            bool isPoolActive = poolInfo.isActive;

            if (isPoolActive) _updatePoolReward(poolInfo, endedRounds);

            bool isAddedToPool = _checkAndAddInvestorToPool(poolInfo, i, investorInfo, investor);
            if (referer != address(0)) {
                isAddedToPool = isAddedToPool || _checkAndAddInvestorToPool(poolInfo, i, refererInfo, referer);
            }

            if (!isPoolActive) {
                if (isAddedToPool) {
                    poolInfo.isActive = true;
                } else {
                    break;
                }
            }

            poolInfo.curReward += amount * poolInfo.share / BASIS_POINTS;
        }
        for (uint8 i = 7; i < 9; i++) {
            PoolInfo memory poolInfo = pools[i];
            if (poolInfo.isActive) {
                _updatePoolReward(pools[i], endedRounds);
                pools[i].curReward += amount * poolInfo.share / BASIS_POINTS;
            }
        }

        lastUpdatePoolRewardTimestamp = block.timestamp;
    }

_updateInvestorPoolRewards ->     function _updateInvestorPoolRewards(address investor) internal {
        uint256 reward;
        for (uint8 i = 0; i < pools.length; i++) {
            if (!isInvestorInPool[investor][i]) continue;

            reward += _updateInvestorPoolReward(investor, i);
        }
        accountToInvestorInfo[investor].accumulatedReward += reward;
    }
```
