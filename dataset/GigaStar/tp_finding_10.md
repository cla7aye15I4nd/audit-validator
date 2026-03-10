# ApprovalUpdated event emits boxName and tokSym in the wrong order


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | info |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/Box.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/Box.sol
- **Lines:** 1–1

## Description

In `_approve`, the `ApprovalUpdated` event is emitted as `emit ApprovalUpdated(_name, ti.tokSym, _name, ...)`, but the event signature is `(boxNameHash, boxName, tokSym, token, spender, oldAllowance, newAllowance)`. This swaps `boxName` and `tokSym` in emitted logs, breaking off-chain indexing/monitoring of approval changes and potentially causing missed/incorrect alerting or accounting around approvals.

## Recommendation

- Update the emit in _approve so the arguments match the ApprovalUpdated signature: (boxNameHash, boxName, tokSym, token, spender, oldAllowance, newAllowance). The current call emits as “emit ApprovalUpdated(_name, ti.tokSym, _name, …)”, which swaps boxName and tokSym; ensure the second argument is the actual boxName and the third is tokSym.
- If the boxName value is not available at the call site, pass it through or persist it so both boxNameHash and boxName are emitted correctly and distinctly.
- Add tests that decode the event log and assert each parameter’s position and value (including indexed vs. non-indexed fields) to prevent regressions.
- Document the change and notify indexers/integrators that historical logs have incorrect ordering; consider a version bump or a new event name if backward compatibility is required.

## Vulnerable Code

```
/// @notice Set requested token to max approval for transfer by `spender`
/// @dev Allows `spender` to call transfer on a token directly
/// @param spender Address to approve for transfers
/// @param newAllowance Qty to approve; =0 to unapprove
/// @param info Token to grant approval
/// @return rc Return code indicating if call was successful or error context
/// @custom:api private
function approve(address spender, TI.TokenInfo calldata info, uint newAllowance) external override
    returns(ApproveRc rc)
{
    _requireOwner(msg.sender); // Access control
    rc = _approve(spender, info, newAllowance);
}
```
