// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './ContractUser.sol';
import './IBox.sol';
import './IBoxMgr.sol';
import './IInstRevMgr.sol';
import './IRevMgr.sol';
import './IVault.sol';
import './LibraryAC.sol';
import './LibraryCU.sol';
import './LibraryIR.sol';
import './LibraryUtil.sol';
import './LibraryString.sol';
import './Types.sol';

/// @title InstRevMgr: Instrument revenue manager for proposals and history
/// @author Jason Aubrey, GigaStar
/// @notice Provides ledgering of instrument revenue and a related proposal
/// @dev Insulates RevMgr from bytecode size
/// - Upgradeable via UUPS. See PROXY_OPTIONS for more.
/// @custom:api public
/// @custom:deploy uups
// prettier-ignore
contract InstRevMgr is Initializable, UUPSUpgradeable, IInstRevMgr, ContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint constant VERSION = 10; // 123 => Major: 12, Minor: 3 (always 1 digit)

    // ────────────────────────────────────────────────────────────────────────────
    // Fields (See MEM_LAYOUT), default visibility is 'internal'
    // ────────────────────────────────────────────────────────────────────────────
    IR.Emap _instRevs;                  // Key: InstName, EarnDate; InstRev - Instrument Revenue
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
        IR.Emap_init(_instRevs);
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

    function _getProp(uint pid) private view returns(Prop storage prop, PropHdr storage ph) {
        prop = _proposals[pid];
        ph = prop.hdr;
    }

    /// @dev Add an instrument revenue proposal, this creates a stub that must be populated by additional calls
    /// - Inputs validated upstream
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param pid Proposal ID, always increases
    /// @param reqId Request ID
    /// @param ccyAddr Revenue currency address
    /// @param correction Whether the proposal is a correction for previously incorrect values
    /// @custom:api private
    function propCreate(uint pid, UUID reqId, address ccyAddr, bool correction) external override {
        _requireOnlyRevMgr(msg.sender); // Access control

        (Prop storage prop, PropHdr storage ph) = _getProp(pid);
        IR.Emap_init(prop.instRevs);

        ph.pid = pid;
        ph.eid = reqId;
        ph.correction = correction;
        ph.ccyAddr = ccyAddr;
    }

    /// @dev Upload input validation
    function _reviewUploadInputs(uint pid, uint pageLen, uint bookLen, uint uploadedAt, uint iAppend, uint total)
        private pure returns(CallRes memory result)
    {
        // Review proposal header
        if (pid == 0) result.rc = uint16(AddInstRc.NoProp);
        else if (uploadedAt > 0) result.rc = uint16(AddInstRc.ReadOnly);
        // Review inputs for paging
        else if (pageLen == 0) result.rc = uint16(AddInstRc.BadPage);
        else if (iAppend != bookLen) result.rc = uint16(AddInstRc.BadIndex);
        else if (bookLen + pageLen > total) result.rc = uint16(AddInstRc.BadTotal);
    }

    /// @dev Bundles vars to reduce stack pressure
    /// - Upgradability is not a concern for this ephemeral type
    /// @custom:api private
    struct PropAddInstRevCtx {
        uint pid;               /// Cached from PropHdr
        address ccyAddr;        /// Cached from PropHdr
        bool correction;        /// Cached from PropHdr
        uint gasLimit;          /// Calculated
        bytes32 instNameKey;    /// Cached from InstRev
    }

    /// @dev Add instrument revenues to a proposal
    /// - CallRes: Indicates progress where `rc` is set from `AddInstRc`
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param req See struct definition
    /// @custom:api public
    function propAddInstRev(uint40 seqNumEx, UUID reqId, PropAddInstRevReq calldata req) external override
    { unchecked {
        address caller = msg.sender;
        // This requires Agent and not RevMgr to reduce RevMgr code size and avoids an arg copy
        _requireOnlyAgent(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        // Cache values
        // slither-disable-next-line uninitialized-local (zero-init is ok)
        PropAddInstRevCtx memory ctx;
        Prop storage prop;
        { // var scope to reduce stack pressure
            PropHdr storage ph;
            (prop, ph) = _getProp(req.pid);
            ctx.pid = ph.pid;
            ctx.ccyAddr = ph.ccyAddr;
            ctx.correction = ph.correction;
        }
        IR.Emap storage book = prop.instRevs;

        // Metaphor: Each page of lines is added to a book of lines
        ICallTracker.CallRes memory result = _reviewUploadInputs(ctx.pid, req.page.length, IR.length(book),
            prop.hdr.uploadedAt, req.iAppend, req.total);

        if (result.rc != uint16(AddInstRc.PartPage)) {
            _setCallRes(caller, seqNumEx, reqId, result);
            return;
        }
        if (!IR.initialized(book)) IR.Emap_init(book);

        ctx.gasLimit = Util.GasCleanupDefault;

        // Copy from memory to storage while gas allows; This is a fast loop with many inputs
        // Ubounds: Condition 1: caller must page, Condition 2: gas available vs limit
        for (; result.count < req.page.length; ++result.count) {
            if (gasleft() < ctx.gasLimit) { result.rc = uint16(AddInstRc.LowGas); break; }

            // Cache values (for gas and bytecode)
            IR.InstRev calldata ir = req.page[result.count]; // Get line to validate and then add to book
            ctx.instNameKey = String.toBytes32(ir.instName);
            // NOTE: More vars would be cached here if not for stack pressure

            // Validate with range and integrity checks
            result.lrc = uint16(_validateInstRev(ir, ctx.instNameKey, book, ctx.correction));
            if (result.lrc != uint16(AddInstLineRc.Ok)) {
                result.rc = uint16(AddInstRc.BadLine);
                break;
            }

            // Validate enough revenue at instrument's deposit address to fund allocations. See LOW_FUNDS.
            // - Given a single deposit address per instrument, the sum of instrument's revenue for all
            //   earn dates in the proposal must be considered to prevent a double spend scenario.
            uint instRevSum = prop.instRevSums[ctx.instNameKey]; // Revenue reserved for inst's other earn dates
            instRevSum += ir.totalRev;                           // Add revenue for an earn date
            uint requiredFunds = instRevSum;
            if (ctx.correction) {
                // Allows for requiring only a correction qty when partial revenue previously transferred
                // If funds availability should not be checked, proposal should set `requiredFunds=0`
                int funds = prop.allocFixes[ctx.instNameKey][ir.earnDate].requiredFunds;
                requiredFunds = funds >= 0 ? uint(funds) : 0;
                // if (funds < 0) then `_fundsAvail` handled in `propAddInstRevAdj`
            }
            if (requiredFunds > 0
                && !_fundsAvail(FundsAvailReq({pid: req.pid, instName: ir.instName, earnDate: ir.earnDate,
                        from: ir.dropAddr, required: requiredFunds, ccyAddr: ctx.ccyAddr })))
            {
                result.rc = uint16(AddInstRc.BadLine);
                result.lrc = uint16(AddInstLineRc.LowFunds);
                break;
            }

            // Now add the 'line to the book'; although, multiple states are updated here

            prop.instRevSums[ctx.instNameKey] = instRevSum;

            // Add InstRev to proposal, ensures unique by key=(instName,earnDate)
            IR.addFromCd(book, ir, ctx.instNameKey, true); // Marks InstRev uploadedAt
            emit InstRevUploaded(req.pid, ir.instName, ir.earnDate, ir.totalQty, ir.totalRev, ir.unitRev,
                ctx.correction);
        }

        // State tracking / feedback
        uint bookLen = IR.length(book);
        if (result.count == req.page.length) {
            if (bookLen < req.total) {
                result.rc = uint16(AddInstRc.FullPage);     // All in current page/call uploaded
            } else {
                result.rc = uint16(AddInstRc.AllPages);     // All uploaded
                prop.hdr.uploadedAt = block.timestamp;      // Mark as uploaded
                emit AllInstRevUploaded(req.pid, bookLen);
            }
        }
        _setCallRes(caller, seqNumEx, reqId, result);
    } }

    /// @dev Add instrument revenue changes/fixes to a proposal - allows revenue per owner to be adjusted
    /// - Each fix will apply a relative adjustment to an owner's balance (+ or -)
    /// - Funds are optionally required from either the dropAddr or vault
    /// - Owner qty is not relevant here as it's handled separately via a RevMgr correction proposal
    /// - CallRes: Indicates progress where `rc` is set from `AddInstRc`
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param req See struct definition - reduces stack pressure
    /// @custom:api public
    function propAddInstRevAdj(uint40 seqNumEx, UUID reqId, AddInstRevAdjReq calldata req) external override
    { unchecked {
        address caller = msg.sender;
        // This requires Agent and not RevMgr to reduce RevMgr code size and avoids an arg copy
        _requireOnlyAgent(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        // Cache values
        (Prop storage prop, PropHdr storage ph) = _getProp(req.pid);
        bytes32 instNameKey = String.toBytes32(req.instName);
        InstAllocFix storage instAllocFix = prop.allocFixes[instNameKey][req.earnDate];
        AllocFix[] storage book = instAllocFix.revFixes;
        uint pageLen = req.page.length;
        uint bookLen = book.length;

        // Metaphor: Each page of lines is added to a book of lines
        ICallTracker.CallRes memory result = _reviewUploadInputs(ph.pid, pageLen, bookLen, instAllocFix.uploadedAt,
            req.iAppend, req.total);

        if (result.rc != uint16(AddInstRc.PartPage)) {
            _setCallRes(caller, seqNumEx, reqId, result);
            return;
        }

        // Validate funds on first line for this book
        if (bookLen == 0) {
            if (req.requiredFunds < 0) {
                // Check funds avail in vault (to send to deposit address)
                uint funds = uint(-req.requiredFunds);
                if (!_fundsAvail(FundsAvailReq({pid: req.pid, instName: req.instName, earnDate: req.earnDate,
                        from: _contracts[CU.Vault], required: funds, ccyAddr: ph.ccyAddr })))
                {
                    result.rc = uint16(AddInstRc.LowFunds);
                    _setCallRes(caller, seqNumEx, reqId, result);
                    return;
                }
            } // else handled in `propAddInstRev`
            instAllocFix.requiredFunds = req.requiredFunds;
        }

        uint gasLimit = Util.GasCleanupDefault;

        // Copy from calldata to storage while gas allows; This is a fast loop with many inputs
        // Ubounds: Condition 1: caller must page, Condition 2: gas available vs limit
        for (; result.count < pageLen; ++result.count) {
            if (gasleft() < gasLimit) { result.rc = uint16(AddInstRc.LowGas); break; }

            // Validate line
            IInstRevMgr.AllocFix calldata line = req.page[result.count];
            if (isEmpty(line.ownerEid) || line.revenue == 0) { result.rc = uint16(AddInstRc.BadLine); break; }
            book.push(line);  // Add line to book
        }

        // State tracking / feedback
        ph.fixCount += result.count; // Store progress
        if (result.count > 0) {
            bookLen = book.length;
            if (result.count == pageLen) {
                if (bookLen < req.total) {
                    result.rc = uint16(AddInstRc.FullPage);     // All in current page/call uploaded
                } else {
                    result.rc = uint16(AddInstRc.AllPages);     // All uploaded
                    ++ph.fixInstRevCount;                       // Store progress
                    instAllocFix.uploadedAt = block.timestamp;  // Mark as uploaded
                }
            }
            emit InstAllocFixUploaded(req.pid, req.instName, req.earnDate, result.count, bookLen);
        }
        _setCallRes(caller, seqNumEx, reqId, result);
    } }

    /// @dev Validate instrument revenue with range and integrity checks
    /// - May help preview/debug an InstRev before adding to a proposal
    /// @param pid Proposal ID, >0 to query related to a proposal, =0 related to executed state
    /// @param instRev Instrument Revenue to validate
    /// @param correction Whether this relates to a correction
    /// @return rc Return code
    function validateInstRev(uint pid, IR.InstRev calldata instRev, bool correction) external view override
        returns(AddInstLineRc rc)
    {
        bytes32 instNameKey = String.toBytes32(instRev.instName);
        return _validateInstRev(instRev, instNameKey, _getInstRevs(pid), correction);
    }

    /// @dev Validate instrument revenue with range and integrity checks
    function _validateInstRev(IR.InstRev calldata instRev, bytes32 instNameKey,
        IR.Emap storage instRevs, bool correction) internal view returns(AddInstLineRc rc)
    {
        // Range checks
        uint nameLen = bytes(instRev.instName).length;
        if (nameLen == 0 || 32 < nameLen) return AddInstLineRc.InstName;
        if (instRev.totalQty == 0) return AddInstLineRc.TotalQty;
        if (instRev.earnDate == 0) return AddInstLineRc.EarnDate;

        // Integrity check: Get total rev from parts (unitRev x totalQty) and ensure remainder in expected range
        // - Total investor revenue
        uint totalRev = instRev.unitRev * instRev.totalQty;
        if (totalRev > instRev.totalRev) return AddInstLineRc.SubtotalRev;
        uint remainder = instRev.totalRev - totalRev;
        if (remainder > instRev.totalQty) return AddInstLineRc.RevRemain;
        if ((totalRev + remainder) != instRev.totalRev) return AddInstLineRc.TotalRev;

        // Ensure InstRev is not already in proposal
        if (IR.exists(instRevs, instNameKey, instRev.earnDate)) return AddInstLineRc.PropHas2;

        // Ensure InstRev is not already in executed state. If an existing executed item is found, it should
        // ideally be when building a prop. However, this check also runs during execution to prevent overlapping
        // props. This redundancy achieves O(1) in both cases whereas checking all props upfront would be O(N).
        if (!correction && IR.exists(_instRevs, instNameKey, instRev.earnDate)) return AddInstLineRc.Exists;
        // rc = AddInstLineRc.Ok is zero-value, implicitly set
    }

    /// @dev Validate proposal is ready for voting
    /// @param pid Proposal ID
    /// @return ok Whether the state is good
    /// @custom:api private
    function propFinalize(uint pid) external view override returns(bool ok) {
        _requireOnlyRevMgr(msg.sender); // Access control

        // Get proposal header
        (Prop storage prop, PropHdr storage ph) = _getProp(pid);

        if (ph.pid == 0 || ph.uploadedAt == 0 || ph.executedAt > 0) return false;
        if (!ph.correction) return true;

        // Validate the count of InstRev in a proposal matches the number of InstRev fixes
        // A thorough check would ensure keys are 1:1 (eg off-chain), this is more pragmatic to reduce SIZE/complexity
        uint fixInstRevCount = ph.fixInstRevCount;
        ok = fixInstRevCount > 0 && IR.length(prop.instRevs) == fixInstRevCount;
    }

    /// @dev Bundles vars to reduce stack pressure
    /// - Upgradability is not a concern for this ephemeral type
    /// @custom:api private
    struct PropExecInstRevCtx {
        string instName;        /// Cached from InstRev
        bytes32 instNameKey;    /// Cached from InstRev
        uint earnDate;          /// Cached from InstRev
        address dropAddr;       /// Cached from InstRev
        address ccyAddr;        /// Cached from InstRev
        address vault;          /// Cached from _contracts
        bool correction;        /// Cached from PropHdr
        uint requiredFunds;     /// Calculated
        address fundsSrc;       /// Calculated
        address fundsDst;       /// Calculated
    }

    /// @dev Add an instrument to the executed state
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param pid Proposal ID
    /// @param iInstRev Index of the InstRev in the proposal, see ``getInstRevsLen(pid, '', 0)` for an upper bound
    /// @return rc Return code
    /// @custom:api private
    function propExecInstRev(uint pid, uint iInstRev) external override returns(IRevMgr.ExecRevRc rc) {
        _requireOnlyRevMgr(msg.sender); // Access control
        rc = _propExecInstRev(pid, iInstRev);
    }

    /// @dev Helper simplifies caller via early returns
    function _propExecInstRev(uint pid, uint iInstRev) internal returns(IRevMgr.ExecRevRc rc) {
        // Get proposal
        Prop storage prop;
        // slither-disable-next-line uninitialized-local (zero-init is ok)
        PropExecInstRevCtx memory ctx;
        { // var scope to reduce stack pressure
            PropHdr storage ph;
            (prop, ph) = _getProp(pid);
            if (ph.pid == 0) return IRevMgr.ExecRevRc.NoProp;
            if (ph.executedAt > 0) return IRevMgr.ExecRevRc.Done;
            if (ph.uploadedAt == 0) return IRevMgr.ExecRevRc.PropStat;

            ctx.correction = ph.correction;
            ctx.ccyAddr = ph.ccyAddr;
        }

        // Get instrument from proposal
        IR.InstRev storage instRev = IR.getByIndex(prop.instRevs, iInstRev);
        // slither-disable-next-line uninitialized-local (accessing item by index, previously validated)
        ctx.earnDate = instRev.earnDate;
        if (ctx.earnDate == 0) return IRevMgr.ExecRevRc.NoInstRev;
        ctx.instNameKey = instRev.instNameKey;

        if (rc != IRevMgr.ExecRevRc.Progress) return rc;

        // Determine funds required and direction of transfer
        ctx.vault = _contracts[CU.Vault];
        if (ctx.correction) {
            // When funds: >0 source from drop box, <0 source from vault, ==0 no check/transfer
            int funds = prop.allocFixes[ctx.instNameKey][ctx.earnDate].requiredFunds;
            ctx.requiredFunds = uint(funds > 0 ? funds : -funds);
            ctx.fundsSrc = funds < 0 ? ctx.vault : instRev.dropAddr;
            ctx.fundsDst = funds < 0 ? instRev.dropAddr : ctx.vault;
        } else {
            ctx.requiredFunds = instRev.totalRev;
            ctx.fundsSrc = instRev.dropAddr;
            ctx.fundsDst = ctx.vault;
        }

        // Xfer instrument revenue. This funds balance increases
        ctx.instName = instRev.instName;
        if (ctx.requiredFunds > 0 &&
            !( _fundsAvail(FundsAvailReq({pid: pid, instName: ctx.instName, earnDate: ctx.earnDate,
                    from: ctx.fundsSrc, required: ctx.requiredFunds, ccyAddr: ctx.ccyAddr }))
               && _xferFunds(pid, ctx)
            ))
        {
            // Protocol violation, see `_fundsAvail` for more. Recourse: A) resolve issue,  B) `pruneProposal` + retry
            return IRevMgr.ExecRevRc.LowFunds;
        }
        // Add InstRev to executed state, ensures unique by key=(instNameKey,earnDate)
        instRev.executedAt = block.timestamp;    // Mark instrument revenue as fully executed
        IR.addFromStore(_instRevs, instRev, ctx.instNameKey, !ctx.correction); // If correction, this does overwrite

        // rc = IRevMgr.ExecRevRc.Progress; line occurs implicity via zero-value init
    }

    /// @dev Mark proposal as executed
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param pid Proposal ID
    /// @custom:api private
    function propExecuted(uint pid) external override {
        _requireOnlyRevMgr(msg.sender); // Access control

        PropHdr storage ph = _proposals[pid].hdr;
        bool count = ph.pid > 0 && ph.executedAt == 0;
        if (count) ph.executedAt = block.timestamp;
    }

    /// @dev Remove an instrument earn date (InstRev) from a sealed proposal
    /// - This is an escape hatch to help ensure progress in `propExecute`
    /// - Size: ~2.6 KB
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
    /// @return removedRev Revenue removed: `InstRev.totalRev` before removal
    /// @custom:api private
    function pruneProp(uint pid, string calldata instName, uint earnDate) external override
        returns(IRevMgr.PruneRevRc rc, uint removedRev)
    {
        _requireOnlyRevMgr(msg.sender); // Access control

        // Get proposal
        (Prop storage prop, PropHdr storage ph) = _getProp(pid);
        if (ph.pid == 0) return (IRevMgr.PruneRevRc.NoProp, removedRev);
        if (ph.executedAt > 0 || ph.uploadedAt == 0) return (IRevMgr.PruneRevRc.PropStat, removedRev);
        if (IR.length(prop.instRevs) == 1) return (IRevMgr.PruneRevRc.LastInst, removedRev);

        bytes32 instNameKey = String.toBytes32(instName);

        // Get total revenue
        IR.InstRev storage ir = IR.getByKey(prop.instRevs, instNameKey, earnDate);
        removedRev = ir.totalRev;
        if (removedRev == 0) return (IRevMgr.PruneRevRc.NoInst, removedRev);

        // Remove InstRev from proposal
        IR.remove(prop.instRevs, instNameKey, earnDate);
        // rc = IRevMgr.PruneRevRc.Done; line occurs implicity via zero-value init
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

    /// @dev Get count of InstAllocFix items
    /// @param pid Proposal ID
    /// @param instName Instrument name as a string
    /// @param earnDate Earn date
    /// @return InstAllocFix item count
    function getAllocFixesLen(uint pid, string calldata instName, uint earnDate) external view override returns(uint) {
        return getAllocFixesLenByKey(pid, String.toBytes32(instName), earnDate);
    }

    /// @dev Get count of InstAllocFix items (for a contract client)
    /// @param pid Proposal ID
    /// @param instNameKey Instrument name as bytes32
    /// @param earnDate Earn date
    /// @return InstAllocFix item count
    function getAllocFixesLenByKey(uint pid, bytes32 instNameKey, uint earnDate) public view override returns(uint) {
        return _proposals[pid].allocFixes[instNameKey][earnDate].revFixes.length;
    }

    /// @dev Get InstAllocFix fields
    /// @param pid Proposal ID
    /// @param instName Instrument name as a string
    /// @param earnDate Earn date
    /// @return revenue Owner's revenue adjustment
    /// @return ownerEid Owner's external id
    function getAllocFix(uint pid, string calldata instName, uint earnDate, uint iAllocFix) external view override
        returns(int revenue, UUID ownerEid)
    {
        return getAllocFixByKey(pid, String.toBytes32(instName), earnDate, iAllocFix);
    }

    /// @dev Get InstAllocFix fields (for a contract client)
    /// @param pid Proposal ID
    /// @param instNameKey Instrument name as bytes32
    /// @param earnDate Earn date
    /// @return revenue Owner's revenue adjustment
    /// @return ownerEid Owner's external id
    function getAllocFixByKey(uint pid, bytes32 instNameKey, uint earnDate, uint iAllocFix) public view override
        returns(int revenue, UUID ownerEid)
    {
        AllocFix[] storage revFixes = _proposals[pid].allocFixes[instNameKey][earnDate].revFixes;
        if (revFixes.length > 0 && iAllocFix < revFixes.length) {
            AllocFix storage fix = revFixes[iAllocFix];
            revenue = fix.revenue;
            ownerEid = fix.ownerEid;
        }
    }

    // ───────────────────────────────────────
    // Getters: Instrument Revenue (Proposal or Executed)
    // ───────────────────────────────────────

    function _getInstRevs(uint pid) private view returns(IR.Emap storage) {
        return pid == 0 ? _instRevs : _proposals[pid].instRevs;
    }

    /// @dev Get count of instrument's revenue
    /// - Scope of the count is conditioned on the filter of params
    /// @param pid Proposal ID, >0 to query a proposal, =0 to query executed state
    /// @param instName Instrument name to filter or empty to get all
    /// @param earnDate Earn date to filter or 0 to get all
    function getInstRevsLen(uint pid, string calldata instName, uint earnDate) external view override returns(uint) {
        bytes32 instNameKey = String.toBytes32(instName);
        return IR.getInstRevsLen(_getInstRevs(pid), instNameKey, earnDate);
    }

    /// @dev Get instrument revenues
    /// - Scope of the results is conditioned on the filter of params: `pid`, `instName`, `earnDate`
    /// - Caller must page outputs to avoid gas issues, see PAGE_REQUESTS
    /// @param pid Proposal ID, >0 to query a proposal, 0 to query executed state
    /// @param instName An instrument name to filter or empty to get all
    /// @param earnDate An earn date to filter or 0 to get all
    /// @param iBegin Index in the array to begin processing
    /// @param count Items to get, 0 = [iBegin:] (may exceed gas), May call `getInstRevsLen` with same inputs
    /// @return results requested range of items
    function getInstRevs(uint pid, string calldata instName, uint earnDate, uint iBegin, uint count)
        external view override returns(IR.InstRev[] memory results)
    {
        bytes32 instNameKey = String.toBytes32(instName);
        return IR.getInstRevs(_getInstRevs(pid), instNameKey, earnDate, iBegin, count);
    }

    /// @dev Get instrument revenue, empty if not found
    /// @param pid Proposal ID, >0 to query a proposal, 0 to query executed state
    /// @param iInst InstRev index
    /// @return instRev The requested instrument revenue
    function getInstRev(uint pid, uint iInst) external view override
        returns(IR.InstRev memory instRev)
    {
        return IR.getByIndex(_getInstRevs(pid), iInst);
    }

    /// @dev Get instrument revenue, empty if not found
    /// @param pid Proposal ID, >0 to query a proposal, 0 to query executed state
    /// @param instName An instrument name to find (required)
    /// @param earnDate An earn date to find (required)
    /// @return instRev The requested instrument revenue
    function getInstRevForInstDate(uint pid, string calldata instName, uint earnDate) external view override
        returns(IR.InstRev memory instRev)
    {
        bytes32 instNameKey = String.toBytes32(instName);
        return IR.getByKey(_getInstRevs(pid), instNameKey, earnDate);
    }

    /// @dev Input to `_fundsAvail`
    /// - Bundles vars to reduce stack pressure
    /// - Upgradability is not a concern for this ephemeral type
    /// @custom:api private
    struct FundsAvailReq {
        uint pid;           /// Proposal ID
        string instName;    /// Instrument name for approval/logging
        uint earnDate;      /// Earn date for logging
        address from;       /// Xfer source address; source of funds
        uint required;      /// Qty required
        address ccyAddr;    /// Currency token address
    }

    /// @dev Check if funds are available at a deposit address.
    // - LOW_FUNDS: This could happen in 2 cases:
    //     1) Prop creation: Due to external processes/people, ideally resolved upstream proactively
    //     2) Prop execution: Due to a protocol violation - should not happen. See REV_FLOW_PROTOCOL
    /// @param req See struct definition
    /// @return ok Whether there are sufficient funds
    function _fundsAvail(FundsAvailReq memory req) private returns(bool ok) {
        // Get balance at funds source address
        uint srcBalance = IERC20(req.ccyAddr).balanceOf(req.from);
        if (srcBalance >= req.required) {
            // Get contract's allowance to transfer funds
            ok = req.required <= IERC20(req.ccyAddr).allowance(req.from, address(this));
        }
        if (!ok) emit LowFundsErr(req.pid, req.instName, req.earnDate,
            req.ccyAddr, req.from, srcBalance, req.required);
        // Could conditionally call `vault.approveMgr` or `box.approve` here but that should happen upstream (eg setup)
    }

    // slither-disable-start arbitrary-send-eth (Intentionally generic and caller has access control)
    // slither-disable-start arbitrary-send-erc20 (See previous comment)

    /// @dev Move funds between addresses and emit an event; source balance checked upstream
    /// @param pid Proposal ID
    /// @param ctx Reduces stack pressure
    /// @return ok Whether the action was successful
    function _xferFunds(uint pid, PropExecInstRevCtx memory ctx) private returns(bool ok) {
        // Move funds, this should not fail since balance and allowance checked upstream
        // - Non-standard tokens that do not return a boolean are not supported, expecting well-behaved like USDC
        try IERC20(ctx.ccyAddr).transferFrom(ctx.fundsSrc, ctx.fundsDst, ctx.requiredFunds) returns(bool success) {
            ok = success;
        } catch {}
        emit RevenueXfer(pid, ctx.instName, ctx.earnDate, ok, ctx.correction,
            ctx.ccyAddr, ctx.fundsSrc, ctx.fundsDst, ctx.requiredFunds);
    }

    // slither-disable-end arbitrary-send-eth
    // slither-disable-end arbitrary-send-erc20
}
