// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title IServiceFeeCommissionReceiver
/// @notice Interface for ServiceFeeCommissionReceiver
interface IServiceFeeCommissionReceiver {
    /// @notice emitted when service fee commission is withdrawn
    event ServiceFeeCommissionWithdrawn(address indexed recipient, uint256 amount);

    /// @notice withdraws service fee commission
    /// @param recipient recipient of the service fee commission
    /// @param amount amount of service fee commission to withdraw
    function withdrawServiceFeeCommission(address recipient, uint256 amount) external;
}
