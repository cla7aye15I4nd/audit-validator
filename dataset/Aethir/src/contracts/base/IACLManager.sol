// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/**
 * @title IACLManager
 * @notice Defines the basic interface for the ACL Manager
 */
interface IACLManager {
    /// @notice Emitted when required signatures is changed
    event RequiredSignaturesChanged(uint8 number);

    /// @notice Emitted when required initiator signatures is changed
    event RequiredInitiatorSignaturesChanged(uint8 number);

    /// @notice revert if the address is not Default Admin
    /// @param account: the address to check
    function requireDefaultAdmin(address account) external view;

    /// @notice revert if the address is not Configuration Admin
    /// @param account: the address to check
    function requireConfigurationAdmin(address account) external view;

    /// @notice revert if the address is not Settlement Operator
    /// @param account: the address to check
    function requireInitSettlementOperator(address account) external view;

    /// @notice revert if the address is not Migrator
    /// @param account: the address to check
    function requireMigrator(address account) external view;

    /// @notice revert if the address is not Validator
    /// @param account: the address to check
    function requireValidator(address account) external view;

    /// @notice revert if the address is not Fund Withdraw Admin
    /// @param account: the address to check
    function requireFundWithdrawAdmin(address account) external view;

    /// @notice get number of required validator signatures for verifiable data
    function getRequiredSignatures() external view returns (uint8);

    /// @notice set number of required validator signatures for verifiable data
    function setRequiredSignatures(uint8 value) external;

    /// @notice get number of required initiator signatures for verifiable data
    function getRequiredInitiatorSignatures() external view returns (uint8);

    /// @notice set number of required initiator signatures for verifiable data
    function setRequiredInitiatorSignatures(uint8 value) external;
}
