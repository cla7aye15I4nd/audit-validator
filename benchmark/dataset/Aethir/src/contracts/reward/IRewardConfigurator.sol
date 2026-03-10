// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title IRewardConfigurator
/// @notice Interface for the RewardConfigurator.sol
interface IRewardConfigurator {
    /// @notice Emitted when reward commission percentage value is set
    event RewardCommissionChanged(uint16 percentage);

    /// @notice returns reward commission percentage value
    function getRewardCommissionPercentage() external view returns (uint16);

    /// @notice sets reward commission percentage value
    /// @param percentage new reward commission percentage value
    function setRewardCommissionPercentage(uint16 percentage) external;
}
