// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {VestingType, VestingRecord} from "./IVestingHandler.sol";

/// @title IVestingStorage
interface IVestingStorage {
    /// @notice increase vesting amount for an account and return the total amount
    /// @param vestingType vesting type
    /// @param account account to increase vesting amount
    /// @param record vesting record to increase
    /// @return totalAmount total amount increase
    function increaseVestingAmounts(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account,
        VestingRecord calldata record
    ) external returns (uint256 totalAmount);

    /// @notice decrease vesting amount for an account and return the total amount
    /// @param vestingType vesting type
    /// @param account account to decrease vesting amount
    /// @param record vesting record to decrease
    /// @return totalAmount total amount decreased
    function decreaseVestingAmounts(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account,
        VestingRecord calldata record
    ) external returns (uint256 totalAmount);

    /// @notice get the vesting amount for an account
    /// @param vestingType vesting type
    /// @param account account to get vesting amount
    /// @param vestingDays array of vesting days
    /// @return amounts amount of vesting for each vesting day
    function getVestingAmounts(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account,
        uint32[] calldata vestingDays
    ) external returns (uint256[] memory amounts);

    /// @notice Retrieves the range of vesting days for a given account.
    /// @param vestingType The type of vesting.
    /// @param account account to get vesting amount
    function getRange(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account
    ) external returns (uint32 firstDay, uint32 lastDays);

    /// @notice get the vesting amount for accounts
    /// @param vestingTypes vesting type
    /// @param accounts account to get vesting amount
    /// @param vestingDays array of vesting days
    /// @return amounts amount of vesting for each vesting day
    function batchGetVestingAmounts(
        VestingType[] calldata vestingTypes,
        uint256[] calldata tids,
        uint256[] calldata gids,
        address[] calldata accounts,
        uint32[][] calldata vestingDays
    ) external view returns (uint256[][] memory amounts);

    /// @notice Retrieves the range of vesting days for given accounts.
    /// @param vestingTypes The type of vesting.
    /// @param accounts accounts to get vesting amount
    function batchGetRange(
        VestingType[] calldata vestingTypes,
        uint256[] calldata tids,
        uint256[] calldata gids,
        address[] calldata accounts
    ) external returns (uint32[] memory firstDays, uint32[] memory lastDays);

    /// @notice get all vested records for an account
    /// @param vestingType vesting type
    /// @param tid tid
    /// @param gid gid
    /// @param account account to get vesting records
    /// @param today today
    /// @return record vesting record
    function getVestedRecord(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account,
        uint32 today
    ) external returns (VestingRecord memory record);

    /// @notice get all vesting records for an account
    /// @param vestingType vesting type
    /// @param tid tid
    /// @param gid gid
    /// @param account account to get vesting records
    /// @return record vesting record
    function getVestingRecord(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account,
        uint32 today
    ) external returns (VestingRecord memory record);
}
