# Premature Weight Removal Enables Theft of Locked Extra Rewards


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

- **Local path:** `./src/projects/anome 2/liquidity_manager/pool/LiquidityPoolInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/liquidity_manager/pool/LiquidityPoolInternal.sol
- **Lines:** 114–149

## Description

_claimRewardExtra allocates an account’s total pending extra rewards across its individual stake records by multiplying the account’s storedPendingRewardExtra by record.extraRewardWeight then dividing by l.extraRewardWeight[account]. However, because total extraRewardWeight can be decreased at any time by unstaking—even unexpired records—a user can shrink the denominator to exactly the weight of a single expired record and thereby claim 100% of the pending extra rewards, including the share that belonged to other still-locked stakes.

Exploit Steps:
1. Stake two positions under the same account:
   • Record A: short duration (weight = a), expires at T1.
   • Record B: long duration (weight = b), expires at T2 > T1.
2. Advance time so that block.timestamp ≥ T1 but < T2 (A is expired, B is still locked).
3. Call withdraw(recordIndex for B):
   – In _unstake, _claimRewardExtra(account, B) returns 0 (B not expired).
   – _unstake then subtracts B’s extraRewardWeight (b) from l.extraRewardWeight[account].
   – You recover your B stake, no extra reward paid.
4. Now call withdraw(recordIndex for A):
   – In _claimRewardExtra(account, A), record.extraRewardWeight = a and l.extraRewardWeight[account] = a.
   – pendingRewardExtra = storedPendingRewardExtra * a / a = storedPendingRewardExtra.
   – You receive the entire pending extra reward balance, including the portion that should have remained locked for B until T2.

Result: by prematurely unstaking B (forfeiting only its future extra yield) you distort the denominator in _claimRewardExtra for A and steal B’s accrued extra rewards immediately. No underflows, reentrancy, or privileged role is needed—just logical manipulation of the weight ratio.

## Vulnerable Code

```
function _claimRewardExtra(
        address account,
        LiquidityManagerStorage.StakeRecord storage record
    ) internal returns (uint256 pendingRewardExtra) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();

        if (block.timestamp < record.expirationTimestamp || record.extraRewardWeight == 0) {
            return 0;
        }

        // 因为额外奖励只有在满足质押期后才能领取
        // 所以每个订单解压时, 按照此订单的权重比例领取额外奖励
        pendingRewardExtra =
            (l.storedPendingRewardExtra[account] * record.extraRewardWeight) /
            l.extraRewardWeight[account];
        if (pendingRewardExtra == 0) {
            return 0;
        }

        uint256 sponsorReward = _rewardSponsor(account, pendingRewardExtra);

        l.storedPendingRewardExtra[account] -= pendingRewardExtra;
        l.totalReward += pendingRewardExtra - sponsorReward;
        l.accountTotalReward[account] += pendingRewardExtra - sponsorReward;
        l.accountClaimRecord[account].push(
            LiquidityManagerStorage.ClaimRecord({
                rewardType: 2,
                amount: pendingRewardExtra,
                timestamp: block.timestamp
            })
        );

        l.tokenReward.safeTransfer(account, pendingRewardExtra - sponsorReward);

        emit RewardPaidExtra(account, pendingRewardExtra);
    }
```

## Related Context

```
layout -> function layout() internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly {
        l.slot := slot
    }
}

_rewardSponsor ->     function _rewardSponsor(address account, uint256 amount) internal returns (uint256 sponsorReward) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();
        IShop shop = IShop(l.config.shop());
        address sponsor = shop.getSponsor(account);
        if (sponsor == address(0)) {
            return 0;
        }

        sponsorReward = (amount * 5) / 100;
        l.referralReward[sponsor] += sponsorReward;
        l.accountTotalSponsorReward[sponsor] += sponsorReward;
        l.totalSponsorReward += sponsorReward;

        emit RewardSponsor(account, sponsor, sponsorReward);
    }
```
