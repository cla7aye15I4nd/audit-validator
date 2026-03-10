# Unstake Function Allows Multiple Unstake Operations for the Same Stake ID


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `e4cfc040-765a-11f0-849a-c7ef6369e136` |
| Commit | `6d829b3d951cfc06e0957b998356210e30884f55` |

## Location

- **Local path:** `./source_code/github/mwxlabs/smart-contract/79cbc89be144f4150e9b61cd352d6945699c61dd/contracts/staking/MWXStaking.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e4cfc040-765a-11f0-849a-c7ef6369e136/source?file=$/github/mwxlabs/smart-contract/79cbc89be144f4150e9b61cd352d6945699c61dd/contracts/staking/MWXStaking.sol
- **Lines:** 360–360

## Description

In the `MWXStaking` contract, the `_unstake` function does not validate whether a `stakeInfo` has already been deactivated (i.e., previously unstaked). As a result, the same stake can be unstaked multiple times, leading to potential double withdrawals.

For example, a malicious user could stake twice with the same amount and then call `_unstake` twice on the same `stakeId`. This would allow the user to withdraw their tokens multiple times while still retaining the ability to claim rewards from another active `stakeId`.

Relevant code snippet:

```solidity
function _unstake(uint256 stakeId, bool emergency) internal virtual updateReward updateStake(_msgSender(), stakeId) {
    StakeInfo storage stakeInfo = stakes[_msgSender()][stakeId];
    
    if (stakeInfo.stakeType == StakeType.LOCKED && !emergency) {
        if (block.timestamp < stakeInfo.unlockTime) revert StakeStillLocked();
    }

    uint256 amount = stakeInfo.amount;
    uint256 effectiveAmount = stakeInfo.effectiveAmount;

    // ... omitted for brevity

    // flag stake as inactive
    stakeInfo.active = false;
    _removeStakeId(_msgSender(), stakeId);

    stakingToken.safeTransfer(_msgSender(), amount);
}
```

The issue is that the function does not verify if `stakeInfo.active == true` before processing the unstake. This allows repeated execution against the same `stakeId`, resulting in potential fund loss for the protocol.

## Recommendation

It is suggested to add a validation check to ensure that only active stakes can be unstaked.

## Vulnerable Code

```
amount, 
            newStake.effectiveAmount, 
            newStake.stakeType == StakeType.LOCKED ? lockedOptions[lockId].duration : 0
        );

        return stakeId;
    }

    /**
     * @dev Unstake tokens
     * @param stakeId The stake ID
     */
    function unstake(uint256 stakeId) external virtual nonReentrant whenNotPaused {
        _unstake(stakeId, false);
    }

    /**
     * @dev Emergency unstake (forfeit rewards for locked stakes)
     * @param stakeId The stake ID
     */
    function emergencyUnstake(uint256 stakeId) external virtual nonReentrant whenNotPaused {
        _unstake(stakeId, true);
    }

    /**
     * @dev Internal function to unstake tokens
     * @param stakeId The stake ID
     * @param emergency Whether the unstake is an emergency unstake
     */
    function _unstake(uint256 stakeId, bool emergency) internal virtual updateReward updateStake(_msgSender(), stakeId) {
        StakeInfo storage stakeInfo = stakes[_msgSender()][stakeId];
        
        if (stakeInfo.stakeType == StakeType.LOCKED && !emergency) {
            if (block.timestamp < stakeInfo.unlockTime) revert StakeStillLocked();
        }

        uint256 amount = stakeInfo.amount;
        uint256 effectiveAmount = stakeInfo.effectiveAmount;
        uint256 forfeitedRewards = stakeInfo.pendingRewards;
        
        // Update totals
        userTotalStaked[_msgSender()] -= amount;
        userTotalEffectiveStaked[_msgSender()] -= effectiveAmount;
        totalEffectiveStake -= effectiveAmount;
        
        if (stakeInfo.stakeType == StakeType.FLEXIBLE) {
            totalFlexibleStaked -= amount;
        } else {
            totalLockedStaked -= amount;
            totalStakedPerLock[stakeInfo.lockId] -= amount;
        }

        // claim rewards first if stake type is flexible
        if (stakeInfo.stakeType == StakeType.FLEXIBLE) {
            _claimRewards(_msgSender(), stakeInfo.pendingRewards);
            forfeitedRewards = 0;
        }

        // claim rewards if stake type is locked and stake is unlocked (unlock period is over)
        if (stakeInfo.stakeType == StakeType.LOCKED && block.timestamp >= stakeInfo.unlockTime) {
```
