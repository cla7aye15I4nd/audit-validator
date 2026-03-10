# Incorrect return value in _removeApproval leads to erroneous event data


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | info |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex, aiflow_scanner_smart |
| Scan Model | gemini-3-pro-preview |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./source_code/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/Box.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/Box.sol
- **Lines:** 1–1

## Description

When `newAllowance == 0`, `_approve` revokes an approval by calling `_removeApproval` and then emits `ApprovalUpdated` using the returned `oldAllowance`, but `_removeApproval` only assigns `oldAllowance` inside the `if (i != iLast)` swap-and-pop branch. If the removed approval is the last (or only) element in the `_approvals` array (`i == iLast`), this block is skipped and `oldAllowance` remains the default `0`, so the event incorrectly reports the prior allowance as `0` even when a nonzero allowance was actually revoked, breaking off-chain tracking/audit trails and causing indexers to miss real allowance changes. Additionally, when swap-and-pop does occur (`i != iLast`), the code copies `tokAddr/spender/allowance` from the moved approval but fails to copy `updatedAt`, leaving the moved entry with a stale timestamp and corrupting on-chain approval enumeration/history used for operational security monitoring and incident response (e.g., determining recently changed approvals). Exploit example: `approveAll(spenderAddress, [tokenInfo], 100)` emits `ApprovalUpdated old: 0, new: 100`, then `approveAll(spenderAddress, [tokenInfo], 0)` triggers `_removeApproval` with `i == iLast` and emits `ApprovalUpdated old: 0, new: 0`, masking that an allowance of 100 was revoked.

## Recommendation

- In _removeApproval, read and store the allowance (oldAllowance) from the element at index i before any mutation (swap/pop) and return this stored value unconditionally. This ensures ApprovalUpdated emits the true prior allowance even when i == iLast.
- In the swap-and-pop branch (i != iLast), move the entire approval record, including updatedAt, rather than copying a subset of fields. Preserve the moved entry’s original updatedAt to avoid a stale or missing timestamp and maintain accurate on-chain history.
- Prefer full-struct moves over per-field assignments to prevent omissions when fields are added or changed in the future.
- If there is an index mapping for approvals, update it to reflect the moved entry’s new position when swap-and-pop occurs.
- Add unit tests for both removal paths (i == iLast and i != iLast) to assert:
  - ApprovalUpdated.old equals the actual revoked allowance.
  - The moved entry retains the correct tokAddr, spender, allowance, and updatedAt.

## Vulnerable Code

```
function approveAll(address spender, TI.TokenInfo[] calldata infos, uint newAllowance) external override
        returns(ApproveRc[] memory rcs)
    { unchecked {
        _requireOwner(msg.sender); // Access control

        uint approved = 0;
        uint infosLen = infos.length;
        if (infosLen == 0) return rcs;
        rcs = new ApproveRc[](infosLen);
        for (uint i = 0; i < infosLen; ++i) { // Ubound: Caller must page
            ApproveRc rc = _approve(spender, infos[i], newAllowance);
            if (rc == ApproveRc.Success) ++approved;
            rcs[i] = rc;
        }
    } }
```

## Related Context

```
_requireOwner -> function _requireOwner(address caller) internal view {
        if (_idxOwners[caller] == SENTINEL_INDEX) revert OwnerRequired(caller);
    }
```
