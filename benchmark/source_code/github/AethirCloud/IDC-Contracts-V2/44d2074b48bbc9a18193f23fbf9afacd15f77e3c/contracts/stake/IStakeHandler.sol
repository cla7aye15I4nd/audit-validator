// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRequestVerifier} from "../base/IRequestVerifier.sol";
import {VestingRecord} from "../vesting/IVestingHandler.sol";

/// @title IStakeHandler
/// @notice Interface for the StakeHandler contract
interface IStakeHandler {
    /// @notice emitted when a standard stake is made
    event StandardStake(
        address indexed host,
        uint256 tid,
        uint256 gid,
        uint256[] cids,
        uint256[] amounts,
        uint256 totalAmount,
        uint64 nonce,
        bytes32 vhash
    );

    /// @notice emitted when a delegation stake is made
    event DelegationStake(
        address indexed delegator,
        uint256 tid,
        uint256 gid,
        uint256[] cids,
        uint256[] amounts,
        uint256 totalAmount,
        uint64 nonce,
        bytes32 vhash
    );

    /// @notice emitted when a standard unstake is made
    event Unstake(
        address indexed account,
        uint256 tid,
        uint256 gid,
        uint256[] cids,
        uint256[] amounts,
        uint256 totalAmount,
        uint64 nonce,
        bytes32 vhash
    );

    /// @notice emitted when a delegation unstake is made
    event DelegationUnstake(
        address indexed account,
        uint256 tid,
        uint256 gid,
        uint256[] cids,
        uint256[] amounts,
        uint256 totalAmount,
        uint64 nonce,
        bytes32 vhash
    );

    /// @notice emitted when a delegation unstake is made
    event ForceUnstake(
        address indexed account,
        uint256 tid,
        uint256 gid,
        uint256[] cids,
        uint256[] amounts,
        uint256 totalAmount,
        uint64 nonce,
        bytes32 vhash
    );

    /// @notice emitted when an initial stake is made
    event InitialStake(
        address indexed delegator,
        uint256 tid,
        uint256 gid,
        uint256[] cids,
        uint256[] amounts,
        uint256 totalAmount,
        uint64 nonce,
        bytes32 vhash
    );

    /// @notice Emitted when unstake vesting is initially settled
    event UnstakeInitialSettled(uint256[] tids, uint256[] gids, VestingRecord[] records, uint64 nonce, bytes32 vhash);

    /// @dev The clients should call `approve(address spender, uint256 value)` before calling
    /// @notice Standard Staking
    /// @param vdata VerifiableData
    function stake(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @dev The clients should call `approve(address spender, uint256 value)` before calling
    /// @notice Delegation Staking
    /// @param vdata VerifiableData
    function delegationStake(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice Standard Unstaking
    /// @param vdata VerifiableData
    function unstake(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice Delegation Unstaking
    /// @param vdata VerifiableData
    function delegationUnstake(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice Force Unstaking
    /// @param vdata VerifiableData
    function forceUnstake(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice deduct staked amount
    /// @param tid the tenant id
    /// @param gid the group id
    /// @param cid the container id
    /// @param stakedAmount the amount to deduct
    function deductStaked(uint256 tid, uint256 gid, uint256 cid, uint256 stakedAmount) external;

    /// @notice initial settle staking records
    /// @param vdata the verifiable data
    function initialSettleStakingRecords(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice initial settle unstake vesting records
    /// @param vdata the verifiable data
    function initialSettleVestingRecords(IRequestVerifier.VerifiableData calldata vdata) external;
}
