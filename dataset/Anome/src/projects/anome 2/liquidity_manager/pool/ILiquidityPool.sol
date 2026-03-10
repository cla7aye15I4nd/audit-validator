// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LiquidityManagerStorage} from "../LiquidityManagerStorage.sol";

interface ILiquidityPool {
    struct PoolInfo {
        address tokenStaking;
        address tokenReward;
        uint256 rewardEndsAt;
        uint256 rewardPerDay;
        uint256 lastRewardTime;
        uint256 totalRewardWeight;
        uint256 totalRewardWeightExtra;
        uint256 totalStaked;
        uint256 totalReward;
        uint256 totalSponsorReward;
    }

    struct AccountInfo {
        uint256 lastUpdateTime;
        uint256 referralReward;
        uint256 stakedAmount;
        uint256 rewardWeight;
        uint256 extraRewardWeight;
        uint256 accountTotalReward;
        uint256 accountTotalSponsorReward;
        uint256 pendingReward;
        uint256 pendingRewardExtra;
        uint256 currentTime;
        uint256 expectedRewardPerSecond;
    }

    function stake(uint256 amount, LiquidityManagerStorage.StakeDuration stakingDuration) external;

    function unstake(uint256 recordIndex) external;

    function claimReward() external;

    function claimSponsorReward() external;

    function getPendingReward(
        address account
    ) external view returns (uint256 pendingReward, uint256 pendingRewardExtra);

    function getStakeRecordList(
        address account
    ) external view returns (LiquidityManagerStorage.StakeRecord[] memory);

    function getClaimRecordList(
        address account
    ) external view returns (LiquidityManagerStorage.ClaimRecord[] memory);

    function getExtraRewardWeight() external view returns (uint256[] memory);

    function getPoolInfo() external view returns (PoolInfo memory poolInfo);

    function getAccountInfo(address account) external view returns (AccountInfo memory accountInfo);

    function setRewardToken(address rewardToken) external;
}
