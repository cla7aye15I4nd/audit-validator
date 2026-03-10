// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title IServiceFeeHandler
/// @notice Interface for the RewardCommissionReceiver.sol
interface IRewardCommissionReceiver {
    /// @notice emitted when reward commission is withdrawn
    event RewardCommissionWithdrawn(address indexed recipient, uint256 amount);

    /// @notice withdraws reward commission
    /// @param recipient recipient of the receiver
    /// @param amount amount of the reward commission to withdraw
    function withdrawRewardCommission(address recipient, uint256 amount) external;
}
