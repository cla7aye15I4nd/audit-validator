# ERC-1155 transfers can silently “succeed” against non-ERC1155 or EOA token addresses


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟢 Minor |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/XferMgr.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/XferMgr.sol
- **Lines:** 1–1

## Description

_xferLoopErc1155 treats an ERC-1155 transfer as successful unless the external call reverts. Unlike the ERC-20 path (which ABI-decodes a boolean and will fail if no return data), IERC1155.safeTransferFrom has no return value, so calling it on an EOA (or on a contract that doesn’t implement ERC-1155 but has a non-reverting fallback) will typically return success with empty returndata. The try-block will not revert, so the function will advance iExec and the proposal can be marked executed even though no token state changed and no tokens moved. This can cause incorrect ownership/accounting (e.g., CRT/asset ownership not updated while the system emits XfersProcessed and marks the proposal Done). Mitigation: pre-validate tokAddr before looping (e.g., require(tokAddr.code.length > 0) and optionally ERC165 supportsInterface(type(IERC1155).interfaceId)), and treat failure to validate as a hard failure (revert) or mark all remaining transfers as failed without advancing the execution cursor.

## Recommendation

- Reject EOAs and non-ERC1155 contracts before any transfer call. For each tokAddr, require tokAddr != address(0), tokAddr.code.length > 0, and ERC165 supportsInterface(type(IERC1155).interfaceId). Do not treat a non-reverting call with empty returndata as success.
- On validation failure, either revert the whole operation (atomic mode) or mark the relevant transfers as failed and stop advancing the execution cursor; do not emit success events or mark the proposal Done.
- Optionally maintain a curated allowlist for known non-compliant tokens; otherwise default to strict ERC165 checks.
- Cache per-token validation results to save gas when processing multiple transfers for the same tokAddr.
- Add tests to cover EOAs, contracts without ERC-1155, and proxies, ensuring the system never records success when no token state changes.

## Vulnerable Code

```
function _xferLoopErc1155(Xfer[] storage xfers, address tokAddr, uint iBegin, uint xfersLen, uint gasLimit) private
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
