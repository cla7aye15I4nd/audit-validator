// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './ContractUser.sol';
import './IBalanceMgr.sol';
import './IBox.sol';
import './IEarnDateMgr.sol';
import './IInstRevMgr.sol';
import './IRevMgr.sol';
import './LibraryAC.sol';
import './LibraryCU.sol';
import './LibraryIR.sol';
import './LibraryOI.sol';
import './LibraryString.sol';
import './LibraryUtil.sol';
import './Types.sol';

/// @title RevMgr: Revenue manager for history, allocations, and claims
/// @author Jason Aubrey, GigaStar
/// @notice Focuses on instrument revenue proposals and management of inst revenue and ownership per inst earn date
/// @dev Insulates Vault from bytecode size
/// - Upgradeable via UUPS. See PROXY_OPTIONS for more.
/// @custom:api public
/// @custom:deploy uups
// prettier-ignore
contract RevMgr is Initializable, UUPSUpgradeable, IRevMgr, ContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint constant VERSION = 10; // 123 => Major: 12, Minor: 3 (always 1 digit)

    // Gas usage estimates based on worst case analysis, see EXEC_GAS
    uint constant GAS_EXEC_LONG  = 500_000; // Sec# [1-11], avg likely <= 200k
    uint constant GAS_EXEC_SHORT = 100_000; // Sec# [1, 9-11]

    // ────────────────────────────────────────────────────────────────────────────
    // Fields (See MEM_LAYOUT), default visibility is 'internal'
    // ────────────────────────────────────────────────────────────────────────────
    OI.Emap _ownSnaps;                  // Key: InstName, EarnDate, [Eid]; OwnInfo (Owner's qty/revenue)
    OI.OwnSnapPool _ownSnapPool;        // An OwnSnap pool to allow pass-by-ref to reduce txs
    mapping(uint => Prop) _proposals;   // Key: pid; A request linked to an instrument revenue proposal

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
        OI.Emap_init(_ownSnaps);
    }

    /// @dev Upgrade hook to enforce permissions
    /// - Ensure `preUpgrade` is called before this function to stage required params
    function _authorizeUpgrade(address newImpl) internal override(UUPSUpgradeable) {
        _authorizeUpgradeImpl(msg.sender, newImpl);
    }

    /// @dev Get the current version
    function getVersion() external pure override virtual returns(uint) { return VERSION; }

    // ───────────────────────────────────────
    // Operations: Instrument Revenue Proposal
    // ───────────────────────────────────────

    /// @dev Add an instrument revenue proposal, this creates a stub that must be populated by additional calls
    /// - Inputs validated upstream
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param pid Proposal ID, always increases
    /// @param reqId Request ID
    /// @param ccyAddr Revenue currency address
    /// @param correction Whether the proposal is a correction
    /// @custom:api private
    function propCreate(uint pid, UUID reqId, address ccyAddr, bool correction) external override {
        _requireOnlyVault(msg.sender); // Access control

        Prop storage prop = _proposals[pid];
        OI.Emap_init(prop.ownSnaps);

        PropHdr storage ph = prop.hdr;
        ph.pid = pid;
        ph.eid = reqId;
        ph.iInst = 0;  // Not IR.FIRST_INDEX
        ph.iOwner = 0; // Not OI.FIRST_INDEX;
        ph.correction = correction;

        IInstRevMgr(_contracts[CU.InstRevMgr]).propCreate(pid, reqId, ccyAddr, correction);
    }

    /// @dev Bundles vars to reduce stack pressure
    /// - Upgradability is not a concern for this ephemeral type
    /// @custom:api private
    struct PropAddOwnersCtx {
        uint pid;               // Cached from PropHdr
        bytes32 instNameKey;    // Calculated
        uint bookLen;           // Calculated
    }

    /// @notice Add to the ownership snapshot for an instrument earn date
    /// - Must occur after `propAddInstRev` since it stores revenue per owner in each OwnInfo to simplify the model
    ///   and that requires InstRev for validation
    /// @dev Idempotency is provided via correct client processing of function i/o
    /// - Naming uses a metaphor where each upload has a page of lines (OwnInfo[]) added to a book of lines
    /// - CallRes: Indicates progress where `rc` is set from `AddOwnRc`
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param req See struct definition - reduces stack pressure
    /// @custom:api public
    function propAddOwners(uint40 seqNumEx, UUID reqId, AddOwnersReq calldata req) external override {
        _requireOnlyAgent(msg.sender); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(msg.sender, seqNumEx, reqId)) return;

        ICallTracker.CallRes memory result = _propAddOwners(req);

        _setCallRes(msg.sender, seqNumEx, reqId, result);
    }

    /// @dev Helper simplifies caller via early returns
    function _makeCr(AddOwnRc rc) internal pure returns(CallRes memory result) {
        result.rc = uint16(rc);
    }

    /// @dev Helper simplifies caller via early returns
    function _propAddOwners(AddOwnersReq calldata req) internal returns(CallRes memory result)
    { unchecked {
        // Get proposal
        Prop storage prop = _proposals[req.pid];

        // Cache values
        // slither-disable-next-line uninitialized-local (zero-init is ok)
        PropAddOwnersCtx memory ctx;
        { // var scope to reduce stack pressure
            PropHdr storage ph = prop.hdr;
            ctx.pid = ph.pid;
            ctx.instNameKey = String.toBytes32(req.instName);
        }

        if (ctx.pid == 0) { return _makeCr(AddOwnRc.NoProp); }
        if (prop.hdr.uploadedAt > 0) { return _makeCr(AddOwnRc.ReadOnly); }

        // Get instrument revenue
        IR.InstRev memory instRev =
            IInstRevMgr(_contracts[CU.InstRevMgr]).getInstRevForInstDate(req.pid, req.instName, req.earnDate);
        if (instRev.uploadedAt == 0) { return _makeCr(AddOwnRc.NoInstRev); }

        // Get owner snapshot, ensures no duplicate snapshots for key=(instNameKey,earnDate)
        OI.OwnSnap storage book = OI.getSnapshot(prop.ownSnaps, ctx.instNameKey, req.earnDate, _ownSnapPool);
        if (book.uploadedAt > 0) { return _makeCr(AddOwnRc.ReadOnly); }

        // Ensure OwnSnap is conditionally found or missing in executed state
        if (req.iAppend == 0) {
            bool exists = OI.exists(_ownSnaps, ctx.instNameKey, req.earnDate);
            if (prop.hdr.correction) {
                if (!exists) { return _makeCr(AddOwnRc.NotFound); }
            } else if (exists) { return _makeCr(AddOwnRc.Exists); }
        }

        // Cache values
        ctx.bookLen = OI.ownersLen(book); // Metaphor: Each page of lines is added to a book of lines

        // Review inputs for paging
        if (req.page.length == 0) { return _makeCr(AddOwnRc.BadPage); }
        if (req.iAppend != ctx.bookLen)  { return _makeCr(AddOwnRc.BadIndex); }
        if (ctx.bookLen + req.page.length > req.total) { return _makeCr(AddOwnRc.BadTotal); }

        // Cache values
        uint ownRevSum = 0; // Current page sum
        { // var scope to reduce stack pressure
            uint unitRev = instRev.unitRev;
            uint gasLimit = Util.GasCleanupDefault;

            // Copy from calldata to storage while gas allows; This is a fast loop with many inputs
            // Ubounds: Condition 1: caller must page, Condition 2: gas available vs limit
            for (; result.count < req.page.length; ++result.count) {
                if (gasleft() < gasLimit) { result.rc = uint16(AddOwnRc.LowGas); break; }

                // Add an owner to the snapshot after validation
                OI.OwnInfo calldata owner = req.page[result.count];
                uint ownerRev = owner.qty * unitRev;
                if (isEmpty(owner.eid) || ownerRev == 0 || owner.revenue != ownerRev) {
                    result.rc = uint16(AddOwnRc.BadLine);
                    break;
                }
                OI.addOwnerToSnapshot(book, owner); // Add line to book (OwnInfo to OwnSnap)
                ownRevSum += ownerRev;
            }
        }

        // State tracking / feedback
        book.totalRevenue += ownRevSum;
        prop.hdr.totalRevenue += ownRevSum;
        ctx.bookLen = OI.ownersLen(book);
        if (result.count > 0) {
            emit OwnersUploaded(req.pid, req.instName, req.earnDate, result.count);  // Progress
        }
        if (result.count == req.page.length) {
            if (ctx.bookLen < req.total) {
                result.rc = uint16(AddOwnRc.FullPage);  // All in current page/call uploaded
            } else {
                // Ensure the sum of owner revenue matches the instrument revenue
                if (instRev.totalRev != instRev.totalRev) {
                    revert RevDiff(ctx.pid, req.instName, req.earnDate, instRev.totalRev, instRev.totalRev);
                }

                result.rc = uint16(AddOwnRc.AllPages);  // All uploaded
                book.uploadedAt = block.timestamp;      // Mark snapshot as upload complete
                emit AllOwnersUploaded(req.pid, req.instName, req.earnDate, ctx.bookLen);
            }
        }
    } }

    /// @dev Reviews progress of `propAddInstRev` and `propAddOwners` and marks request as fully uploaded
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param pid Proposal ID
    /// @return rc Indicates progress:
    /// - Ok        : Proposal upload complete
    /// - NoProp    : No proposal found by pid
    /// - DiffLens  : Different count of instrument revenues and owner snapshots
    /// - NoInstRev : No instrument revenue in proposal
    /// - PartOwners: Owners are only partially uploaded
    /// @custom:api private
    function propFinalize(uint pid) external override returns(PropRevFinalRc rc) {
        _requireOnlyVault(msg.sender); // Access control
        rc = _propFinalize(pid);
    }

    function _propFinalize(uint pid) internal returns(PropRevFinalRc rc) {
        // Get proposal
        Prop storage prop = _proposals[pid];
        PropHdr storage ph = prop.hdr;
        if (ph.pid == 0) return PropRevFinalRc.NoProp;
        if (ph.uploadedAt > 0) return PropRevFinalRc.Ok;

        // Ensure proposal has >= 1 instrument revenue
        IInstRevMgr instRevMgr = IInstRevMgr(_contracts[CU.InstRevMgr]);
        uint instRevsLen = instRevMgr.getInstRevsLen(pid, "", 0);
        if (instRevsLen == 0) return PropRevFinalRc.NoInstRev;

        // Ensure instrument revenue and owner snapshot keys are 1:1. `propAddOwners` already ensures there is an
        // InstRev for each OwnSnap and no duplicate OwnSnap, so this length check ensures 1:1.
        uint ownSnapsLen = OI.ownSnapsLen(prop.ownSnaps);
        if (instRevsLen != ownSnapsLen) return PropRevFinalRc.DiffLens;

        // Ensure the last `OwnSnap` is completely uploaded
        OI.PoolRef[] storage poolRefs = prop.ownSnaps.poolRefs;
        if (poolRefs.length == 0) return PropRevFinalRc.PartOwners; // Defensive: Not currently possible
        OI.PoolRef memory poolRef = poolRefs[poolRefs.length - 1];
        uint lastPoolId = poolRef.poolId;
        OI.OwnSnap storage ownSnap = _ownSnapPool.ownSnaps[lastPoolId];
        if (ownSnap.uploadedAt == 0) return PropRevFinalRc.PartOwners;

        // Ensure the correction flag is aligned with the allocation fixes count
        if (!instRevMgr.propFinalize(pid)) return PropRevFinalRc.AllocFixes;

        ph.uploadedAt = block.timestamp; // Mark proposal as upload complete
        // rc = PropRevFinalRc.Ok is zero-value, implicitly set
    }

    /// @dev Bundles vars to reduce stack pressure
    /// - Upgradability is not a concern for this ephemeral type
    /// @custom:api private
    struct PropExecuteCtx {
        IEarnDateMgr earnDateMgr;   // Cached from _contracts
        IBalanceMgr balanceMgr;     // Cached from _contracts
        IInstRevMgr instRevMgr;     // Cached from _contracts
        uint instRevsLen;           // Calculated
        uint iInst;                 // Calculated
        uint iOwner;                // Calculated
        uint ownersLen;             // Calculated
        uint gasLimit;              // Calculated
        uint poolId;                // Calculated
        address ccyAddr;            // Reduces var count passed to helper
        bool correction;            // Cached from PropHdr
    }

    /// @dev Execute an instrument revenue proposal as gas allows, progress given by return code
    /// - This function should be called until `code=ExecRevRc.Done`, work is unlikely to complete in a single tx
    /// - Idempotency is provided by an private cursor. Excess calls are safe and only waste gas.
    /// - All values in the proposal validated upstream: before on-chain, during upload/creation, and during approval
    /// - Instruments processing is sequential. Consider `pruneProposal` in the unlikely event of blocked progress.
    /// - See REV_MGR_PROP_EXEC_BIG_O for pros/cons on this algo being O(N^2) vs O(N)
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param pid Proposal ID
    /// @return result Indicates progress where `rc` is set from `ExecRevRc`
    /// - Progress: Partial progress
    /// - Done    : Proposal is complete
    /// - NoProp  : No proposal found by pid
    /// - PartProp: Partial proposal found, not fully uploaded
    /// - PropStat: Proposal status not fit for execution
    /// - LowFunds: An event should provide more context, such as: LowFunds, LowAllowance, XferErr
    /// - NoOwners: No owners found for instrument revenue
    /// - NoInstRev: Should not happen, would indicate a corrupt interaction with the InstRevMgr
    /// @custom:api private
    function propExecute(uint pid) external override returns(CallRes memory result) {
        _requireOnlyVault(msg.sender); // Access control
        result = _propExecute(pid);
    }

    /// @dev Helper simplifies caller via early returns
    function _propExecute(uint pid) internal returns(CallRes memory result)
    { unchecked {
        // Get proposal to begin/resume execution
        Prop storage prop = _proposals[pid];
        // slither-disable-next-line uninitialized-local (zero-init is ok)
        PropExecuteCtx memory ctx;
        { // var scope to reduce stack pressure
            PropHdr storage ph = prop.hdr;
            if (ph.pid == 0) { result.rc = uint16(ExecRevRc.NoProp); return result; }
            if (ph.executedAt > 0) { result.rc = uint16(ExecRevRc.Done); return result; }
            if (ph.uploadedAt == 0) { result.rc = uint16(ExecRevRc.PartProp); return result; }

            // Cache values
            ctx.correction = ph.correction;
            ctx.earnDateMgr = IEarnDateMgr(_contracts[CU.EarnDateMgr]);
            ctx.instRevMgr = IInstRevMgr(_contracts[CU.InstRevMgr]);
            ctx.balanceMgr = IBalanceMgr(_contracts[CU.BalanceMgr]);
            ctx.instRevsLen = ctx.instRevMgr.getInstRevsLen(pid, "", 0);
            ctx.iInst = ph.iInst;      // Index to resume
            ctx.iOwner = ph.iOwner;    // Index to resume
        }

        // Ubounds: Condition 1: caller must page, Condition 2: gas available vs limit
        while (ctx.iInst < ctx.instRevsLen) {
            // Set `gasLimit` with a conditional `cleanup` margin, where execution paths are either:
            //     A) `GAS_EXEC_LONG` : First pass for an instrument, gas likely exhuasted in section 9
            //     B) `GAS_EXEC_SHORT`: Resume an instrument, skip section 2-8, gas likely exhuasted in section 9
            //     C) Either (A) or (B) but gas not exhausted in section 9 and execution continues here
            ctx.gasLimit = ctx.iOwner == 0 ? GAS_EXEC_LONG : GAS_EXEC_SHORT; // See EXEC_GAS
            if (gasleft() < ctx.gasLimit) break;

            ++result.lrc; // Successful instruments, overwritten on error; `count` tracks owners

            // 1) Cache values
            IR.InstRev memory ir = ctx.instRevMgr.getInstRev(pid, ctx.iInst);
            ctx.ccyAddr = ir.ccyAddr;

            // Get the poolId for the OwnSnap with the same key as instRev, `propFinalize` ensures they are 1:1
            // This allows the owners to be transferred from proposal to executed state by reference (poolId)
            ctx.poolId = OI.getPoolId(prop.ownSnaps, ir.instNameKey, ir.earnDate);

            // Defensive: Sanity check though seemingly not possible
            if (ctx.poolId == OI.SentinelValue) {
                result.rc = uint16(ExecRevRc.NoOwners); result.lrc = uint16(ctx.iInst); break;
            }

            // Process the InstRev and OrdSnap if first pass for this InstRev, See FOOTER_CONDITION
            if (ctx.iOwner == 0) {
                // 2-3) Conditionally add/overwrite InstRev in the emap (all fields copied and indexes built)
                { // var scope to reduce stack pressure
                    ExecRevRc irmRc = ctx.instRevMgr.propExecInstRev(pid, ctx.iInst);
                    if (irmRc != ExecRevRc.Progress) {
                        result.rc = uint16(irmRc);
                        result.lrc = uint16(ctx.iInst);
                        break;
                    }
                }
                if (ctx.correction) {
                    // 4) Overwrite OwnSnap in emap via pool id, indexes already built
                    OI.upsertPoolId(_ownSnaps, ir.instNameKey, ir.earnDate, ctx.poolId); // Copy ownSnap by ref (poolId)

                    // No need to call `EarnDateMgr.addInstEarnDate`, already exists (key unchanged)
                } else { // normal path
                    // 4) Add OwnSnap to the emap via pool id
                    // `propExecInstRev` does the existance check on the same key and these are only added together
                    OI.addPoolIdNoCheck(_ownSnaps, ir.instNameKey, ir.earnDate, ctx.poolId); // Copy ownSnap by ref

                    // 5-8) Update emaps for instruments and earn dates (and combinations)
                    ctx.earnDateMgr.addInstEarnDate(0, UuidZero, ir.instName, ir.earnDate);
                }

                ctx.gasLimit = GAS_EXEC_SHORT; // Recalculate for path until function return
            }

            // 9) Increase each owner balance (start or resume)
            OI.OwnSnap storage ownSnap = _ownSnapPool.ownSnaps[ctx.poolId];
            { // var scope to reduce stack pressure
                uint iOwnerBegin = ctx.iOwner;
                // Execution path is conditioned on whether the proposal is a fix/correction
                (ctx.iOwner, ctx.ownersLen) = ctx.correction
                    ? _propExecOwnSnapFix(pid, ctx, ir.instNameKey, ir.earnDate)
                    : _propExecOwnSnapNormal(ownSnap, ctx);
                result.count += uint16(ctx.iOwner - iOwnerBegin); // Track owners
            }

            // 10) Processed all owner balances?
            if (ctx.iOwner >= ctx.ownersLen) {          // Then all owners handled for instrument
                ++ctx.iInst;                            // Move cursor to next instrument
                ctx.iOwner = 0;                         // Reset owner cursor for next instrument
                ownSnap.executedAt = block.timestamp;   // Mark instrument revenue as fully executed

                // Event's `totalRev` param is the full allocation for the inst earn date. During a correction,
                // this is not the delta, this is still the full allocation including corrections
                emit RevenueAllocated(pid, ir.instName, ir.earnDate, ctx.ownersLen, ir.totalQty,
                    ir.totalRev, ir.unitRev);
            }
        }

        // 11) Track progress to complete or resume
        prop.hdr.iInst = ctx.iInst;                   // Store progress
        prop.hdr.iOwner = ctx.iOwner;                 // Store progress
        if (ctx.iInst >= ctx.instRevsLen) {
            prop.hdr.executedAt = block.timestamp;    // Mark request as fully executed
            ctx.instRevMgr.propExecuted(pid);
            result.rc = uint16(ExecRevRc.Done);
            // No proposal executed event here as handled by Vault
        }
        // result.rc If not set, ExecRevRc.Progress is zero-value
    } }

    /// @dev `propExecute` helper to increase owner balances in the fix/correction flow
    /// - Modularizes the path for normal flows vs corrections
    function _propExecOwnSnapFix(uint pid, PropExecuteCtx memory ctx, bytes32 instNameKey, uint earnDate) internal
        returns(uint, uint)
    {
        // 9) Upper bounds: condition 1: none, condition 2: gas remaining
        uint ownersLen = ctx.instRevMgr.getAllocFixesLenByKey(pid, instNameKey, earnDate);
        while (ctx.iOwner < ownersLen) {
            // Get fix info from InstRevMgr for SIZE reasons, performance not as important in this case but would be
            // faster & +complex to do this loop within InstRevMgr, simpler this way for now and only ~800 gas warm
            (int revenue, UUID ownerEid) = ctx.instRevMgr.getAllocFixByKey(pid, instNameKey, earnDate, ctx.iOwner);

            // Adjust revenue allocation (adjust owner's balance up/down)
            ctx.balanceMgr.updateBalance(ctx.ccyAddr, ownerEid, revenue, true);

            ++ctx.iOwner; // FOOTER_CONDITION: Ensures `iOwner > 0` after a `break` + resume with same `iInst`
            if (gasleft() < ctx.gasLimit) break;
        }
        return (ctx.iOwner, ownersLen);
    }

    /// @dev `propExecute` helper to increase owner balances in the normal flow
    /// - Modularizes the path for normal flows vs corrections
    function _propExecOwnSnapNormal(OI.OwnSnap storage ownSnap, PropExecuteCtx memory ctx) internal
        returns(uint, uint)
    {
        // 9) Upper bounds: condition 1: none, condition 2: gas remaining
        uint ownersLen = OI.ownersLen(ownSnap);
        while (ctx.iOwner < ownersLen) {
            OI.OwnInfo storage owner = OI.getByIndex(ownSnap, ctx.iOwner);

            // Allocate revenue (increase owner's balance)
            ctx.balanceMgr.updateBalance(ctx.ccyAddr, owner.eid, int(owner.revenue), true);

            // FOOTER_CONDITION: Ensures `iOwner > 0` after a `break` + resume with same `iInst`
            ++ctx.iOwner;
            if (gasleft() < ctx.gasLimit) break;
        }
        return (ctx.iOwner, ownersLen);
    }

    /// @dev Remove an instrument earn date (InstRev + OwnSnap) from a sealed proposal
    /// - This is an escape hatch to help ensure progress in `propExecute`
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param pid Proposal ID
    /// @param instName Instrument name
    /// @param earnDate Instrument's earn date
    /// @return rc Indicates progress:
    /// - Done     : Proposal is complete
    /// - NoProp   : No proposal found by pid
    /// - PropStat : Proposal is not fully uploaded, create a new proposal
    /// - NoInst   : Not found in proposal by key
    /// - LastInst : Pruning the last instrument would invalidate the proposal
    /// - MidBal   : Proposal is in the middle of balance increases, see `rc` below (Should not happen)
    /// - LastInst : Pruning the last instrument would invalidate the proposal
    /// @custom:api private
    function pruneProp(uint pid, string calldata instName, uint earnDate) external override returns(PruneRevRc rc) {
        _requireOnlyVault(msg.sender); // Access control
        rc = _pruneProp(pid, instName, earnDate);
    }

    /// @dev Helper simplifies caller via early returns
    function _pruneProp(uint pid, string calldata instName, uint earnDate) internal returns(PruneRevRc rc) {
        // Get proposal
        Prop storage prop = _proposals[pid];
        PropHdr storage ph = prop.hdr;
        if (ph.pid == 0) return PruneRevRc.NoProp;
        if (ph.executedAt > 0 || ph.uploadedAt == 0) return PruneRevRc.PropStat;

        // Defensive: Get the instrument from the execution cursor and ensure it's not mid-balance update.
        // This should only be possible from an in-progress execution that should not be blockable - a pathology
        if (ph.iOwner > 0) return PruneRevRc.MidBal; // Balance increases in range [0:iOwner) would need to be reverted

        // Remove InstRev from proposal
        uint removedRev;
        (rc, removedRev) = IInstRevMgr(_contracts[CU.InstRevMgr]).pruneProp(pid, instName, earnDate);
        if (rc != PruneRevRc.Done) return rc;

        // Remove InstRev from total revenue
        uint totalRevenue = ph.totalRevenue;
        if (totalRevenue >= removedRev) { // Defensive: Should always be true
            totalRevenue -= removedRev;
            ph.totalRevenue = totalRevenue;
        }

        // Remove OwnSnap from proposal
        bytes32 instNameKey = String.toBytes32(instName);
        OI.remove(prop.ownSnaps, instNameKey, earnDate);
        emit PropPruned(pid, instName, earnDate);
        // rc = PruneRevRc.Done; Occurs implicitly due to zero-value
    }

    // ───────────────────────────────────────
    // Getters: Proposal
    // ───────────────────────────────────────

    /// @notice Get instrument revenue proposal header info.
    /// - To get `InstRev` in the prop, see `getInstRevs`
    /// - To get `OwnInfo` in the prop, see `getOwnInfo`
    /// @param pid Proposal ID, identifies an existing proposal
    function getPropHdr(uint pid) external view override returns(PropHdr memory info) {
        return _proposals[pid].hdr;
    }

    // ───────────────────────────────────────
    // Getters: Owner Information (Proposal or Executed)
    // ───────────────────────────────────────

    function _getOwnSnap(uint pid, string calldata instName, uint earnDate) private view
        returns(OI.OwnSnap storage)
    {
        bytes32 instNameKey = String.toBytes32(instName);
        OI.Emap storage ownSnaps = pid == 0 ? _ownSnaps : _proposals[pid].ownSnaps;
        return OI.tryGetOwnSnap(ownSnaps, instNameKey, earnDate, _ownSnapPool);
    }

    /// @dev Get owner information (qty, revenue) for an instrument and earn date
    /// - To enumerate instrument or earn dates, or one within the other, see `EarnDateMgr`
    /// @param pid Proposal ID, >0 to query a proposal, =0 to query executed state
    /// @param instName Instrument name, empty is not allowed
    /// @param earnDate Earn date, 0 not allowed
    /// @param ownerEid Owner's external id
    /// @return revenue (units owned) x (unit price) for the inputs
    /// @return qty units owned
    function getOwnInfo(uint pid, string calldata instName, uint earnDate, UUID ownerEid) external view override
        returns(uint revenue, uint qty)
    {
        _checkInstNameEarnDate(instName, earnDate);

        OI.OwnSnap storage ownSnap = _getOwnSnap(pid, instName, earnDate);
        if (OI.ownersLen(ownSnap) == 0) return (revenue, qty);
        OI.OwnInfo storage owner = ownSnap.owners[ownSnap.idxEid[ownerEid]]; // Sentinel value if not found
        return (owner.revenue, owner.qty);
    }

    /// @dev Get count of owner information for an instrument and earn date
    /// - To enumerate instrument or earn dates, or one within the other, see `EarnDateMgr`
    /// @param pid Proposal ID, >0 to query a proposal, =0 to query executed state
    /// @param instName Instrument name, empty not allowed
    /// @param earnDate Earn date, 0 not allowed
    /// @return len Number of owners
    /// @return uploadedAt When owners upload completed, =0 if not complete
    /// @return executedAt When owners allocation completed, =0 if not complete
    function getOwnInfosLen(uint pid, string calldata instName, uint earnDate) external view override
        returns(uint len, uint uploadedAt, uint executedAt)
    {
        _checkInstNameEarnDate(instName, earnDate);

        OI.OwnSnap storage ownSnap = _getOwnSnap(pid, instName, earnDate);
        return (OI.ownersLen(ownSnap), ownSnap.uploadedAt, ownSnap.executedAt);
    }

    /// @dev Get owner information (eid, qty, revenue) for an instrument and earn date
    /// - To enumerate instrument or earn dates, or one within the other, see `EarnDateMgr`
    /// - Caller must page outputs to avoid gas issues, see PAGE_REQUESTS
    /// @param pid Proposal ID, >0 to query a proposal, =0 to query executed state
    /// @param instName Instrument name, empty is not allowed
    /// @param earnDate Earn date, 0 not allowed
    /// @param iBegin Index in the array to begin processing
    /// @param count Items to get, 0 = [iBegin:] (may exceed gas), See `getOwnInfosLen(instName, earnDate)`
    /// @return ownInfos requested range of items
    function getOwnInfos(uint pid, string calldata instName, uint earnDate, uint iBegin, uint count)
        external view override returns(OI.OwnInfo[] memory ownInfos)
    { unchecked {
        _checkInstNameEarnDate(instName, earnDate);

        // Get owner infos array
        OI.OwnSnap storage ownSnap = _getOwnSnap(pid, instName, earnDate);
        OI.OwnInfo[] storage values = ownSnap.owners;

        // Calculate results length
        iBegin += OI.FIRST_INDEX; // to ignore sentinel value
        uint len = Util.getRangeLen(values.length, iBegin, count);
        if (len == 0) return ownInfos;

        // Get results slice, indexes are scattered across the global array
        ownInfos = new OI.OwnInfo[](len);
        for (uint i = 0; i < len; ++i) { // Ubound: Caller must page
            ownInfos[i] = values[iBegin + i];
        }
    } }

    /// @dev Validate args are not empty
    function _checkInstNameEarnDate(string calldata instName, uint earnDate) private pure {
        if(bytes(instName).length == 0) revert EmptyString();
        if(earnDate == 0) revert EmptyDate();
    }
}
