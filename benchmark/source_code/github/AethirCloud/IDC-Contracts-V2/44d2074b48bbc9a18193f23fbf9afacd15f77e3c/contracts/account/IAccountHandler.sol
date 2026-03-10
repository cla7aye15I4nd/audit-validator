// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRequestVerifier} from "../base/IRequestVerifier.sol";

/// @title Account Handler Interface
interface IAccountHandler {
    /// @notice Emitted when a new account is created
    event AccountCreated(address indexed wallet, uint256 tid, Group initialGroup, uint64 nonce, bytes32 vhash);
    /// @notice Emitted when an account is migrated
    event AccountMigrationCompleted(
        address[] indexed wallets,
        uint256[] tids,
        Group[] initialGroups,
        uint64 nonce,
        bytes32 vhash
    );
    /// @notice Emitted when a wallet is rebound
    event WalletRebound(address indexed wallet, uint256 tid, uint64 nonce, bytes32 vhash);
    /// @notice Emitted when a new group is created
    event GroupCreated(uint256 tid, uint256 gid, uint64 nonce, bytes32 vhash);
    /// @notice Emitted when a group migration is completed
    event GroupMigrationCompleted(Group[] groups, uint64 nonce, bytes32 vhash);
    /// @notice Emitted when a delegator is assigned to a group
    event DelegatorAssigned(address indexed delegator, uint256 tid, uint256 gid, uint64 nonce, bytes32 vhash);
    /// @notice Emitted when a delegator is revoked from a group
    event DelegatorRevoked(uint256 tid, uint256 gid, uint64 nonce, bytes32 vhash);
    /// @notice Emitted when a fee receiver is set for a group
    event FeeReceiverSet(address indexed receiver, uint256 tid, uint256 gid, uint64 nonce, bytes32 vhash);
    /// @notice Emitted when a fee receiver is revoked from a group
    event FeeReceiverRevoked(uint256 tid, uint256 gid, uint64 nonce, bytes32 vhash);
    /// @notice Emitted when a reward receiver is set for a group
    event RewardReceiverSet(address indexed receiver, uint256 tid, uint256 gid, uint64 nonce, bytes32 vhash);
    /// @notice Emitted when a reward receiver is revoked from a group
    event RewardReceiverRevoked(uint256 tid, uint256 gid, uint64 nonce, bytes32 vhash);
    /// @notice Emitted when a policy is updated
    event PolicyUpdated(uint256 tid, uint256 gid, bool delegatorSetFeeReceiver, bool delegatorSetRewardReceiver);
    /// @notice Emitted when group settings are updated
    event GroupsUpdated(Group[] groups, uint64 nonce, bytes32 vhash);
    /// @notice Emitted when receivers are set
    event ReceiversSet(Receiver[] receivers, uint64 nonce, bytes32 vhash);

    struct Group {
        uint256 tid;
        uint256 gid;
        address delegator;
        address feeReceiver;
        address rewardReceiver;
        bool delegatorSetFeeReceiver;
        bool delegatorSetRewardReceiver;
    }

    struct Receiver {
        address feeReceiver;
        address rewardReceiver;
        uint256 tid;
        uint256 gid;
        bool setFeeReceiver;
        bool setRewardReceiver;
    }

    /// @notice create a new account
    /// @param vdata the verifiable data
    function createAccount(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice rebind a wallet to a new account
    /// @param vdata the verifiable data
    function rebindWallet(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice create a new group
    /// @param vdata the verifiable data
    function createGroup(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice assign a delegator to a group
    /// @param vdata the verifiable data
    function assignDelegator(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice revoke a delegator from a group
    /// @param vdata the verifiable data
    function revokeDelegator(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice set a fee receiver for a group
    /// @param vdata the verifiable data
    function setFeeReceiver(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice revoke a fee receiver from a group
    /// @param vdata the verifiable data
    function revokeFeeReceiver(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice set a reward receiver for a group
    /// @param vdata the verifiable data
    function setRewardReceiver(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice revoke a reward receiver from a group
    /// @param vdata the verifiable data
    function revokeRewardReceiver(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice update a policy
    /// @param tid the account tid
    /// @param gid the group id
    /// @param delegatorSetFeeReceiver whether delegator can set fee receiver
    /// @param delegatorSetRewardReceiver whether delegator can set reward receiver
    function updatePolicy(
        uint256 tid,
        uint256 gid,
        bool delegatorSetFeeReceiver,
        bool delegatorSetRewardReceiver
    ) external;

    /// @notice batch update group settings
    /// @param vdata the verifiable data
    function batchUpdateGroupSettings(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice batch set receivers
    /// @param vdata the verifiable data
    function batchSetReceivers(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice get the group information
    /// @param tid the account tid
    /// @param gid the group id
    function getGroup(uint256 tid, uint256 gid) external view returns (Group memory);

    /// @notice initial account migration
    /// @param vdata the verifiable data
    function initialAccountsMigration(IRequestVerifier.VerifiableData calldata vdata) external;
}
