# Referral Rewards Accumulable and Claimable Without Personal Investment


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟢 Minor |
| Triage Verdict | ✅ Valid |
| Source | scanner.smart_audit |
| Scan Model | grok-4 |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./src/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The _updateReferers function allows updating referral statistics (directRefsDeposit, directRefsCount) and accumulating referral rewards (via _updateInvestorRefReward) for an address that has not made any personal deposit. This occurs because there is no check ensuring the referer is an existing investor with positive totalDeposit before performing updates. As a result, referral rewards are calculated and added to accumulatedReward for non-investors based on deposits from accounts referring to them. These accumulated rewards can then be claimed without the recipient ever making a personal investment, bypassing the intended requirement of personal participation in the investment program.

Exploit Demonstration:
1. The attacker selects their address M as the intended reward recipient. M does not make any deposit.
2. The attacker controls another address Bot1 and calls deposit(amount1, M), where amount1 >= 10^18. This invokes _updateReferers(M, toInvestor1, true), which calls _updateInvestorRefReward(M), potentially adding rewards to M's accumulatedReward, and increases M's directRefsDeposit by toInvestor1 and directRefsCount by 1.
3. The attacker waits for at least one reward round (24 hours) to pass, allowing endedRounds > 0 for future updates.
4. The attacker uses another address Bot2 to call deposit(amount2, M), where amount2 >= 10^18. This again invokes _updateReferers(M, toInvestor2, true), calling _updateInvestorRefReward(M) which now calculates rewards using the updated directRefsDeposit from step 2, multiplies by endedRounds >=1, adds to M's accumulatedReward, then increases directRefsDeposit by toInvestor2 and directRefsCount by 1.
5. Optionally, repeat steps 3-4 with additional bot addresses to further accumulate rewards in M's accumulatedReward.
6. Once M's accumulatedReward >= 10^18, the attacker calls claimReward() from M. This invokes _updateInvestorRewards(M), adding any final rewards, then mints the net claim amount to M without M having made a personal deposit beforehand.

## Vulnerable Code

```
function _updateReferers(address referer, uint256 amount, bool isFirstDeposit) internal {
        _updateInvestorRefReward(referer);

        accountToInvestorInfo[referer].directRefsDeposit += amount;
        if (isFirstDeposit) accountToInvestorInfo[referer].directRefsCount += 1;

        for (uint i = 0; i < 9; i++) {
            referer = accountToInvestorInfo[referer].referer;
            if (referer == address(0)) break;
            _updateDownlineReferer(referer, amount, isFirstDeposit);
        }
    }
```

## Related Context

```
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

_updateDownlineReferer ->     function _updateDownlineReferer(address referer, uint256 amount, bool isFirstDeposit) internal {
        _updateInvestorRefReward(referer);

        accountToInvestorInfo[referer].downlineRefsDeposit += amount;
        if (isFirstDeposit) accountToInvestorInfo[referer].downlineRefsCount += 1;
    }
```
