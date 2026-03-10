# Missing Event Emission in setMetadata


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | low |
| Triage Verdict | ❌ Invalid |
| Triage Reason | not important enough |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The `setMetadata` function changes `tokenStorage.metadata` but does not emit any event to signal off-chain listeners of the update.Emit a dedicated `MetadataSet(string metadata)` event in `setMetadata` after updating the storage.1. Alice (owner) calls `setMetadata("v2.0")`.
2. Transaction succeeds but no event log is created.
3. Off-chain indexers listening for metadata changes see no event and cannot detect the update.

## Recommendation

Emit a dedicated `MetadataSet(string metadata)` event in `setMetadata` after updating the storage.

## Vulnerable Code

```
function setMetadata(string calldata metadata_) public onlyOwner {
    _getTokenStorage().metadata = metadata_;
    // <--- Missing event emission here
}
```
