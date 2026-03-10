# Batch Reentrancy Double-Spend via Optimistic State Update


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | 🟠 Major |
| Triage Verdict | ❌ Invalid |
| Source | aiflow_scanner_codex, aiflow_scanner_taint |
| Scan Model | gemini-3-pro-preview |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/XferMgr.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/XferMgr.sol
- **Lines:** 1–1

## Description

XferMgr.propExecute (via Vault.execXferProp/executeProposal) is reentrancy-exploitable because it violates Checks-Effects-Interactions: it performs external transfers inside a loop (ERC20 transferFrom, ERC1155 safeTransferFrom at Anchor 7, and Vault.xferNative at Anchor 5 which uses a low-level .call) but only advances the proposal execution cursor (PropHdr.iXfer / ph.iXfer) after the loop completes, and additionally relies on an optimization where successful transfers (t.status) are not written to storage. If the Vault or transfer target can reenter during these calls (e.g., ETH receive/fallback triggered by xferNative, ERC1155 onERC1155Received, or a malicious token/recipient), an attacker can submit a proposal with multiple native/ERC1155 transfers to themselves and, during the first transfer, reenter to invoke a nested execXferProp/propExecute; the nested call observes the stale iXfer (e.g., still 0) and re-processes already-in-progress indices, resulting in duplicate payouts/double spending and potential draining of the Vault’s native balance. The state machine/epoch protections cited (ph.iXfer and ph.executedAt) fail because they are updated only at the very end, and the outer call can also overwrite iXfer with a smaller value than a reentrant inner call stored, leaving the cursor inconsistent and enabling further duplicate execution in later transactions. Mitigations include adding reentrancy protection (nonReentrant on propExecute and/or Vault.execXferProp, or a per-proposal execution lock) and/or persisting iXfer before each external transfer (with careful failure handling) so reentrant calls cannot re-execute the same indices.

## Recommendation

- Add reentrancy protection to all proposal execution entry points. Apply a global nonReentrant guard to propExecute and Vault.execXferProp, or implement a per-proposal execution lock (e.g., mapping proposalId => executing flag). Set the lock at function entry, revert on reentry, and clear it only after completion (including on failure via finally-style cleanup).
- Make the execution cursor monotonic and persisted per iteration. Before performing each external call (ERC20 transferFrom, ERC1155 safeTransferFrom at Anchor 7, and Vault.xferNative at Anchor 5), write the next index to ph.iXfer in storage so reentrant calls cannot re-execute the same index. Always read the current index from storage at the start of each iteration and never overwrite ph.iXfer with a smaller/older value on function exit.
- Persist per-transfer outcomes (e.g., t.status) to storage and skip already completed indices on subsequent calls. Ensure the loop is idempotent and resumable across transactions, with consistent handling of partial execution and failures.
- Enforce Checks-Effects-Interactions within each iteration: validate bounds and invariants, update proposal state (cursor/status) in storage, then perform the external transfer. Keep xferNative/.call and token transfers behind the same guard.
- Optionally remove batch push transfers entirely by switching to a pull-based model (credit balances on approval; recipients withdraw via a guarded function), eliminating reentrancy surfaces from token/ETH callbacks during proposal execution.

## Vulnerable Code

```
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
```

## Related Context

```
_requireOnlyVault -> function _requireOnlyVault(address caller) internal view {
        if (caller == _contracts[CU.Vault]) return;
        revert AC.AccessDenied(caller);
    }

_makeCr -> function _makeCr(address caller, uint40 seqNumEx, UUID reqId, AddXferRc rc) private {
        // slither-disable-next-line uninitialized-local (zero-init is ok)
        ICallTracker.CallRes memory cr;
        cr.rc = uint16(rc);
        _setCallRes(caller, seqNumEx, reqId, cr);
    }

_makeCr -> function _makeCr(address caller, uint40 seqNumEx, UUID reqId, AddXferRc rc) private {
        // slither-disable-next-line uninitialized-local (zero-init is ok)
        ICallTracker.CallRes memory cr;
        cr.rc = uint16(rc);
        _setCallRes(caller, seqNumEx, reqId, cr);
    }

_makeCr -> function _makeCr(address caller, uint40 seqNumEx, UUID reqId, AddXferRc rc) private {
        // slither-disable-next-line uninitialized-local (zero-init is ok)
        ICallTracker.CallRes memory cr;
        cr.rc = uint16(rc);
        _setCallRes(caller, seqNumEx, reqId, cr);
    }

_xferLoopRev -> function _xferLoopRev(Prop storage prop, PropExecuteCtx memory ctx) private returns(uint iExec, uint fails)
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

_xferLoopErc1155 -> function _xferLoopErc1155(Xfer[] storage xfers, address tokAddr, uint iBegin, uint xfersLen, uint gasLimit) private
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
```
