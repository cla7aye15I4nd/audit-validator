# tryGetOwnSnap can revert on uninitialized Emap, breaking "empty if not found" behavior (e.g., querying non-existent proposal pid)


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | info |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./source_code/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/LibraryOI.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/LibraryOI.sol
- **Lines:** 1–1

## Description

OI.tryGetOwnSnap reads `iPoolRefs = emap.idxNameDate[instNameKey][earnDate]` and then unconditionally indexes `emap.poolRefs[iPoolRefs]`. If the `Emap` was never initialized via `Emap_init` (so `poolRefs.length == 0`), `iPoolRefs` will be 0 and `emap.poolRefs[0]` reverts (out-of-bounds), contradicting the function’s intent/comment of returning an empty/sentinel snapshot when not found.

This condition is reachable from RevMgr getters when querying a proposal `pid` that does not exist: `_proposals[pid].ownSnaps` is a default (uninitialized) `Emap`, so `getOwnInfo/getOwnInfosLen/getOwnInfos` can unexpectedly revert instead of returning empty data.

Fix: guard before indexing `poolRefs`, e.g. `if (iPoolRefs == SENTINEL_INDEX || emap.poolRefs.length == 0) return pool.ownSnaps[0];` (or return `(OwnSnap storage, bool found)` and have callers handle `found`).

## Recommendation

- Add a guard in OI.tryGetOwnSnap before indexing poolRefs: if the computed index is the sentinel or poolRefs is empty/uninitialized, return the sentinel snapshot instead of indexing.
- Alternatively, change the function to return (snapshot, found) and require callers to handle the not-found case without indexing.
- Update RevMgr getters (getOwnInfo/getOwnInfosLen/getOwnInfos) to rely on the guarded/boolean-return behavior so that queries for non-existent pids return empty results rather than reverting.
- Ensure ownSnaps[0] is a reserved sentinel entry that always exists and is never overwritten; initialize it during deployment or pool creation.
- Document the “empty if not found” behavior and add tests for uninitialized Emap and non-existent pid queries.

## Vulnerable Code

```
function tryGetOwnSnap(Emap storage emap, bytes32 instNameKey, uint earnDate, OwnSnapPool storage pool)
        internal view returns(OwnSnap storage ownSnap)
    {
        uint iPoolRefs = emap.idxNameDate[instNameKey][earnDate];
        return pool.ownSnaps[emap.poolRefs[iPoolRefs].poolId]; // Sentinel value if not found
    }
```
