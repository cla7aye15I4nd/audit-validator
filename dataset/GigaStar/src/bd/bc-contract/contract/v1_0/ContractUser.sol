// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './CallTracker.sol';
import './IContractUser.sol';
import './IVault.sol';
import './IVersion.sol';
import './LibraryAC.sol';
import './LibraryCU.sol';
import './Types.sol';

// slither-disable-start unimplemented-functions (Abstract contracts do not need to worry about this)
// slither-disable-start dead-code (Entities are optimized away where unused though all used somewhere)

/// @dev Contract address management
/// @custom:api private
/// @custom:deploy none
abstract contract ContractUser is IContractUser, CallTracker {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────

    // ────────────────────────────────────────────────────────────────────────────
    // Fields (See MEM_LAYOUT), default visibility is 'internal'
    // ────────────────────────────────────────────────────────────────────────────
    address[] _contracts;       // Contract addresses described by `Contract` enum, < SIZE than more fields/funcs
    uint40 _nextUpgradeSeqNum;  // Value to use in the next upgrade
    UUID _nextUpgradedReqId;    // Value to use in the next upgrade

    // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
    uint[10] __gapContractUser; // Always last field, for upgradeability, reduce size by slots used for new fields

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Access control
    // ───────────────────────────────────────

    /// @dev Access control: Vault
    function _requireOnlyVault(address caller) internal view {
        if (caller == _contracts[CU.Vault]) return;
        revert AC.AccessDenied(caller);
    }

    /// @dev Access control: Xfer manager
    function _requireOnlyXferMgr(address caller) internal view {
        if (caller == _contracts[CU.XferMgr]) return;
        revert AC.AccessDenied(caller);
    }

    /// @dev Access control: Revenue manager
    function _requireOnlyRevMgr(address caller) internal view {
        if (caller == _contracts[CU.RevMgr]) return;
        revert AC.AccessDenied(caller);
    }

    /// @dev Access control: Agent
    function _requireOnlyAgent(address caller) internal virtual {
        address vault = _contracts[CU.Vault];
        if (vault != AddrZero && AC.Role.Agent == _getRole(vault, caller)) return;
        revert AC.AccessDenied(caller);
    }

    /// @dev Access control: Creator
    function _requireOnlyCreator(address caller) internal view {
        if (caller == _contracts[CU.Creator]) return;
        revert AC.AccessDenied(caller);
    }

    /// @dev Access control: Allow Agent, Admin, or Creator
    function _requireAgentOrCreator(address caller) internal {
        address vault = _contracts[CU.Vault];
        if (vault != AddrZero) {
            AC.Role role = _getRole(vault, caller);
            if (AC.Role.Agent == role) return;
            if (AC.Role.Admin == role) return;
        }
        if (caller == _contracts[CU.Creator]) return; // Last as only during deploy
        revert AC.AccessDenied(caller);
    }

    /// @dev Access control: Allow Vault, Admin, or Creator
    function _requireVaultOrAdminOrCreator(address caller) internal {
        address vault = _contracts[CU.Vault];
        if (caller == vault) return;
        if (vault != AddrZero && _getRole(vault, caller) == AC.Role.Admin) return;
        if (caller == _contracts[CU.Creator]) return; // Last as only during deploy
        revert AC.AccessDenied(caller);
    }

    /// @dev Get a role via the Vault's role based governance
    /// - Not 'view' access to allow an override without
    function _getRole(address vault, address account) internal virtual returns(AC.Role role) {
        return IVault(vault).getRole(account);
    }

    /// @dev Get a role via the Vault's role based governance
    /// - Same as `_getRole` with 'view' access
    function _getRoleView(address vault, address account) internal view returns(AC.Role role) {
        return IVault(vault).getRole(account);
    }

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────

    /// @dev Allows initialization by a creator before access control would otherwise allow
    /// @param creator Account that created this contract
    /// @param reqId Request ID, unique amongst requests across all callers
    function __ContractUser_init(address creator, UUID reqId) internal {
        __CallTracker_init(creator, reqId);
        _contracts = new address[](CU.Count);
        _contracts[CU.Creator] = creator;
        emit ContractUpdated(CU.Creator, AddrZero, creator);
    }

    /// @dev Stage values to use in the next call to `__authorizeUpgrade`
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param reqIdStage Param to stage
    function preUpgrade(uint40 seqNumEx, UUID reqId, UUID reqIdStage) external override {
        address caller = msg.sender;
        _requireVaultOrAdminOrCreator(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        if (isEmpty(reqId)) revert EmptyReqId();

        _nextUpgradeSeqNum = seqNumEx + 1;
        _nextUpgradedReqId = reqIdStage;

        _setCallRes(caller, seqNumEx, reqId, true); // For off-chain sequencing
    }

    event ContractUpgraded(address newImpl);

    function _authorizeUpgradeImpl(address caller, address newImpl) internal {
        _requireVaultOrAdminOrCreator(caller); // Access control

        checkZeroAddr(newImpl);
        emit ContractUpgraded(newImpl);

        // Validate `preUpgrade` was called
        if (isEmpty(_nextUpgradedReqId)) revert EmptyReqId();

        // Use staged params
        _setCallRes(caller, _nextUpgradeSeqNum, _nextUpgradedReqId, true); // For off-chain sequencing

        // Consume staged params
        _nextUpgradedReqId = UuidZero;
        _nextUpgradeSeqNum = 0;
    }

    /// @notice Set a contract's address
    /// @dev Less size than separate setters
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param contractId Identifies the contract being set
    /// @param newProxy The new proxy address
    /// @custom:api public
    function setContract(uint40 seqNumEx, UUID reqId, uint8 contractId, address newProxy) external override {
        address caller = msg.sender;
        _requireVaultOrAdminOrCreator(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        bool ok = _setContract(contractId, newProxy);

        _setCallRes(caller, seqNumEx, reqId, ok);
    }

    /// @dev Set a contract's address from a base contract
    function _setContract(uint8 contractId, address newProxy) internal returns(bool ok) {
        // Only the `Creator` contract may be set to zero address after deploy
        // `getVersion` is arbitrary to validate interface
        if (contractId < CU.Count &&
            (contractId == CU.Creator || (newProxy != AddrZero && IVersion(newProxy).getVersion() != 0)))
        {
            address oldProxy = _contracts[contractId];
            if (oldProxy != newProxy) {
                _contracts[contractId] = newProxy;
                emit ContractUpdated(contractId, oldProxy, newProxy);
                ok = true;
            }
        }
    }

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────

    /// @dev Get a contract address
    /// @param contractId Contract ID requested
    /// @return Requested contract address
    function getContract(uint8 contractId) external view override returns(address) {
        return _contracts[contractId];
    }
}

// slither-disable-end dead-code
// slither-disable-end unimplemented-functions
