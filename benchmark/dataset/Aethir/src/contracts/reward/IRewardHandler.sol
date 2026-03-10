// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRequestVerifier} from "../base/IRequestVerifier.sol";
import {VestingRecord} from "../vesting/IVestingHandler.sol";

/// @title IRewardHandler
/// @notice Interface for the RewardHandler contract
interface IRewardHandler {
    /// @notice emitted when reward is settled
    /// @param epochs reward epochs
    /// @param amounts reward amounts
    /// @param nonce nonce of the sender
    /// @param vhash hash of the vdata
    event EmissionScheduleSet(uint256[] epochs, uint256[] amounts, uint64 nonce, bytes32 vhash);

    /// @notice emitted when reward is settled
    /// @param tids array of host id
    /// @param gids array of group id
    /// @param amounts array of reward amounts
    /// @param nonce nonce of the sender
    /// @param vhash hash of the vdata
    event RewardSettled(uint256[] tids, uint256[] gids, uint256[] amounts, uint64 nonce, bytes32 vhash);

    /// @notice emitted when reward is initially settled
    /// @param tids array of host id
    /// @param gids group id
    /// @param record array of record
    /// @param nonce nonce of the sender
    /// @param vhash hash of the vdata
    event RewardInitialSettled(uint256[] tids, uint256[] gids, VestingRecord[] record, uint64 nonce, bytes32 vhash);

    /// @notice emitted when reward is settled
    /// @param vdata  VerifiableData struct
    function setEmissionSchedule(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice emitted when reward is settled
    /// @param vdata  VerifiableData struct
    function settleReward(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice emitted when reward is settled
    /// @param vdata  VerifiableData structs
    function initialSettleReward(IRequestVerifier.VerifiableData calldata vdata) external;
}
