// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './ContractUser.sol';
import './IBalanceMgr.sol';
import './IBox.sol';
import './IBoxMgr.sol';
import './IContractUser.sol';
import './IInstRevMgr.sol';
import './IRevMgr.sol';
import './IEarnDateMgr.sol';
import './IVault.sol';
import './IXferMgr.sol';
import './Types.sol';

/// @title Vault Deployer: Deploys a Vault contract and related contracts
/// @author Jason Aubrey, GigaStar
/// @dev Allow on-chain automations that would be excessive off-chain
/// @custom:api public
/// @custom:deploy basic
// prettier-ignore
contract DeployerVault is ContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint constant VERSION = 10;         // 123 => Major: 12, Minor: 3 (always 1 digit), Used outside this contract
    uint constant EXPECT_VERSION = 10;  // 123 => Major: 12, Minor: 3 (always 1 digit)
    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UUID.wrap(0);

    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    event CreatorDetached(address addr);

    error OwnerRequired(address caller);
    error BadAddress(address expect, address actual, string what);
    error BadUint(uint expect, uint actual, string what);
    error SetAddrFailed(); // Unlikely this happens, add args if it does

    // ────────────────────────────────────────────────────────────────────────────
    // Fields
    // ────────────────────────────────────────────────────────────────────────────

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Access control
    // ───────────────────────────────────────
    function _requireOwner(address caller) private view {
        if (caller == _contracts[CU.Creator]) return;
        revert OwnerRequired(caller);
    }

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────

    /// @dev Construct an instance
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @custom:api protected
    constructor(UUID reqId) {
        __ContractUser_init(msg.sender, reqId);
    }

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────

    /// @dev Get the current version
    function getVersion() external pure returns(uint) { return VERSION; }

    function getOwner() external view returns(address) { return _contracts[CU.Creator]; }

    /// @dev Set each contract's references to all other contracts, effectively a reference mesh
    /// - Requires caller to have the owner/creator role for all contracts
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    function setRefMesh(uint40 seqNumEx, UUID reqId,
        address balanceMgr, address boxMgr, address crt, address earnDateMgr,
        address instRevMgr, address revMgr, address vault, address xferMgr
    ) external {
        address caller = msg.sender;
        _requireOwner(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        // Set a ref to each contract
        _setContract(CU.BalanceMgr, balanceMgr);
        _setContract(CU.BoxMgr, boxMgr);
        _setContract(CU.Crt, crt);
        _setContract(CU.EarnDateMgr, earnDateMgr);
        _setContract(CU.InstRevMgr, instRevMgr);
        _setContract(CU.RevMgr, revMgr);
        _setContract(CU.Vault, vault);
        _setContract(CU.XferMgr, xferMgr);

        // For each contract, set refs to other contracts
        _regContracts(balanceMgr);
        _regContracts(boxMgr);
        _regContracts(crt);
        _regContracts(earnDateMgr);
        _regContracts(instRevMgr);
        _regContracts(revMgr);
        _regContracts(vault);
        _regContracts(xferMgr);

        _setCallRes(caller, seqNumEx, reqId, true);
    }

    /// @dev Register all contracts with the `user` contract
    function _regContracts(address userAddr) internal {
        checkZeroAddr(userAddr); // Validate arg
        IContractUser user = IContractUser(userAddr);
        _verifyUint(EXPECT_VERSION, user.getVersion(), 'IContractUser.getVersion');

        user.setContract(NoSeqNum, NoReqId, CU.BalanceMgr,  _contracts[CU.BalanceMgr]);
        user.setContract(NoSeqNum, NoReqId, CU.BoxMgr,      _contracts[CU.BoxMgr]);
        user.setContract(NoSeqNum, NoReqId, CU.Crt,         _contracts[CU.Crt]);
        user.setContract(NoSeqNum, NoReqId, CU.EarnDateMgr, _contracts[CU.EarnDateMgr]);
        user.setContract(NoSeqNum, NoReqId, CU.InstRevMgr,  _contracts[CU.InstRevMgr]);
        user.setContract(NoSeqNum, NoReqId, CU.RevMgr,      _contracts[CU.RevMgr]);
        user.setContract(NoSeqNum, NoReqId, CU.Vault,       _contracts[CU.Vault]);
        user.setContract(NoSeqNum, NoReqId, CU.XferMgr,     _contracts[CU.XferMgr]);

        _verifyAddress(_contracts[CU.BalanceMgr],    user.getContract(CU.BalanceMgr),    'getBalanceMgr');
        _verifyAddress(_contracts[CU.BoxMgr],        user.getContract(CU.BoxMgr),        'getBoxMgr');
        _verifyAddress(_contracts[CU.Crt],           user.getContract(CU.Crt),           'getCrt');
        _verifyAddress(_contracts[CU.EarnDateMgr],   user.getContract(CU.EarnDateMgr),   'getEarnDateMgr');
        _verifyAddress(_contracts[CU.InstRevMgr],    user.getContract(CU.InstRevMgr),    'getInstRevMgr');
        _verifyAddress(_contracts[CU.RevMgr],        user.getContract(CU.RevMgr),        'getRevMgr');
        _verifyAddress(_contracts[CU.Vault],         user.getContract(CU.Vault),         'getVault');
        _verifyAddress(_contracts[CU.XferMgr],       user.getContract(CU.XferMgr),       'getXferMgr');
    }

    /// @dev Detach the creator from each instance to finalize the setup
    /// - Requires caller to have the owner/creator role for all contracts
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @custom:api public
    function finalizeDeploy(uint40 seqNumEx, UUID reqId) external {
        address caller = msg.sender;
        _requireOwner(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        _detachCreator(_contracts[CU.BalanceMgr]);
        _detachCreator(_contracts[CU.BoxMgr]);
        _detachCreator(_contracts[CU.Crt]);
        _detachCreator(_contracts[CU.EarnDateMgr]);
        _detachCreator(_contracts[CU.InstRevMgr]);
        _detachCreator(_contracts[CU.RevMgr]);
        _detachCreator(_contracts[CU.Vault]);
        _detachCreator(_contracts[CU.XferMgr]);

        _setCallRes(caller, seqNumEx, reqId, true);
    }

    function _detachCreator(address userAddr) internal {
        IContractUser user = IContractUser(userAddr);
        user.setContract(NoSeqNum, NoReqId, CU.Creator, AddrZero);

        _verifyAddress(AddrZero, user.getContract(CU.Creator), 'getCreator');

        emit CreatorDetached(userAddr);
    }

    function _verifyAddress(address expect, address actual, string memory what) internal pure {
        if (actual != expect) revert BadAddress(expect, actual, what);
    }

    function _verifyUint(uint expect, uint actual, string memory what) internal pure {
        if (actual != expect) revert BadUint(expect, actual, what);
    }
}
