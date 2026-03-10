// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @notice Vesting types
enum VestingType {
    Stake,
    Unstake,
    ServiceFee,
    Reward
}

/// @notice Vesting record
/// @param amounts array of amounts
/// @param vestingDays array of vesting days

struct VestingRecord {
    uint256[] amounts;
    uint32[] vestingDays;
}

interface IVestingHandler {
    /// @notice Emitted when a new vesting schedule is created
    /// @dev beneficiary is the wallet who will receive the vested tokens,
    /// beneficiary can be address(0) if the vested tokens go to the host
    event VestingCreated(
        address indexed beneficiary,
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        VestingRecord records
    );

    /// @notice Emitted when vested tokens are released
    /// @dev beneficiary is the wallet who will receive the vested tokens,
    /// beneficiary can be address(0) if the vested tokens go to the host
    event VestingReleased(
        address indexed beneficiary,
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        VestingRecord records
    );

    /// @notice Emitted when vested tokens are restaked
    event VestingRestaked(
        address indexed delegator,
        uint256 tid,
        uint256 gid,
        VestingRecord records,
        uint256 restakeFeeAmount
    );

    /// @notice Emitted when vested tokens are early claimed
    /// @dev beneficiary is the wallet who will receive the vested tokens,
    /// beneficiary can be address(0) if the vested tokens go to the host
    event EarlyClaimed(
        address indexed beneficiary,
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        VestingRecord records,
        uint256 penaltyAmount,
        uint256 penaltyPercentage,
        uint256 earlyClaimDays
    );

    /// @notice Emitted when vested tokens are slashed
    event VestingSlashed(
        address indexed host,
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        VestingRecord records
    );

    /// @notice Create a new vesting schedule
    /// @param vestingType type of vesting
    /// @param tid user tid
    /// @param gid group id
    /// @param amount amount to vest
    function createVesting(VestingType vestingType, uint256 tid, uint256 gid, uint256 amount) external;

    /// @notice Create a new vesting schedule with custom amounts and vesting days
    /// @param vestingType type of vesting
    /// @param tid user tid
    /// @param gid group id
    /// @param record vesting record
    function initialVesting(VestingType vestingType, uint256 tid, uint256 gid, VestingRecord calldata record) external;

    /// @notice Claim vested tokens
    /// @param tids user tids
    /// @param gids group ids
    /// @param fees vesting record
    /// @param rewards vesting record
    /// @param stakes vesting record
    function releaseHostVestedToken(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingRecord[] calldata fees,
        VestingRecord[] calldata rewards,
        VestingRecord[] calldata stakes
    ) external;

    /// @notice Release vested tokens to delegator
    /// @param tids user tid
    /// @param gids group id
    /// @param stakes vesting record
    function releaseDelegatorVestedToken(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingRecord[] calldata stakes
    ) external;

    /// @notice Release vested tokens to stake fund holder for restake
    /// @param tid user tid
    /// @param gid group id
    /// @param stakes vesting record
    /// @dev This function is called by StakeHandler
    function restakeVestedToken(
        uint256 tid,
        uint256 gid,
        VestingRecord calldata stakes,
        uint256 restakeFeeAmount
    ) external;

    /// @notice Release vested tokens to receiver
    /// @param tids user tid
    /// @param gids group id
    /// @param fees vesting record
    /// @param rewards vesting record
    function releaseReceiverVestedToken(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingRecord[] calldata fees,
        VestingRecord[] calldata rewards
    ) external;

    /// @notice Host early claim
    /// @param tids user tid
    /// @param gids group id
    /// @param vestingTypes vesting type
    /// @param records vesting record
    function hostEarlyClaim(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingType[] calldata vestingTypes,
        VestingRecord[] calldata records,
        uint32 earlyClaimDays
    ) external;

    /// @notice Delegate early claim
    /// @param tids user tid
    /// @param gids group id
    /// @param records vesting record
    /// @param earlyClaimDays early claim days
    function delegateEarlyClaim(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingRecord[] calldata records,
        uint32 earlyClaimDays
    ) external;

    /// @notice Receiver early claim
    /// @param tids user tid
    /// @param gids group id
    /// @param vestingTypes vesting type
    /// @param records vesting record
    /// @param earlyClaimDays early claim days
    function receiverEarlyClaim(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingType[] calldata vestingTypes,
        VestingRecord[] calldata records,
        uint32 earlyClaimDays
    ) external;

    /// @notice Settle penalty for slashing.
    /// Deducts from Vested Fee, Vested Reward, or Staking in order.
    /// Transfers ATH to SlashDeductionReceiver
    /// @param tid user tid
    /// @param gid group id
    /// @param fees vesting record for fees
    /// @param rewards vesting record for rewards
    function settleSlash(
        uint256 tid,
        uint256 gid,
        VestingRecord calldata fees,
        VestingRecord calldata rewards
    ) external;

    /// @notice Release all vested tokens for host
    /// @param tids user tid
    /// @param gids group id
    function releaseHostAllVestedToken(
        uint256[] calldata tids,
        uint256[] calldata gids,
        bool[] calldata releaseServiceFees,
        bool[] calldata releaseRewards,
        bool[] calldata releaseUnstakes
    ) external;

    /// @notice Release all vested tokens for delegator
    /// @param tids user tid
    /// @param gids group id
    function releaseDelegatorAllVestedToken(uint256[] calldata tids, uint256[] calldata gids) external;

    /// @notice Release all vested tokens
    /// @param tids user tid
    /// @param gids group id
    function releaseReceiverAllVestedToken(
        uint256[] calldata tids,
        uint256[] calldata gids,
        bool[] calldata releaseServiceFees,
        bool[] calldata releaseRewards
    ) external;
}
