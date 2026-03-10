// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title IServiceFeeConfigurator
/// @notice Interface for ServiceFeeConfigurator
interface IServiceFeeConfigurator {
    event CommissionPercentageChanged(uint16 value);

    /// @notice returns commission percentage
    /// @return percentage the commission percentage
    function getCommissionPercentage() external view returns (uint16);

    /// @notice configures commission percentage
    /// @param value: the new commission percentage
    function setCommissionPercentage(uint16 value) external;
}
