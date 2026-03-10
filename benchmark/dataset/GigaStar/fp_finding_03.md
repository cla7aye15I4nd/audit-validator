# OwnSnap is created/registered before validation, enabling incomplete snapshots and inconsistent proposals


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ❌ Invalid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./source_code/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/RevMgr.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/RevMgr.sol
- **Lines:** 1–1

## Description

`_propAddOwners` calls `OI.getSnapshot(prop.ownSnaps, ...)` before validating key-existence conditions (Exists/NotFound) and paging inputs (e.g., `BadPage`, `BadIndex`, `BadTotal`). Because `getSnapshot` creates and registers a new `OwnSnap` entry when missing, calls that return an error can still permanently add an empty/incomplete snapshot to the proposal. This can (a) leave a proposal in a stuck state for that key (e.g., correction `NotFound` creates an un-uploadable snapshot) and/or (b) allow a proposal to end up with incomplete snapshots that are nonetheless sealable/executable depending on downstream assumptions, causing revenue to be transferred for instruments whose owner snapshots were never properly uploaded and leaving funds unallocated.

## Recommendation

- Validate all key-existence and paging inputs (Exists/NotFound, BadPage, BadIndex, BadTotal) before any call that can create or register an OwnSnap. Do not invoke OI.getSnapshot until all validations pass.
- Refactor OI.getSnapshot to be non-mutating by default. Provide a read-only “peek” that never creates, and a separate create path (or a createIfMissing flag) that is called only after successful validation.
- Ensure snapshot creation is atomic: create and fully populate in the same success path and revert on any failure. Never persist empty or incomplete snapshots. If staging is required, mark snapshots as “incomplete” and only register/activate them once all pages and totals are validated.
- Strengthen sealing/execution gates to require that all owner snapshots exist, are complete, and pass paging/total consistency checks. Reject proposals containing any empty or incomplete OwnSnap.
- Migrate/clean up existing state by removing or invalidating any empty/incomplete snapshots to unblock stuck proposals.
- Add tests to assert: no state changes occur on validation failures; _propAddOwners does not persist an OwnSnap on error; incomplete snapshots cannot be sealed or executed.

## Vulnerable Code

```
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
```
