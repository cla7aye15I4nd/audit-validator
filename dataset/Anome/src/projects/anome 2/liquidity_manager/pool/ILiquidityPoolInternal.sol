// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILiquidityPoolInternal {
    error StakeAmountIsZero();
    error StakeAmountIsGreaterThanStaked();
    error StakeAlreadyWithdrawn();
    error PoolNotStarted();

    event RewardAmountUpdated(uint256 newRewardPerDay);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event RewardPaidExtra(address indexed user, uint256 amount);
    event RewardSponsor(address indexed user, address indexed sponsor, uint256 amount);
    event RewardPaidSponsor(address indexed user, uint256 amount);
}
