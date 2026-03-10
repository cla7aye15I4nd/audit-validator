// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {VestingType} from "./IVestingHandler.sol";

interface IVestingSchemeManager {
    /// @notice Emitted when a vesting scheme is set
    event VestingSchemeSet(VestingType vestingType, uint32[] percentages, uint32[] dates);

    /// @notice Set the vesting scheme for a specific vesting type
    /// @param vestingType Vesting type
    /// @param percentages Array of percentages for each vesting period
    /// @param vestingDays Array of days for each vesting period
    function setVestingScheme(
        VestingType vestingType,
        uint32[] memory percentages,
        uint32[] memory vestingDays
    ) external;

    /// @notice Get the vesting scheme for a specific vesting type
    /// @param vestingType Vesting type
    /// @return percentages Array of percentages for each vesting period
    /// @return vestingDays Array of days for each vesting period
    function getVestingScheme(
        VestingType vestingType
    ) external view returns (uint32[] memory percentages, uint32[] memory vestingDays);

    /// @notice Get the vesting amount for a specific vesting type
    /// @param vestingType Vesting type
    /// @param amount Total amount to be vested
    /// @return amounts Array of amounts for each vesting period
    /// @return vestingDays Array of days for each vesting period
    function getVestingAmount(
        VestingType vestingType,
        uint256 amount
    ) external view returns (uint256[] memory amounts, uint32[] memory vestingDays);
}
