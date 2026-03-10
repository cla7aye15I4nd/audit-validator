// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRequestVerifier} from "../base/IRequestVerifier.sol";
import {VestingRecord} from "../vesting/IVestingHandler.sol";

/// @title IServiceFeeHandler
/// @notice Interface for the ServiceFeeHandler contract
interface IServiceFeeHandler {
    /// @notice Emitted when service fee is deposited
    event ServiceFeeDeposited(address indexed sender, uint256 tid, uint256 amount);

    /// @notice Emitted when service fee is withdrawn
    event ServiceFeeWithdrawn(address indexed sender, uint256 tid, uint256 amount);

    /// @notice Emitted when service fee is locked
    event ServiceFeeLocked(uint256[] tids, uint256[] amounts, uint64 nonce, bytes32 vhash);

    /// @notice Emitted when service fee is unlocked
    event ServiceFeeUnlocked(uint256[] tids, uint256[] amounts, uint64 nonce, bytes32 vhash);

    /// @notice Emitted when service fee is settled
    event ServiceFeeSettled(ServiceFeeSettleParams params, uint64 nonce, bytes32 vhash);

    /// @notice Emitted when service fee is initially settled
    event ServiceFeeInitialSettled(
        uint256[] tids,
        uint256[] gids,
        VestingRecord[] records,
        uint64 nonce,
        bytes32 vhash
    );

    /// @notice Emitted when tenants service fee is initially deposited
    event ServiceFeeInitialDeposited(uint256[] tids, uint256[] amounts, uint64 nonce, bytes32 vhash);

    /// @notice Data structure for service fee settlement
    /// @param tenants Array of tenant IDs
    /// @param tenantAmounts Array of tenant amounts
    /// @param hosts Array of cloud hosts. Use to create a new vesting record.
    /// @param groups Array of host groups. Use to create a new vesting record.
    /// @param hostGroupAmounts Array of host group with amount. Use to create a new vesting record.
    /// @param grantAmount Deducts used grants from the Grant Pool
    /// @param slashAmount The slash amount. Use to Allocates daily slash penalties
    struct ServiceFeeSettleParams {
        uint256[] tenants;
        uint256[] tenantAmounts;
        uint256[] hosts;
        uint256[] groups;
        uint256[] hostGroupAmounts;
        uint256 grantAmount;
        uint256 slashAmount;
    }
    /// @dev The clients should call `approve(address spender, uint256 value)` before calling
    /// @notice deposit service fee to the contract
    /// @param tid the tenant tid
    /// @param amount the amount to deposit
    function depositServiceFee(uint256 tid, uint256 amount) external;

    /// @notice withdraw service fee from the contract
    /// @param tid the tenant tid
    /// @param amount the amount to withdraw
    function withdrawServiceFee(uint256 tid, uint256 amount) external;

    /// @notice lock service fee
    /// @param vdata the verifiable data
    function lockServiceFee(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice unlock service fee
    /// @param vdata the verifiable data
    function unlockServiceFee(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice settle service fee
    /// @param vdata the verifiable data
    function settleServiceFee(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice initial settle service fee
    /// @param vdata the verifiable data
    function initialSettleServiceFee(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice initial deposited tenants service fee
    /// @param vdata the verifiable data
    function initialTenantsServiceFee(IRequestVerifier.VerifiableData calldata vdata) external;
}
