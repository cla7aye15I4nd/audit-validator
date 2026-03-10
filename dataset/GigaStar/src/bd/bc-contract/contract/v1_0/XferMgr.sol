// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './ContractUser.sol';
import './IBalanceMgr.sol';
import './IBox.sol';
import './IVault.sol';
import './IXferMgr.sol';
import './LibraryAC.sol';
import './LibraryCU.sol';
import './LibraryTI.sol';
import './LibraryUtil.sol';
import './Types.sol';

/// @title XferMgr: Token transfer manager
/// @author Jason Aubrey, GigaStar
/// @notice Provides functionality related to a transfer proposal
/// @dev Insulates Vault from bytecode size
/// - Upgradeable via UUPS. See PROXY_OPTIONS for more.
/// @custom:api public
/// @custom:deploy uups
// prettier-ignore
contract XferMgr is Initializable, UUPSUpgradeable, IXferMgr, ContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint constant VERSION = 10; // 123 => Major: 12, Minor: 3 (always 1 digit)

    // ────────────────────────────────────────────────────────────────────────────
    // Fields (See MEM_LAYOUT), default visibility is 'internal'
    // ────────────────────────────────────────────────────────────────────────────
    mapping(address => bool) _tokenAdmin;   // Keys: token address; Tracks which tokens allow a mint/burn
    mapping(uint => Prop) _proposals;       // Key: pid; A request linked to a token transfer proposal

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

    /// @notice Update the list of tokens where transfers may mint/burn to prevent accidental value destruction
    /// - Tokens on this list are allowed to have xfers to/from AddrZero, else such transfers may fail pre-send
    /// - Useful for an internal token where mints/burns are routine/reversible but external tokens would destroy value
    /// @dev Call behaves as add and remove (tokAddr=0)
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param tokAddr The token to add/remove from list
    /// @param add true: Add to list; false: Remove from list
    /// @custom:api public
    function updateTokenAdminList(uint40 seqNumEx, UUID reqId, address tokAddr, bool add) external override {
        _requireVaultOrAdminOrCreator(msg.sender); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(msg.sender, seqNumEx, reqId)) return;

        bool ok = false;
        if (tokAddr != AddrZero) {
            if (_tokenAdmin[tokAddr] != add) {
                _tokenAdmin[tokAddr] = add;
                emit TokenAdminListUpdated(tokAddr, add);
            }
            ok = true;
        }

        _setCallRes(msg.sender, seqNumEx, reqId, ok);
    }

    // ───────────────────────────────────────
    // Operations: Xfer Proposal
    // ───────────────────────────────────────

    /// @dev Add a transfer proposal, this creates a stub that must be populated by additional calls
    /// - Inputs validated upstream
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param pid Proposal ID, always increases
    /// @param reqId Request ID
    /// @param ti TokenInfo, see struct definition; ERC-1155 transfers use the token id from the `Xfer` items in prop
    /// @param isRevDist Whether this transfer is a revenue distribution (relates to balance tracking)
    /// @custom:api private
    function propCreate(uint pid, UUID reqId, TI.TokenInfo memory ti, bool isRevDist) external override {
        _requireOnlyVault(msg.sender); // Access control

        PropHdr storage prop = _proposals[pid].hdr;
        prop.pid = pid;
        prop.eid = reqId;
        prop.isRevDist = isRevDist;
        prop.ti = ti;
        // prop.xfers = new Xfer[](0); See `propAddXfers`
    }

    /// @dev Bundles vars to reduce stack pressure
    /// - Upgradability is not a concern for this ephemeral type
    /// @custom:api private
    struct PropAddXfersCtx {
        uint bookLen;               // Cached from Xfer[]
        IBalanceMgr balanceMgr;     // Cached from _contracts
        address vaultAddr;          // Cached from _contracts
        bool resolveAddrs;          // Calculated
        bool isNative;              // Calculated
        bool allowMintBurn;         // Calculated
        uint gasLimit;              // Calculated
    }

    /// @dev Helper simplifies caller via early returns
    function _makeCr(address caller, uint40 seqNumEx, UUID reqId, AddXferRc rc) private {
        // slither-disable-next-line uninitialized-local (zero-init is ok)
        ICallTracker.CallRes memory cr;
        cr.rc = uint16(rc);
        _setCallRes(caller, seqNumEx, reqId, cr);
    }

    /// @notice Append transfers to a pending proposal (created by `createXferProp`), idempotency
    /// is provided via correct client processing of function i/o. Comments and i/o are verbose to ensure accuracy.
    /// @dev Naming uses a metaphor where each upload has a page of lines (transfers) added to a book of lines.
    /// - CallRes: Indicates progress where `rc` is set from `AddXferRc`
    /// - Success: See `code`, may emit `XfersUploaded` or `PropSealed`
    /// - Access by role: Agent
    /// - Xfers with insufficient funds will fail
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param req See struct definition, additional comments:
    /// - `req.iAppend` May return `BadIndex` in cases such as the client passing a bad `iAppend` because:
    ///     - The status of call was mishandled and a retry (duplicate call) had no effect (to prevent duplicates)
    ///     - Client incorrectly assumed a previous call completed with `code` = `FullPage`
    /// - `req.total` Allows proposal to be sealed when all pages in an upload are complete.
    /// - `req.page`:  If calling again with transfers not handled in a previous call, be sure to remove those
    //        handled from the input or they will be considered new input as transfers do not have an id/index.
    /// @custom:api public
    function propAddXfers(uint40 seqNumEx, UUID reqId, PropAddXfersReq calldata req) external override
    { unchecked {
        address caller = msg.sender;
        _requireOnlyAgent(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        // Get proposal
        Prop storage prop = _proposals[req.pid];
        PropHdr memory ph = prop.hdr; // Most fields are used and 'memory' reduces stack pressure
        if (ph.pid == 0) { _makeCr(caller, seqNumEx, reqId, AddXferRc.NoProp); return; }
        if (ph.uploadedAt > 0) { _makeCr(caller, seqNumEx, reqId, AddXferRc.ReadOnly); return; }

        // Cache values
        Xfer[] storage book = prop.xfers; // Storage ptr cannot be part of a struct (ctx)
        // slither-disable-next-line uninitialized-local (zero-init is ok)
        PropAddXfersCtx memory ctx;
        ctx.bookLen = book.length; // Metaphor: Each page of lines is added to a book of lines
        ctx.balanceMgr = IBalanceMgr(_contracts[CU.BalanceMgr]);
        ctx.vaultAddr = _contracts[CU.Vault];
        ctx.resolveAddrs = ph.ti.tokType != TI.TokenType.Erc1155Crt;
        ctx.isNative = ph.ti.tokType == TI.TokenType.NativeCoin;
        ctx.allowMintBurn = !ph.isRevDist
            && (ph.ti.tokType == TI.TokenType.Erc1155Crt || _tokenAdmin[ph.ti.tokAddr]);
        ctx.gasLimit = Util.GasCleanupDefault;

        // Review inputs for paging
        if (req.page.length == 0) { _makeCr(caller, seqNumEx, reqId, AddXferRc.BadPage); return; }
        if (req.iAppend != ctx.bookLen) { _makeCr(caller, seqNumEx, reqId, AddXferRc.BadIndex); return; }
        if (ctx.bookLen + req.page.length > req.total) { _makeCr(caller, seqNumEx, reqId, AddXferRc.BadTotal); return; }

        // slither-disable-next-line uninitialized-local (zero-init is ok)
        ICallTracker.CallRes memory result;
        // Copy from calldata to storage while gas allows; This is a fast loop with many inputs
        // Ubounds: Condition 1: caller must page, Condition 2: gas available vs limit
        for (; result.count < req.page.length; ++result.count) {
            if (gasleft() < ctx.gasLimit) { result.rc = uint16(AddXferRc.LowGas); break; }

            // Validate each transfer (page line)
            Xfer calldata line = req.page[result.count];
            result.lrc = uint16(_xferFieldsCheck(line, ctx.isNative, ctx.allowMintBurn));
            if (result.lrc != uint16(AddXferLrc.Ok)) {
                result.rc = uint16(AddXferRc.BadLine);
                break;
            }
            if (ph.isRevDist) {
                if (!_xferIsFunded(ctx.balanceMgr, ph.ti.tokAddr, line, prop.srcSimBals[line.fromEid])) {
                    // This is a protocol violation, but if it happens then better to stop here and resolve the
                    // issue or create a proposal to amend this one via `propPruneXfers`
                    result.rc = uint16(AddXferRc.BadLine);
                    result.lrc = uint16(AddXferLrc.LowFunds); // Should only happen via protocol violation
                    break;
                }
            } // else no validation occurs when not a revenue distribution as less critical
            // Validated, now "write line to book"

            // Add transfer to storage
            // - `status` is gas-optimized here by setting the expected post-execution happy-path value to avoid
            //   storage writes during transfer, masked externally as explained by XFER_NOT_EXEC. Value is not
            //   actually valid until post-execution, also explained in enum declaration
            book.push(Xfer({
                eid: line.eid,
                from: ctx.resolveAddrs ? Util.resolveAddr(line.from, ctx.vaultAddr) : line.from,
                to: ctx.resolveAddrs ? Util.resolveAddr(line.to, ctx.vaultAddr) : line.to,
                tokenId: line.tokenId,
                status: IXferMgr.XferStatus.Sent, // Optimization: See `status` comment above or SEND_HOT_PATH below
                qty: line.qty,
                fromEid: line.fromEid,
                toEid: line.toEid
            }));
        }
        if (result.count > 0) {
            // This event per page provides efficient state tracking, defering optional details to read calls
            // - To get details, forward event params to `getXferLites(pid, iBegin, count)`
            emit XfersUploaded(ph.pid, ph.eid, req.iAppend, result.count);

            ctx.bookLen = book.length;
            if (result.count == req.page.length) {
                if (ctx.bookLen < req.total) {
                    result.rc = uint16(AddXferRc.FullPage); // All xfers in current page
                } else {
                    result.rc = uint16(AddXferRc.AllPages); // All xfers
                    prop.hdr.uploadedAt = block.timestamp;  // Mark as upload complete
                }
            }
        }
        _setCallRes(caller, seqNumEx, reqId, result);
    } }

    /// @dev Basic transfer input validation
    function _xferFieldsCheck(Xfer calldata x, bool isNative, bool allowMintBurn) internal pure
        returns(AddXferLrc lrc)
    {
        if (isEmpty(x.eid)) return AddXferLrc.BadEid; // No check on 'fromEid' or 'toEid' as 0 on mint/burn
        if (x.qty == 0 || x.qty > uint(type(int).max)) return AddXferLrc.BadQty;
        if (x.from == x.to) return AddXferLrc.SelfXfer;
        if (isNative && x.from != Util.ContractHeld) return AddXferLrc.NativeSrc;

        // A standards compliant ERC20 tokens does not allow a transfer to/from the mint/burn address but the Crt
        // allows this via sentinel addresses to reduce the flow (mint/xfer/burn) => transfer
        if (x.from == Util.NativeMint || x.to == Util.NativeBurn) return AddXferLrc.NativeAddr; // Use Util.Explicit*
        if (!allowMintBurn && (x.from == Util.ExplicitMint || x.to == Util.ExplicitBurn)) return AddXferLrc.MintBurn;
        // AddXferLrc.Ok is zero value
    }

    /// @dev Simulate balance transfer to check for underflow on source balance
    /// - Transfer are assumed to be a DAG (no cycles) (eg vault to externals) since only source funds are checked
    /// - State only updated if no underflow
    /// @param balanceMgr Balance manager with current balances
    /// @param tokAddr Token to transfer
    /// @param xfer Transfer to check
    /// @param srcSimBal Transfer source simulated balance (running sum of current balance + transfers)
    /// @return valid Whether the transfer appears valid
    function _xferIsFunded(IBalanceMgr balanceMgr, address tokAddr, Xfer calldata xfer, SimBal storage srcSimBal)
        internal returns(bool valid)
    {
        int balance;
        int xferQty = int(xfer.qty);
        if (srcSimBal.seen) { // then compare to simulated balance
            balance = srcSimBal.balance;
            if (xferQty > balance) return false; // Underflow
        } else { // then first simulated transfer for account
            balance = balanceMgr.getOwnerBalance(tokAddr, xfer.fromEid);
            if (xferQty > balance) return false; // Underflow
            srcSimBal.seen = true; // Only set after validation for the first in the sequence
        }
        srcSimBal.balance = balance - int(xfer.qty);
        valid = true; // Balance sufficient for transfer
    }

    /// @dev Reviews progress of `propAddXfers` and marks request as fully uploaded
    /// @param pid Proposal ID
    /// @return rc Indicates progress:
    /// - Ok       : Proposal upload complete
    /// - NoProp   : No proposal found by pid
    /// - BadTotal : Total qty in header differs from the sum of transfers
    /// @custom:api private
    function propFinalize(uint pid) external view override returns(PropXferFinalRc rc) {
        _requireOnlyVault(msg.sender); // Access control

        // Get proposal
        PropHdr storage ph = _proposals[pid].hdr;
        if (ph.pid == 0) return PropXferFinalRc.NoProp;
        if (ph.uploadedAt == 0) return PropXferFinalRc.PropStat;

        // rc = PropXferFinalRc.Ok is zero-value, implicitly set
    }

    /// @dev Helper simplifies caller via early returns
    function _makeCr(ExecXferRc rc) private pure returns(CallRes memory cr) {
        cr.rc = uint16(rc);
    }

    /// @dev Bundles vars to reduce stack pressure
    /// - Upgradability is not a concern for this ephemeral type
    /// @custom:api private
    struct PropExecuteCtx {
        address tokAddr;            // Cached from PropHdr
        uint xfersLen;              // Cached from Proposal
        uint iXfer;                 // Calculated
        uint gasLimit;              // Calculated
    }

    /// @notice Execute an approved transfer proposal
    /// @dev Should be called until no pages remain, each call runs until work is complete or gas limit.
    /// - This is a hot path for gas usage, more focus given to gas
    /// - The execution cursor is internal and therefore safe for excessive calls
    /// - Xfers with insufficient funds will fail but this should not happen as checked in proposal creation
    /// - See ACCOUNT_ACCESS_LIST, MALICIOUS_TRANSFERS, and TRANSFER_FAILURE
    /// - Success: emits XfersProcessed, conditionally PropExecuted,
    /// - Success progress: Check progress via returns and/or `getXferExecIndex`
    /// - Access by role: Agent
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param pid Proposal ID, identifies an existing transfer proposal
    /// @return result Indicates progress where `rc` is set from `ExecXferRc`
    /// @custom:api private
    function propExecute(uint pid) external override
        returns(CallRes memory result) // Return value used by Vault
    {
        address caller = msg.sender;
        _requireOnlyVault(caller); // Access control

        // Get proposal to begin/resume execution
        Prop storage prop = _proposals[pid];
        PropHdr storage ph = prop.hdr;
        if (ph.pid == 0) return _makeCr(ExecXferRc.NoProp);
        if (ph.uploadedAt == 0) return _makeCr(ExecXferRc.PropStat);
        if (ph.executedAt > 0) return _makeCr(ExecXferRc.Done);

        // Cache state before looping
        // slither-disable-next-line uninitialized-local (zero-init is ok)
        PropExecuteCtx memory ctx;
        ctx.tokAddr = ph.ti.tokAddr;
        ctx.xfersLen = prop.xfers.length;
        ctx.iXfer = ph.iXfer;
        ctx.gasLimit = Util.GasCleanupDefault;

        // Process transfers
        uint iExec = 0;
        uint fails = 0;
        if (ph.ti.tokType == TI.TokenType.Erc20 || ph.ti.tokType == TI.TokenType.NativeCoin) {
            (iExec, fails) = _xferLoopRev(prop, ctx);
        } else { // values constrained upstream so must be Erc1155 or Erc1155Crt
            (iExec, fails) = _xferLoopErc1155(prop.xfers, ctx.tokAddr, ctx.iXfer, ctx.xfersLen, ctx.gasLimit);
        }
        result.lrc = uint16(fails); // Failed transfers

        // State tracking / feedback
        ph.iXfer = iExec;                           // Store progress
        result.count = uint16(iExec - ctx.iXfer);   // Transfers handled in this function
        if (result.count > 0 || fails > 0) {
            // This event per page provides efficient state tracking, defering optional details to read calls
            // - To get details, forward event params to `getXferLites(pid, iBegin, count)`
            emit XfersProcessed(pid, ph.eid, ctx.iXfer, result.count, fails, ph.ti.tokSym);
        }
        if (iExec >= ctx.xfersLen) {
            ph.executedAt = block.timestamp; // Mark proposal as executed
            result.rc = uint16(ExecXferRc.Done);
        }
    }

    // slither-disable-start arbitrary-send-eth (Send is parameterized and caller is access controlled)
    // slither-disable-start arbitrary-send-erc20 (See previous comment)

    /// @dev Process xfers until complete or gasLimit, transfer details delegated based on input
    /// - Success: emits dependent on `tokAddr`, none emitted here to reduce gas, caller emits for batch
    /// - Success progress: Check progress via returns and/or `getXferExecIndex`
    /// - Failure effects are conditional: check returns. See MALICIOUS_TRANSFERS, and TRANSFER_FAILURE
    /// @dev This is a hot path for gas usage, more focus given to gas but it still focuses on size, etc
    /// @param prop Xfer proposal
    /// @param ctx Context to reduce stack pressure (vs passing discrete vars)
    /// @return iExec Next xfer index (`iBegin`), also count of total transfers handled in proposal
    /// @return fails Failed transfers in this call, these should not happen
    function _xferLoopRev(Prop storage prop, PropExecuteCtx memory ctx) private returns(uint iExec, uint fails)
    { unchecked {
        // Cache state before looping
        Xfer[] storage xfers = prop.xfers;
        bool isRevDist = prop.hdr.isRevDist;
        IBalanceMgr balanceMgr = IBalanceMgr(isRevDist ? _contracts[CU.BalanceMgr] : AddrZero);
        bool isErc20 = ctx.tokAddr != AddrZero;
        IERC20 token = IERC20(isErc20 ? ctx.tokAddr : AddrZero);
        IVault vault = IVault(isErc20 ? AddrZero : _contracts[CU.Vault]);

        // Ubounds: Condition 1: caller must page, Condition 2: gas available vs limit
        uint skips = 0;
        for (iExec = ctx.iXfer; iExec < ctx.xfersLen && gasleft() > ctx.gasLimit; ++iExec) {
            Xfer storage t = xfers[iExec];
            if (t.status == XferStatus.Skipped) { ++skips; continue; } // cold path: transfer pruned

            // Conditionally check owner's balance
            uint qty = t.qty;
            if (isRevDist && !balanceMgr.claimQty(ctx.tokAddr, t.fromEid, qty)) {
                t.status = XferStatus.Failed;
                ++fails;
                // An event is not necessary but simplifies debugging vs parsing the Xfer array
                emit XferErr(t.from, t.to, qty, true, isErc20);
                continue; // cold path: error
            }

            // SEND_HOT_PATH: GAS: Block content optimized away for tight-loop performance
            // - `t.status` is initialized pre-execution to `XferStatus.Sent` to skip storage writes here
            // - `sent` count is calculated post-loop
            if (isErc20) {
                // Non-standard tokens that do not return a boolean are not supported, expecting well-behaved like USDC
                try token.transferFrom(t.from, t.to, qty) returns(bool success) {
                    if (success) continue; // hot path
                } catch {}
            } else { // Native coin
                if (vault.xferNative(t.to, t.qty)) continue; // hot path
            }

            // Xfer failed, refund owner balance, See TRANSFER_FAILURE
            // A 2-step claim/unclaim avoids reverting the tx on failure as would be required in 1 claim post-transfer
            if (isRevDist) balanceMgr.unclaimQty(ctx.tokAddr, t.fromEid, qty);
            t.status = XferStatus.Failed;
            ++fails;

            // An event is not necessary but simplifies debugging vs parsing the Xfer array
            emit XferErr(t.from, t.to, qty, false, isErc20);
        }
        // sent = iExec - ctx.iXfer - skips - fails; // Could be calculated post-loop as an optimization
    } }

    /// @dev Process xfers until complete or gasLimit, transfer details delegated based on input
    /// - Success: emits are dependent on the token contract used, none emitted here to reduce gas
    /// - Success progress: Check progress via returns and/or `getXferExecIndex`
    /// - Failure effects are conditional: check returns. See MALICIOUS_TRANSFERS, and TRANSFER_FAILURE
    /// @param xfers ERC-1155 transfers
    /// @param tokAddr Token address, the asset to transfer
    /// @param iBegin Starting index/offset to process in transfers array
    /// @param xfersLen Total transfers in the proposal, passed after prior load to save gas
    /// @param gasLimit The target max gas to use in this call.
    /// @return iExec Next xfer index (`iBegin`), also count of total transfers handled in proposal
    /// @return fails Failed transfers in this call, these should not happen
    function _xferLoopErc1155(Xfer[] storage xfers, address tokAddr, uint iBegin, uint xfersLen, uint gasLimit) private
        returns(uint iExec, uint fails)
    { unchecked {
        // Ubounds: Condition 1: caller must page, Condition 2: gas available vs limit
        uint skips = 0;
        IERC1155 token = IERC1155(tokAddr);
        for (iExec = iBegin; iExec < xfersLen && gasleft() > gasLimit; ++iExec) {
            Xfer storage t = xfers[iExec];
            if (t.status == XferStatus.Skipped) { ++skips; continue; } // cold path: transfer pruned

            try token.safeTransferFrom(t.from, t.to, t.tokenId, t.qty, '') {
                // See SEND_HOT_PATH
            } catch { // cold path: error, See TRANSFER_FAILURE
                t.status = XferStatus.Failed;
                ++fails;
            }
        }
        // sent = iExec - iBegin - skips - fails; // Could be calculated post-loop as an optimization
    } }

    // slither-disable-end arbitrary-send-eth
    // slither-disable-end arbitrary-send-erc20

    /// @notice Used to skip transfers in an approved proposal that have failed, this is a defensive escape hatch
    /// where skipped transfers can be resolved in future proposals to ensure progress for the current proposal.
    /// - Ensure skipped transfers cascade skips to dependent transfers if relevant (eg A => B, B => C)
    /// Most likely use cases would be either:
    /// - A token that runs destination contract code on a malicious wallet (USDC does not), See MALICIOUS_TRANSFERS
    /// - Insufficient funds/access to transfer
    /// Such cases should be avoidable/resolvable in other ways but this is a backup/fail-safe mechanism to ensure
    /// progress in a proposal rather than abort mid-batch due to a small problem subset.
    /// - Success: emits XfersPruned
    /// - Success progress: Check progress via returns and/or `getXfers`
    /// - Failure effects are conditional: Check returns.
    /// - Access by role: Agent (Can deny a transfer here but not redirect it)
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param skips Xfer indexes to be skipped during `propExecute`
    /// @custom:api public
    function propPruneXfers(uint40 seqNumEx, UUID reqId, uint pid, uint[] calldata skips) external override
    {
        address caller = msg.sender;
        _requireOnlyAgent(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        uint count;
        bool badIndex;
        (count, badIndex) = _propPruneXfers(pid, skips);

        _setCallRes(caller, seqNumEx, reqId, count > 0 ? 1 : 0, badIndex ? 1 : 0, uint16(count));
    }

    /// @dev Helper simplifies caller via early returns
    function _propPruneXfers(uint pid, uint[] calldata skips) internal
        returns(uint count, bool badIndex)
    { unchecked {
        // Get proposal
        Prop storage prop = _proposals[pid];
        PropHdr storage ph = prop.hdr;
        if (pid == 0 || ph.uploadedAt == 0 || ph.executedAt > 0) return (count, badIndex);

        // Cache vars before loop
        Xfer[] storage xfers = prop.xfers;
        uint xfersLen = xfers.length;
        uint skipsLen = skips.length;
        if (skipsLen == 0) return (count, badIndex);
        uint iXfer = ph.iXfer; // Execution cursor
        uint pruned = 0;       // Separate from `count` to handle possibly duplicate `iSkip` values

        // Mark transfers to be skipped
        uint gasLimit = Util.GasCleanupDefault;
        // Ubounds: Condition 1: caller must page, Condition 2: gas available vs limit
        for (; count < skipsLen && gasleft() > gasLimit; ++count) {
            uint iSkip = skips[count];
            if (iSkip < iXfer || iSkip >= xfersLen) { // if `iSkip` is out-of-range: [execution cursor, last index]
                // Invalid index: Caller must fix the index at skips[count].
                badIndex = true;
                break;
            }
            if (xfers[iSkip].status != XferStatus.Skipped) { // Ignore duplicate `iSkip` values (already processed)
                xfers[iSkip].status = XferStatus.Skipped;
                ++pruned;
            }
        }
        if (pruned > 0) {
            emit XfersPruned(pid, ph.eid, pruned); // Indicates actually pruned count for this page (no duplicates)
        }
        // returned `count` reflects processed items (including possible duplicates)
    } }

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────

    /// @dev Complements `updateTokenAdminList`, see return value
    /// @param tokAddr The token to add/remove from list
    /// @return Whether the token is in the admin list
    function inTokenAdminList(address tokAddr) external view override returns(bool) {
        return _tokenAdmin[tokAddr];
    }

    /// @notice Feature is orthogonal to the contract but convenient for now
    /// Get each account token balance directly from the token contract.
    /// - NOT AN ACCOUNT VAULT BALANCE
    /// - Provides batch behavior not available directly on tokens to coalesce many txs into 1
    /// - ERC-1155 not supported to save size as those tokens supports it directly via `IERC1155.balanceOfBatch`
    /// @param tokAddr Token address
    /// @param tokType Controls how to query the token
    /// @param accounts Accounts to check
    /// @return balances Token balance per account, 0 if unsupported token
    function getTokenBalances(address tokAddr, TI.TokenType tokType, address[] calldata accounts)
        external view override returns(uint[] memory balances)
    { unchecked {
        uint accountsLen = accounts.length;
        balances = new uint[](accountsLen);
        if (tokType == TI.TokenType.Erc20) {
            for (uint i = 0; i < accountsLen; ++i) { // Ubound: Caller must page
                balances[i] = IERC20(tokAddr).balanceOf(accounts[i]);
            }
        } else if (tokType == TI.TokenType.NativeCoin) {
            for (uint i = 0; i < accountsLen; ++i) { // Ubound: Caller must page
                balances[i] = accounts[i].balance;
            }
        }
    } }

    /// @notice Get xfer proposal info excluding the xfers, call `getXfers` for all transfers
    /// @param pid Proposal ID, identifies an existing proposal
    function getPropHdr(uint pid) external view override returns(PropHdr memory info) {
        return _proposals[pid].hdr;
    }

    /// @notice Get a proposal's next transfer index to be executed, a lightweight alternative to `getProp`
    /// @param pid Proposal ID, identifies an existing transfer proposal
    function getXferExecIndex(uint pid) external view override returns(uint) {
        return _proposals[pid].hdr.iXfer;
    }

    /// @notice Get the count of uploaded transfers - also the insertion index for the next upload
    /// @param pid Proposal ID, identifies an existing transfer proposal
    function getXfersLen(uint pid) external view override returns(uint) {
        return _proposals[pid].xfers.length;
    }

    /// @notice Get a range of detailed transfers
    /// @param pid Proposal ID, identifies an existing transfer proposal
    /// @param iBegin Index in the array to start processing
    /// @param count Items to get, 0 = [iBegin:] (may exceed gas), See `getXfersLen` and PAGE_REQUESTS.
    /// @return results requested range of items
    function getXfers(uint pid, uint iBegin, uint count) external view override returns(Xfer[] memory results)
    { unchecked {
        Prop storage prop = _proposals[pid];
        Xfer[] storage xfers = prop.xfers;

        // Calculate results length
        uint resultsLen = Util.getRangeLen(xfers.length, iBegin, count);
        if (resultsLen == 0) return results;

        // Get next index to be transferred
        uint iXfer = prop.hdr.iXfer;

        // Get results slice
        results = new Xfer[](resultsLen);
        uint k = iBegin;
        for (uint i = 0; i < resultsLen; ++i) { // Ubound: Caller must page
            results[i] = xfers[k];
            if (k >= iXfer && results[i].status == XferStatus.Sent) { // `status` check allows non-exec status `Skipped`
                // XFER_NOT_EXEC: `.status` is only valid after the transfer is executed as value is pre-set to `Sent`
                // for no storage writes during exec on happy-path, translated here for intuitive external behavior
                // as this is both outside the critical path and write costs are inconsequential here via `view`
                results[i].status = XferStatus.Pending;
            }
            ++k;
        }
    } }

    /// @notice Get a range of lightweight transfers
    /// @param pid Proposal ID, identifies an existing transfer proposal
    /// @param iBegin Index in the array to start processing
    /// @param count Items to get, 0 = [iBegin:] (may exceed gas), See `getXfersLen` and PAGE_REQUESTS.
    /// @return results requested range of items
    function getXferLites(uint pid, uint iBegin, uint count) external view override returns(XferLite[] memory results)
    { unchecked {
        Prop storage prop = _proposals[pid];
        Xfer[] storage xfers = prop.xfers;

        // Calculate results length
        uint resultsLen = Util.getRangeLen(xfers.length, iBegin, count);

        // Get next index to be transferred
        uint iXfer = prop.hdr.iXfer;

        // Get results slice (both by fields and length)
        results = new XferLite[](resultsLen);
        uint k = iBegin;
        for (uint i = 0; i < resultsLen; ++i) { // Ubound: Caller must page
            Xfer storage x = xfers[k];
            results[i] = XferLite({
                eid: x.eid,
                status: k >= iXfer && x.status == XferStatus.Sent ? XferStatus.Pending : x.status // See XFER_NOT_EXEC
            });
            ++k;
        }
    } }
}
