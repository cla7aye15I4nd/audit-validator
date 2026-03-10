// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title IGrantPool
/// @notice Interface for GrantPool
interface IGrantPool {
    /// @notice emitted when grant fund is withdrawn
    event GrantSpent(uint256 amount);

    /// @notice emitted when grant fund is withdrawn
    event GrantWithdrawn(address indexed recipient, uint256 amount);

    /// @notice send token from pool to service fee fund holder
    /// @param amount amount of service fee commission to withdraw
    function spendGrantFund(uint256 amount) external;

    /// @notice withdraws grant fund
    /// @param recipient address of the receiver
    /// @param amount amount of the fund to withdraw
    function withdrawGrantFund(address recipient, uint256 amount) external;
}
