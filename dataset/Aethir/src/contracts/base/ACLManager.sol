// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IACLManager} from "./IACLManager.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

contract ACLManager is AccessControlEnumerable, IACLManager {
    bytes32 public constant CONFIGURATION_ADMIN_ROLE = keccak256("CONFIGURATION_ADMIN");
    bytes32 public constant MIGRATOR_ROLE = keccak256("MIGRATOR");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR");
    bytes32 public constant FUND_WITHDRAW_ADMIN_ROLE = keccak256("FUND_WITHDRAW_ADMIN");
    bytes32 public constant INIT_SETTLEMENT_OPERATOR_ROLE = keccak256("INIT_SETTLEMENT_OPERATOR");
    uint8 private _validatorThreshold = 2;
    uint8 private _initiatorThreshold = 2;

    constructor(address governor) {
        require(governor != address(0), "Governor cannot be zero");
        _grantRole(DEFAULT_ADMIN_ROLE, governor);
    }

    function addConfigurationAdmin(address account) external {
        grantRole(CONFIGURATION_ADMIN_ROLE, account);
    }

    function removeConfigurationAdmin(address account) external {
        revokeRole(CONFIGURATION_ADMIN_ROLE, account);
    }

    function addMigrator(address account) external {
        grantRole(MIGRATOR_ROLE, account);
    }

    function removeMigrator(address account) external {
        revokeRole(MIGRATOR_ROLE, account);
    }

    function addValidator(address account) external {
        grantRole(VALIDATOR_ROLE, account);
    }

    function removeValidator(address account) external {
        revokeRole(VALIDATOR_ROLE, account);
    }

    function addFundWithdrawAdmin(address account) external {
        grantRole(FUND_WITHDRAW_ADMIN_ROLE, account);
    }

    function removeFundWithdrawAdmin(address account) external {
        revokeRole(FUND_WITHDRAW_ADMIN_ROLE, account);
    }

    function addInitSettlementOperator(address account) external {
        grantRole(INIT_SETTLEMENT_OPERATOR_ROLE, account);
    }

    function removeInitSettlementOperator(address account) external {
        revokeRole(INIT_SETTLEMENT_OPERATOR_ROLE, account);
    }

    /// @inheritdoc IACLManager
    function requireDefaultAdmin(address account) public view override {
        require(hasRole(DEFAULT_ADMIN_ROLE, account), "Default admin only");
    }

    /// @inheritdoc IACLManager
    function requireConfigurationAdmin(address account) public view override {
        require(hasRole(CONFIGURATION_ADMIN_ROLE, account), "Configuration admin only");
    }

    /// @inheritdoc IACLManager
    function requireMigrator(address account) public view override {
        require(hasRole(MIGRATOR_ROLE, account), "Migrator only");
    }

    /// @inheritdoc IACLManager
    function requireValidator(address account) public view override {
        require(hasRole(VALIDATOR_ROLE, account), "Validator only");
    }

    /// @inheritdoc IACLManager
    function requireFundWithdrawAdmin(address account) public view override {
        require(hasRole(FUND_WITHDRAW_ADMIN_ROLE, account), "Fund withdraw admin only");
    }

    /// @inheritdoc IACLManager
    function requireInitSettlementOperator(address account) public view override {
        require(hasRole(INIT_SETTLEMENT_OPERATOR_ROLE, account), "Init settlement operator only");
    }

    /// @inheritdoc IACLManager
    function getRequiredSignatures() public view override returns (uint8) {
        return _validatorThreshold;
    }

    /// @inheritdoc IACLManager
    function setRequiredSignatures(uint8 value) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        _validatorThreshold = value;
        emit RequiredSignaturesChanged(value);
    }

    /// @inheritdoc IACLManager
    function getRequiredInitiatorSignatures() public view override returns (uint8) {
        return _initiatorThreshold;
    }

    /// @inheritdoc IACLManager
    function setRequiredInitiatorSignatures(uint8 value) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        _initiatorThreshold = value;
        emit RequiredInitiatorSignaturesChanged(value);
    }
}
