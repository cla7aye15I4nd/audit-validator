# Final revenue consistency check is a no-op, allowing arbitrary owner snapshots to be finalized


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | — |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex, aiflow_scanner_llm, aiflow_scanner_llm_reverse, aiflow_scanner_smart, aiflow_scanner_taint |
| Scan Model | gpt-5.2 |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/RevMgr.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/RevMgr.sol
- **Lines:** 1–1

## Description

In `_propAddOwners`, the contract intends to ensure the sum of uploaded per-owner revenues (`book.totalRevenue` / `prop.hdr.totalRevenue`) equals the authorized instrument revenue (`instRev.totalRev`) before finalizing an owner snapshot by setting `book.uploadedAt`. However, the final invariant is fatally broken: it uses `if (instRev.totalRev != instRev.totalRev) { revert RevDiff(...); }`, a tautology that can never be true, and even the revert arguments pass the same value twice, making the consistency check unreachable and allowing snapshots to be marked uploaded once paging completes (`ctx.bookLen >= req.total` / `ctx.bookLen == req.total`). Because each line is only validated locally via `owner.revenue == owner.qty * unitRev`, an attacker who can reach `_propAddOwners` (e.g., via its external wrapper; some contexts assume an Agent/`onlyAgent` or a malicious proposal owner) can choose `owner.qty` values so the total uploaded owner revenue is less than or greater than `instRev.totalRev`, then upload pages until `OI.ownersLen(book) == req.total` to trigger finalization without a revert. This breaks the core accounting invariant `Sum(OwnerRevenues) == InstrumentTotalRevenue`, causing contract-state miscalculation/illegal modification and book balance inconsistencies: over-allocation inflates liabilities and can enable unfair/manipulated distribution, unbacked liabilities, insolvency, and partial vault draining (early claimers succeed while later claims/settlements fail), while under-allocation can strand funds transferred in `propExecInstRev` with no owner balances to claim, locking value and skewing accounting. Minimal fix: compare the snapshot total against the instrument total (e.g., `if (book.totalRevenue != instRev.totalRev) { revert RevDiff(...); }`) so the finalization gate correctly enforces the intended global revenue integrity check.

## Vulnerable Code

```
function _propAddOwners(AddOwnersReq calldata req) internal returns(CallRes memory result){ unchecked {
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
                book.uploadedAt = block.timestamp;      // Mark snapshot as upload
...<truncated>...
```

## Related Context

```
function getInstRevForInstDate(uint pid, string calldata instName, uint earnDate) external view override
        returns(IR.InstRev memory instRev){
        bytes32 instNameKey = String.toBytes32(instName);
        return IR.getByKey(_getInstRevs(pid), instNameKey, earnDate);
    }

function _getInstRevs(uint pid) private view returns(IR.Emap storage){
        return pid == 0 ? _instRevs : _proposals[pid].instRevs;
    }

function toBytes32(string calldata source) public pure returns (bytes32 result){
        return String.toBytes32(source);
    }
```
