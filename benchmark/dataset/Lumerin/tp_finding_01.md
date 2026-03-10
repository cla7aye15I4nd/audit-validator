# Reward May Be Locked Permanently


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `e87cbcc0-50e0-11ef-be7f-a520f1665dc4` |
| Commit | `3e86cce22d1af476fdc8b1d191c1b2e54254817a` |

## Location

- **Local path:** `./source_code/github/Lumerin-protocol/Morpheus-Lumerin-Node/75269bd207913526bd7b4db0892307a39c0cb9b3/smart-contracts/contracts/StakingMasterChef.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e87cbcc0-50e0-11ef-be7f-a520f1665dc4/source?file=$/github/Lumerin-protocol/Morpheus-Lumerin-Node/75269bd207913526bd7b4db0892307a39c0cb9b3/smart-contracts/contracts/StakingMasterChef.sol
- **Lines:** 105–106

## Description

When a pool is added by the owner, `rewardToken` is transferred into the contract. The owner has the capability to halt the pool before its conclusion and retrieve any `rewardToken` that has not been distributed. However, if no users stake or if there is a period without staking activity, any `rewardToken` that remains undistributed at the end of the pool will be permanently locked within the contract.

## Recommendation

It's recommended to revise the logic to ensure there would be no reward tokens locked in the contract.

## Vulnerable Code

```
rewardPerSecondScaled: (_totalReward * PRECISION) / _duration,
        locks: _lockDurations,
        accRewardPerShareScaled: 0,
        totalShares: 0
      })
    );
    emit PoolAdded(poolId, _startTime, endTime);

    rewardToken.transferFrom(_msgSender(), address(this), _totalReward);

    return poolId;
  }

  /// @notice Get the available lock durations of a pool with the corresponding multipliers
  /// @param _poolId the id of the pool
  /// @return locks locks for this pool
  function getLockDurations(uint256 _poolId) external view poolExists(_poolId) returns (Lock[] memory) {
    return pools[_poolId].locks;
  }

  /// @notice Stops the pool, no more rewards will be distributed
  /// @param _poolId the id of the pool
  function stopPool(uint256 _poolId) external onlyOwner poolExists(_poolId) {
    Pool storage pool = pools[_poolId]; // errors if poolId is invalid
    _recalculatePoolReward(pool);
    uint256 oldEndTime = pool.endTime;
    pool.endTime = block.timestamp;
    emit PoolStopped(_poolId);

    uint256 undistributedReward = ((oldEndTime - block.timestamp) * pool.rewardPerSecondScaled) / PRECISION;
    safeTransfer(_msgSender(), undistributedReward);
  }

  /// @notice Manually update pool reward variables
  /// @param _poolId the id of the pool
  function recalculatePoolReward(uint256 _poolId) external poolExists(_poolId) {
    Pool storage pool = pools[_poolId]; // errors if poolId is invalid
    _recalculatePoolReward(pool);
  }

  /// @dev Update reward variables of the given pool to be up-to-date.
  function _recalculatePoolReward(Pool storage _pool) private {
    uint256 timestamp = min(block.timestamp, _pool.endTime);
    if (timestamp <= _pool.lastRewardTime) {
      return;
    }

    if (_pool.totalShares != 0) {
      _pool.accRewardPerShareScaled = getRewardPerShareScaled(_pool, timestamp);
    }

    _pool.lastRewardTime = timestamp;
  }

  /// @dev calculate reward per share scaled without updating the pool
  function getRewardPerShareScaled(Pool storage _pool, uint256 _timestamp) private view returns (uint256) {
    uint256 rewardScaled = (_timestamp - _pool.lastRewardTime) * _pool.rewardPerSecondScaled;
    return _pool.accRewardPerShareScaled + (rewardScaled / _pool.totalShares);
  }

  /// @notice Deposit staking token
```
