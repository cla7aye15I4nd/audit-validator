# getInstRevs pagination is ineffective because filtered queries copy the entire index array to memory (DoS risk for large datasets)


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟢 Minor |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./source_code/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/LibraryIR.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/LibraryIR.sol
- **Lines:** 1–1

## Description

When filtering by `instName` or `earnDate`, `getInstRevs` calls `_getInstRevs(emap, emap.idxName[instName], ...)` or `_getInstRevs(emap, emap.idxDate[earnDate], ...)`, but `_getInstRevs` is defined to take `uint[] memory indexes`. Because callers pass storage arrays (`emap.idxName[...]` / `emap.idxDate[...]`), Solidity copies the entire storage index array into memory before any slicing occurs, making gas and memory usage scale with the total number of matching entries (O(N)) even when `count` is small or the requested slice is empty. This defeats pagination and the library’s stated paging guarantees; once an instrument/date accumulates many entries, these getter calls can revert due to out-of-gas/out-of-memory, effectively causing a denial-of-service for enumeration and making historical revenue data unqueryable on-chain (potentially breaking any on-chain integration relying on these getters). Fix by changing `_getInstRevs` to accept `uint[] storage indexes` (or otherwise avoid full-array copying) and compute the range/end index directly on the storage array so only the requested slice is read.

## Recommendation

- Change _getInstRevs to accept uint[] storage indexes and mark it internal/private. Perform all pagination math (length, start, end) directly on the storage array and iterate only over the requested slice.
- Update getInstRevs(instName/earnDate, ...) to call the storage-based _getInstRevs with emap.idxName[instName] or emap.idxDate[earnDate] so no storage array is copied to memory.
- If a public/external interface is required, keep it as a thin wrapper that delegates to the internal storage-based function. Alternatively, expose a function to query total length and require callers to pass explicit start/count for bounded reads.
- Cap count and validate bounds (e.g., handle start >= length or empty ranges by returning an empty result) to avoid unnecessary storage reads and reverts.
- Compute page start/end indices from length without scanning skipped elements (e.g., for reverse pagination derive indices arithmetically), and pre-size the result array to the exact slice size to minimize gas.

## Vulnerable Code

```
function getInstRevs(Emap storage emap, bytes32 instName, uint earnDate, uint iBegin, uint count)
        internal view returns(InstRev[] memory results)
    { unchecked {
        if (instName != bytes32(0)) {
            if (earnDate == 0) {
                // Get all earn dates for an instrument (instName=set, earnDate=empty)
                return _getInstRevs(emap, emap.idxName[instName], iBegin, count);
            }
            // Get 1 result (instName=set, earnDate=set)
            uint iValue = emap.idxNameDate[instName][earnDate].iValue;
            if (iValue != SENTINEL_INDEX) { // then found
                results = new InstRev[](1);
                results[0] = emap.values[iValue];
            }
            return results;
        }
        if (earnDate > 0) {
            // Get all instruments for an earn dates (instName=empty, earnDate=set)
            return _getInstRevs(emap, emap.idxDate[earnDate], iBegin, count);
        }
        // Get all results (instName=empty, earnDate=empty)
        InstRev[] storage values = emap.values;

        // Calculate results length
        iBegin += FIRST_INDEX; // to ignore sentinel value
        uint resultsLen = Util.getRangeLen(values.length, iBegin, count);
        if (resultsLen == 0) return results;

        // Get results slice
        results = new InstRev[](resultsLen);
        for (uint i = 0; i < resultsLen; ++i) { // Ubound: Caller must page
            results[i] = values[iBegin + i];
        }
    } }
```
