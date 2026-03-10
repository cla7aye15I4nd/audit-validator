# Revenue balances credited using InstRev.ccyAddr while funding transfers use proposal-level ccyAddr (token mismatch can miscredit/drain funds)


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/RevMgr.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/RevMgr.sol
- **Lines:** 1–1

## Description

In _propExecute, the token used to credit owner balances is taken from each IR.InstRev line (ctx.ccyAddr = ir.ccyAddr) and then passed into BalanceMgr.updateBalance. However, InstRevMgr.propExecInstRev funds the Vault using the proposal header currency (IInstRevMgr.PropHdr.ccyAddr), not the InstRev line’s ccyAddr. Since InstRevMgr.propAddInstRev does not validate that each InstRev.ccyAddr matches the proposal header ccyAddr (and also uses the header ccyAddr for funds-availability checks), a malformed/corrupted proposal can result in: (1) transferring token A into the Vault, while (2) crediting balances under token B. This can strand the actual funded token (token A) while making token B balances claimable, potentially draining unrelated token B holdings from the Vault (or making claims fail/creating insolvency depending on how distributions are constructed). Fix: enforce a single currency per revenue proposal by (a) validating at upload/execute that ir.ccyAddr == InstRevMgr PropHdr.ccyAddr for every InstRev, and/or (b) ignore InstRev.ccyAddr during balance crediting and always use the proposal header ccyAddr.

## Recommendation

- Enforce a single currency per revenue proposal.
  - At proposal creation (InstRevMgr.propAddInstRev): require each InstRev.ccyAddr equals PropHdr.ccyAddr; reject zero-address and mismatched currencies.
  - At execution (InstRevMgr.propExecInstRev and _propExecute): derive the currency once from the proposal header and ignore InstRev.ccyAddr when crediting balances. Optionally assert per-line equality and revert on any mismatch.
- Ensure consistency between funding and crediting by always using the proposal header ccyAddr for BalanceMgr.updateBalance and for funds-availability checks.
- Prevent execution of any existing proposals with mixed currencies; surface a clear revert reason. Provide an admin-controlled recovery path for already-stranded tokens, if applicable.
- Add tests that:
  - Verify proposal creation rejects mixed currencies.
  - Verify execution reverts on any currency mismatch.
  - Prove that the token transferred to the Vault equals the token credited in balances for all executed proposals.

## Vulnerable Code

```
function _propExecute(uint pid) internal returns(CallRes memory result) { unchecked {
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
```
