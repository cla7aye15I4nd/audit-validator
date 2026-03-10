// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title IRestakeFeeReceiver
/// @notice Interface for IRestakeFeeReceiver
interface IRestakeFeeReceiver {
    /// @notice emitted when restake transaction fee is withdrawn
    event RestakeFeeWithdrawn(address indexed recipient, uint256 amount);

    /// @notice withdraws restart transaction fee
    /// @param recipient recipient of the restake transaction fee
    /// @param amount amount of the restake transaction fee to withdraw
    function withdrawRestakeFee(address recipient, uint256 amount) external;
}
