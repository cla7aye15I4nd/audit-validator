// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './ContractUser.sol';
import './IBalanceMgr.sol';
import './LibraryAC.sol';
import './LibraryCU.sol';
import './LibraryUtil.sol';
import './Types.sol';

/// @title BalanceMgr: Balance manager for revenue allocations and claims by RevMgr and XferMgr respectively
/// @author Jason Aubrey, GigaStar
/// @dev Insulates RevMgr from bytecode size
/// - Signed ints used with `_balances` to allow edge cases where balances are negative due to corrections
/// - Upgradeable via UUPS. See PROXY_OPTIONS for more.
/// @custom:api public
/// @custom:deploy uups
// prettier-ignore
contract BalanceMgr is Initializable, UUPSUpgradeable, IBalanceMgr, ContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint constant VERSION = 10; // 123 => Major: 12, Minor: 3 (always 1 digit)

    // ────────────────────────────────────────────────────────────────────────────
    // Fields (See MEM_LAYOUT), default visibility is 'internal'
    // ────────────────────────────────────────────────────────────────────────────
    // NOTE: The address mapping allows multiple revenue tokens to coexist (eg as USDC and EURC)
    mapping(address => mapping(UUID => int)) _balances; // Key: token => ownerEid; Unclaimed qty

    // New fields should be inserted immediately above this line to preserve layout

    // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
    uint[20] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────

    /// @dev Ensures the logic contract cannot be hijacked before the `initializer` runs
    /// - Sets version to `type(uint64).max` + `emit Initialized(version)` to prevent future initialization
    /// - `initialize` is where the business logic is initialized on proxies
    /// - For more info see comments in 'Initializable.sol'
    /// @custom:api private
    constructor() { _disableInitializers(); } // Do not add code to cstr

    /// @dev Basically replaces the constructor in a proxy oriented contract
    /// - `initializer` modifier ensures this function can only be called once during deploy
    /// - See UUPS_UPGRADE_SEQ for details on how to upgrade this contract
    /// @param creator Creator's address for access control during setup
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @custom:api protected
    function initialize(address creator, UUID reqId) external override initializer {
        __ContractUser_init(creator, reqId);
    }

    /// @dev Upgrade hook to enforce permissions
    /// - Ensure `preUpgrade` is called before this function to stage required params
    function _authorizeUpgrade(address newImpl) internal override(UUPSUpgradeable) {
        _authorizeUpgradeImpl(msg.sender, newImpl);
    }

    /// @dev Get the current version
    function getVersion() external pure override virtual returns(uint) { return VERSION; }

    /// @dev Set an owner's unclaimed balance during contract creation
    /// - Requires caller to have the owner/creator role
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param tokAddr Token related to the balance
    /// @param ownerEids Owner external ids
    /// @param balances Owner balances
    /// @param relative true: Balances are added to existing; false: balances are set
    /// @custom:api public
    function setOwnerBalances(uint40 seqNumEx, UUID reqId, address tokAddr,
        UUID[] calldata ownerEids, int[] calldata balances, bool relative) external override
    { unchecked {
        address caller = msg.sender;
        _requireOnlyCreator(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        uint len = Util.requireSameArrayLength(ownerEids.length, balances.length);
        for (uint i = 0; i < len; ++i) { // Ubound: Caller must page
            if (relative) {
                _balances[tokAddr][ownerEids[i]] += balances[i];
            } else {
                _balances[tokAddr][ownerEids[i]] = balances[i];
            }
        }

        _setCallRes(caller, seqNumEx, reqId, true);
    } }

    /// @dev Get an owner's balance (sum of unclaimed qty)
    /// @param tokAddr Token related to the balance
    /// @param ownerEid Owner's external id
    /// @return The owner's balance info
    function getOwnerBalance(address tokAddr, UUID ownerEid) external view override returns(int) {
        return _balances[tokAddr][ownerEid];
    }

    /// @dev Get a owner balances (sum of unclaimed qty)
    /// @param tokAddr Token related to the balance
    /// @param ownerEids Owner external ids to query
    /// @return balances Owner balances for each ownerEid
    function getOwnerBalances(address tokAddr, UUID[] calldata ownerEids) external view override
        returns(int[] memory balances)
    { unchecked {
        balances = new int[](ownerEids.length);
        uint balancesLen = balances.length;
        for (uint i = 0; i < balancesLen; ++i) { // Ubound: Caller must page
            balances[i] = _balances[tokAddr][ownerEids[i]];
        }
    } }

    // ───────────────────────────────────────
    // Operations: Xfer Revenue Proposal
    // ───────────────────────────────────────

    /// @dev Set an owner balance via an absolute or relative qty (+ or -)
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param tokAddr Token related to the balance
    /// @param ownerEid Owner's external id
    /// @param qty Quantity to add
    /// @param relative true: Balances are added to existing; false: balances are set
    /// @custom:api private
    function updateBalance(address tokAddr, UUID ownerEid, int qty, bool relative) external override {
        _requireOnlyRevMgr(msg.sender); // Access control, see `_isReqReplay` above if this changes

        if (relative) {
            _balances[tokAddr][ownerEid] += qty;
        } else {
            _balances[tokAddr][ownerEid] = qty;
        }
    }

    /// @dev Claim the requested qty from an owner's balance
    /// - Caller must transfer the funds else return them via `unclaimQty` or revert
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param tokAddr Token related to the balance
    /// @param ownerEid Owner's external id
    /// @param qty Quantity to claim
    /// @return ok Whether the claim was successful
    /// @custom:api private
    function claimQty(address tokAddr, UUID ownerEid, uint qty) external override returns(bool ok) {
        _requireOnlyXferMgr(msg.sender); // Access control, see `_isReqReplay` above if this changes

        int balance = _balances[tokAddr][ownerEid];
        if (balance >= int(qty)) {
            _balances[tokAddr][ownerEid] -= int(qty);
            // Since the ccy token emits an event, a batch event is emitted downstream rather than here
            ok = true;
        }
    }

    /// @dev Unclaim qty from an owner's balance such as after a transfer problem
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param tokAddr Token related to the balance
    /// @param ownerEid Owner's external id
    /// @param qty Quantity to refund
    /// @custom:api private
    function unclaimQty(address tokAddr, UUID ownerEid, uint qty) external override {
        _requireOnlyXferMgr(msg.sender); // Access control, see `_isReqReplay` above if this changes

        _balances[tokAddr][ownerEid] += int(qty);
    }
}
