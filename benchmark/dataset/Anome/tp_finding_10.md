# Incorrect Global Weight Deduction in _unstake Enables Reward Hijack


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

- **Local path:** `./source_code/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/liquidity_manager/pool/LiquidityPoolInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/liquidity_manager/pool/LiquidityPoolInternal.sol
- **Lines:** 54–87

## Description

Vulnerability: In the _unstake function, the code reduces the pool’s global reward‐weight (l.totalRewardWeight) using
    l.totalRewardWeight -= (l.totalRewardWeight * record.amount) / l.stakedAmount[account];
Here l.totalRewardWeight is the sum of weights of all stakers, but l.stakedAmount[account] is only the caller’s stake. When there are other stakers (so l.totalRewardWeight > l.stakedAmount[account]), this formula over-deducts: it subtracts G * (R/U) rather than R, where G is the pool’s total weight, U is the attacker’s stake and R the record being withdrawn. In the extreme case R=U this wipes out the entire pool weight.

Exploit Steps:
1. Observe a live pool with existing stakers so that G = l.totalRewardWeight > 0.
2. From your attacker account, call the external stake function (which invokes _stake) with a small amount R > 0. Now your per-account stake U = R, and global G_new = G_old + R.
3. Immediately call the external withdraw function (which invokes _unstake) for your new recordIndex. Inside _unstake:
   • It computes removal = l.totalRewardWeight * R / l.stakedAmount[attacker] = G_new * R / R = G_new.
   • It then sets l.totalRewardWeight = G_new - G_new = 0.
4. The pool’s total reward weight is now zero. All other stakers’ weights have effectively been erased.
5. Call the external stake function again to deposit any positive amount R′. Now l.totalRewardWeight = R′ (you are the only staker).
6. All subsequent reward accrual (via rewardPerToken calculations) will be divided by R′, so your new stake captures 100% of the pool rewards.

Impact: An attacker can momentarily ‘reset’ the pool’s weight to zero by staking and immediately unstaking, then restake to become the sole reward recipient.

## Vulnerable Code

```
function _unstake(address account, uint256 recordIndex) internal {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();
        LiquidityManagerStorage.StakeRecord storage record = l.accountStakeRecord[account][recordIndex];

        if (record.isWithdrawn) {
            revert StakeAlreadyWithdrawn();
        }

        if (record.amount == 0) {
            revert StakeAmountIsZero();
        }

        if (record.amount > l.stakedAmount[account]) {
            revert StakeAmountIsGreaterThanStaked();
        }

        _claimReward(account);
        _claimRewardExtra(account, record);

        record.isWithdrawn = true;
        l.rewardWeight[account] -= (l.rewardWeight[account] * record.amount) / l.stakedAmount[account];
        l.totalRewardWeight -= (l.totalRewardWeight * record.amount) / l.stakedAmount[account];
        l.stakedAmount[account] -= record.amount;
        l.totalStaked -= record.amount;

        l.totalRewardWeightExtra -=
            (l.totalRewardWeightExtra * record.extraRewardWeight) /
            l.extraRewardWeight[account];
        l.extraRewardWeight[account] -= record.extraRewardWeight;

        l.tokenStaking.safeTransfer(account, record.amount);

        emit Withdrawn(account, record.amount);
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

_claimReward ->     function _claimReward(address account) internal returns (uint256 pendingReward) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();

        pendingReward = l.storedPendingReward[account];
        if (pendingReward == 0) {
            return 0;
        }
        uint256 sponsorReward = _rewardSponsor(account, pendingReward);

        l.storedPendingReward[account] = 0;
        l.totalReward += pendingReward - sponsorReward;
        l.accountTotalReward[account] += pendingReward - sponsorReward;
        l.accountClaimRecord[account].push(
            LiquidityManagerStorage.ClaimRecord({
                rewardType: 1,
                amount: pendingReward - sponsorReward,
                timestamp: block.timestamp
            })
        );

        l.tokenReward.safeTransfer(account, pendingReward - sponsorReward);

        emit RewardPaid(account, pendingReward);
    }

_claimRewardExtra -> function _claimRewardExtra(
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
