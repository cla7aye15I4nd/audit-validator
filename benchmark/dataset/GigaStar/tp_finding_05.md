# Renaming allows name collisions across active/inactive maps, enabling index corruption and potentially freezing assets


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex, aiflow_scanner_smart |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./source_code/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/LibraryBI.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/LibraryBI.sol
- **Lines:** 1–1

## Description

`BoxMgr.renameBox` has a logical flaw in its uniqueness checks: it relies on `BI.renameBox`, which only verifies that `newNameKey` is unused within the single `Emap` passed to it. In `BoxMgr`, boxes are partitioned across two separate maps—`_boxes` (active) and `_inactive` (inactive). While `addBox` enforces global name uniqueness across both maps, `renameBox` calls `BI.renameBox` on only the map where the box currently resides and does not first ensure that `newNameKey` is absent from the other map. This allows the same `nameKey` to exist simultaneously in `_boxes` and `_inactive` (e.g., renaming an active box to a name already used by an inactive box, or vice versa), breaking the intended invariant of global uniqueness and putting the system into a corruptible state.

This broken invariant is then exploited by `BoxMgr.rotateBox`, which moves entries between `_boxes` and `_inactive` using `BI.addBoxNoCheck(dst, nameKey, info)` and assumes the destination cannot already contain `nameKey`. If a destination entry with the same `nameKey` exists (made possible by the flawed `renameBox`), `idxByName[nameKey]` in the destination is overwritten to point to the newly moved box, while the previously existing box remains in the destination’s `values` array and `idxByAddr` but loses its name-based index entry. The earlier box becomes effectively orphaned: it still exists in storage but is no longer reachable by `nameKey`.

Because Box contracts are owned/controlled by `BoxMgr` (only `BoxMgr` can `push`/`approve`), and operational methods resolve boxes by `nameKey` (derived from the name string) rather than by address, an orphaned box becomes practically unmanageable through the manager. This can permanently strand assets held by that box, effectively freezing tokens.

Example sequence: `addBox("BoxA")`, `addBox("BoxB")`, `rotateBox("BoxB", activate=false)` to `_inactive`, then `renameBox("BoxA","BoxB")` succeeds because `_boxes` has no "BoxB" even though `_inactive` does; finally `rotateBox("BoxB", activate=true)` moves the inactive "BoxB" back and overwrites the active entry’s `idxByName`, orphaning the previously mapped box.

Fix: enforce global uniqueness in `renameBox` by requiring `newNameKey` to be unused in BOTH `_boxes` and `_inactive` before renaming (and ideally ensure `oldNameKey` exists in exactly one of them). As defense-in-depth, `rotateBox` should revert/fail if the destination already contains `nameKey` instead of using `addBoxNoCheck`, preventing state corruption even if invariants are violated.

## Recommendation

- Enforce global nameKey uniqueness in `BoxMgr.renameBox`:
  - Revert if `newNameKey` exists in either `_boxes` or `_inactive`.
  - Require that `oldNameKey` exists in exactly one of the two maps, then call `BI.renameBox` only on that map.
  - Add a post-condition check that `newNameKey` appears in exactly one map and `oldNameKey` is removed from both.

- Harden `BoxMgr.rotateBox`:
  - Stop using `BI.addBoxNoCheck` for cross-map moves. Revert if the destination already contains `nameKey`.
  - Add a post-condition that `nameKey` exists in the destination and not in the source, and that all indices (`idxByName`, `idxByAddr`) and `values` are consistent.

- Apply the same invariant across all mutating entry points:
  - At all times, a `nameKey` must exist in at most one of `_boxes` and `_inactive`.
  - If any invariant check fails, revert rather than overwriting indices.

- Add internal assertions and tests:
  - Property tests/fuzzing covering rename/rotate sequences across both maps.
  - Negative tests verifying that renaming to a name present in the other map and rotating into an occupied `nameKey` both revert.

- Operational safeguard:
  - If deployed state may already contain duplicates, add a temporary admin-guarded reconciliation routine to detect and resolve duplicates before enabling `rotateBox` and `renameBox`, or temporarily pause those functions until the state is cleaned.

## Vulnerable Code

```
function renameBox(Emap storage emap, bytes32 oldNameKey, bytes32 newNameKey, string memory newName)
        internal returns(bool)
    {
        uint i = emap.idxByName[newNameKey];
        if (i != SENTINEL_INDEX) return false; // New name already in use

        i = emap.idxByName[oldNameKey];
        if (i == SENTINEL_INDEX) return false; // Old name not found

        // Update value
        BoxInfo storage box = emap.values[i];
        box.nameKey = newNameKey;
        box.name = newName;

        // Update mapping to `values` index
        delete emap.idxByName[oldNameKey];  // Remove old name mapping to index
        emap.idxByName[newNameKey] = i;     // Add new name mapping to index
        // No need to update `emap.idxByAddr`
        return true;
    }
```
