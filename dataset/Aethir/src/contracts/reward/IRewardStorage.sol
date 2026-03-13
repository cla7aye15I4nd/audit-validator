// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

interface IRewardStorage {
    /// @notice Emitted when a reward is allocated
    event RewardAllocated(uint32 today, uint256 amount);

    /// @notice Returns the emission amount for the specified epoch
    function getEmissionScheduleAt(uint256 epoch) external returns (uint256 amount);

    /// @notice Sets the emission schedule for the specified epochs
    /// @param epochs The epochs to set the emission schedule for
    /// @param amounts The amounts to set for the specified epochs
    function setEmissionSchedule(uint256[] calldata epochs, uint256[] calldata amounts) external;

    /// @notice Returns the allocated amount for the specified epoch
    function getAllocatedAmount(uint256 epoch) external returns (uint256);

    /// @notice Allocates the specified reward amount
    /// @param amount The amount to allocate
    function allocateReward(uint256 amount) external;
}
