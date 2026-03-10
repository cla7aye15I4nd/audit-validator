// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title IStakeConfigurator
/// @notice Interface for StakeConfigurator
interface IStakeConfigurator {
    /// @notice emitted when the restaking transaction fee percentage is changed
    event RestakingTransactionFeePercentageChanged(uint16 value);

    /// @notice A {$restaking_transaction_fee_percentage} fee applies to restaked vesting tokens
    /// @return the fee percentage
    function getRestakingTransactionFeePercentage() external view returns (uint16);

    /// @notice sets the restaking transaction fee percentage
    /// @param value the new fee percentage
    function setRestakingTransactionFeePercentage(uint16 value) external;
}
