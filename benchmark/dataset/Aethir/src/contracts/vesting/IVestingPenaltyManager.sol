// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {VestingType} from "./IVestingHandler.sol";

/// @title Vesting Penalty Manager Interface
interface IVestingPenaltyManager {
    /// @notice Emitted when vesting penalty is set
    event VestingPenaltySet(VestingType vestingType, uint32[] percentages, uint32[] dates);

    /// @notice Set vesting penalty for a vesting type
    /// @param vestingType the vesting type
    /// @param percentages the percentages array
    /// @param dates the dates array
    function setVestingPenalties(VestingType vestingType, uint32[] memory percentages, uint32[] memory dates) external;

    /// @notice Get vesting penalties for a vesting type
    /// @param vestingType the vesting type
    /// @return percentages the percentages array
    /// @return dates the dates array
    function getVestingPenalties(VestingType vestingType) external view returns (uint32[] memory, uint32[] memory);

    /// @notice Get vesting penalty for a vesting type and days to claim
    /// @param vestingType the vesting type
    /// @param daysToClaim the days to claim
    /// @return percentage the penalty percentage
    function getVestingPenalty(VestingType vestingType, uint32 daysToClaim) external view returns (uint256 percentage);
}
