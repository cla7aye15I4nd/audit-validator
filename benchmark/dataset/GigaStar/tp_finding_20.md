# Incomplete Data Verification Allows Finalizing Proposals with Missing Data


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_taint |
| Scan Model | gemini-3-pro-preview |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./source_code/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/RevMgr.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/RevMgr.sol
- **Lines:** 1–1

## Description

Exploitability: EXPLOITABLE
Anchor: Anchor 4 `if (ownSnap.uploadedAt == 0) return PropRevFinalRc.PartOwners;`
Root Cause: The function checks the completeness of the proposal data by inspecting only the `uploadedAt` timestamp of the *last* snapshot in the `poolRefs` array. It assumes that if the last snapshot is uploaded, all preceding snapshots are also complete. This assumption is flawed if the system allows non-sequential uploads or the creation of multiple snapshot references before their data is populated.

Preconditions:
- The protocol allows a proposal to contain multiple owner snapshots (stored in `prop.ownSnaps.poolRefs`).
- The attacker (as a proposal creator) can manipulate the order of snapshot creation and data uploading, specifically creating multiple snapshot references (e.g., A, B) but only populating the data (`uploadedAt`) for the last one (B).
- The Vault or an automated Keeper calls `propFinalize` to settle the proposal.

Exploit Steps:
1. Attacker creates a proposal and adds multiple owner snapshot references (e.g., Snapshot 1 and Snapshot 2).
2. The system's state now has `poolRefs` containing `[Ref1, Ref2]` with both having `uploadedAt == 0`.
3. Attacker uploads the data for Snapshot 2, setting its `uploadedAt` to the current timestamp.
4. Attacker intentionally leaves Snapshot 1 empty (`uploadedAt == 0`).
5. The Vault (or Keeper) triggers `propFinalize(pid)`.
6. The function retrieves the last element (`Ref2`), verifies `Ref2.uploadedAt != 0`, and passes the check.
7. The function sets `ph.uploadedAt`, marking the entire proposal as finalized.

Impact:
- **Loss of Rewards/Funds**: Since Snapshot 1 is not uploaded, users or entities accounted for in that snapshot are ignored during the final settlement/distribution phase.
- **Accounting Corruptions**: The system treats incomplete data as complete, potentially leading to discrepancies between expected and actual distributed value.

Why Existing Protections Fail:
- The protection `if (ownSnap.uploadedAt == 0)` specifically targets `poolRefs[poolRefs.length - 1]`. While it prevents finalizing a proposal with *no* uploaded tail, it fails to validate the integrity of the entire array (`0` to `length-2`).

Minimal Fix:
- Iterate through the entire `poolRefs` array in `_propFinalize` and verify that `uploadedAt > 0` for every `ownSnap`.
- Alternatively, enforce strictly sequential uploading in the `propAddOwners`/upload logic such that `Ref[i]` cannot be created or uploaded until `Ref[i-1]` is complete.

## Recommendation

- Replace the tail-only check at Anchor 4 with a completeness check over the entire prop.ownSnaps.poolRefs array. Finalization must require poolRefs.length > 0 and uploadedAt > 0 for every entry; if any entry is incomplete, return PropRevFinalRc.PartOwners.
- Alternatively (or additionally), enforce strictly sequential creation/upload: disallow creating or uploading Ref[i] unless Ref[i−1] exists and is already uploaded; prevent reordering or gaps; block finalize unless the count of uploaded snapshots equals poolRefs.length.
- Consider bounding the maximum number of snapshots per proposal to avoid gas griefing during validation.
- Add tests covering non-sequential uploads, gaps (missing earlier snapshots), empty arrays, and the case where only the last snapshot is uploaded.

## Vulnerable Code

```
function propFinalize(uint pid) external override returns(PropRevFinalRc rc) {
        _requireOnlyVault(msg.sender); // Access control
        rc = _propFinalize(pid);
    }
```

## Related Context

```
_requireOnlyVault -> function _requireOnlyVault(address caller) internal view {
        if (caller == _contracts[CU.Vault]) return;
        revert AC.AccessDenied(caller);
    }

_propFinalize -> function _propFinalize(uint pid) internal returns(PropRevFinalRc rc) {
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
```
