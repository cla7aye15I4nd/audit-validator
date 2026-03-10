# Correction proposals can bypass positive requiredFunds availability checks due to upload order dependency


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | info |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./source_code/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/InstRevMgr.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/InstRevMgr.sol
- **Lines:** 1–1

## Description

For correction proposals, propAddInstRev uses prop.allocFixes[instNameKey][earnDate].requiredFunds to decide requiredFunds and whether to call _fundsAvail. However, requiredFunds is only set in propAddInstRevAdj (and propAddInstRevAdj only checks funds when requiredFunds < 0). If InstRev lines are uploaded first, requiredFunds is still the default 0, so propAddInstRev skips the funds check; later, requiredFunds can be set to a positive value in propAddInstRevAdj without any availability/allowance validation. This allows correction proposals to be fully uploaded/finalized yet fail at execution with LowFunds, creating governance-time DoS and requiring pruning/reproposal. Fix: require allocFix.requiredFunds to be set before accepting correction InstRev lines, or also validate requiredFunds > 0 in propAddInstRevAdj (or re-check/lock requiredFunds at finalize).

## Recommendation

- Treat allocFix.requiredFunds as an explicit, initialized field (e.g., track with a boolean). Reject correction InstRev lines in propAddInstRev unless requiredFunds has been set.
- In propAddInstRevAdj, validate funds/allowance for any requiredFunds != 0, not only when requiredFunds < 0. If requiredFunds increases or becomes > 0, call the same availability/allowance checks used elsewhere.
- Once any InstRev line is accepted, either forbid further changes to requiredFunds or require revalidation on every change that could increase requiredFunds.
- On finalize, re-evaluate the final requiredFunds and enforce availability/allowance checks; lock or reserve the funds to prevent LowFunds at execution.
- Prefer deriving requiredFunds deterministically from proposal data and validating incrementally, rather than relying on a mutable field that can be set after InstRev uploads.
- Add tests for all upload orders (InstRev-first, Adjust-first, interleaved) to ensure no path bypasses positive requiredFunds validation and that finalize fails early if funds are insufficient.

## Vulnerable Code

```
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
```
