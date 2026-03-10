# `push` does not validate TokenInfo invariants (tokType vs tokAddr/tokenId), enabling unintended asset transfers when inputs are inconsistent


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./source_code/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/Box.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/Box.sol
- **Lines:** 1–1

## Description

`_push()` branches solely on `ti.tokType` and ignores whether `ti.tokAddr`/`ti.tokenId` are consistent with that type (e.g., `NativeCoin` ignores `tokAddr` entirely). This means a caller can provide internally inconsistent `TokenInfo` that passes higher-level checks based only on `tokAddr`/`tokenId`, yet results in transferring a different asset than expected (notably ETH when `tokType==NativeCoin`). In this codebase, `Vault.createFixDepositProp()` requires `req.ti.tokAddr != 0` but does not enforce `tokType != NativeCoin`, so a FixDeposit request can be created with `tokType=NativeCoin` and a nonzero `tokAddr`, and execution will transfer native coin from the box. Add explicit validation in `push/_push` (or return `BadToken`) such as: `NativeCoin => tokAddr==0 && tokenId==0`, `Erc20 => tokAddr!=0 && tokenId==0`, `Erc1155 => tokAddr!=0` (and enforce the expected tokenId semantics).

## Recommendation

- Enforce a single, canonical TokenInfo invariant check at the start of push/_push and any entry point that accepts TokenInfo; revert (e.g., BadToken) on mismatch.
- Invariants to enforce:
  - NativeCoin: tokAddr == 0 and tokenId == 0.
  - Erc20: tokAddr != 0 and tokenId == 0.
  - Erc1155: tokAddr != 0; validate tokenId semantics according to the call context (single vs batch).
- Validate before branching on tokType and before any transfer logic. Do not ignore nonzero tokAddr for NativeCoin; reject the input instead.
- In Vault.createFixDepositProp and similar constructors, require the exact tokType expected by the product (e.g., tokType != NativeCoin when an ERC token is required), not just tokAddr != 0.
- Add a guard that msg.value == 0 unless tokType == NativeCoin, and require msg.value to match the intended NativeCoin amount when tokType == NativeCoin.
- Centralize the invariant check (pure/internal function) and reuse it across request creation, execution, deposits, and withdrawals; include unit tests for inconsistent combinations to ensure they revert.

## Vulnerable Code

```
/// @notice Push `qty` units of token to the `to`
/// @dev Allows caller to use this contract's access control rather than approval per token
/// - Caller can log the event consistently upon either forward or pull
/// @param to Transfer recipient
/// @param info Token info for a single transfer
/// @param qty Quantity to push; =0 to push entire balance
/// @return result Indicates progress where `rc` is set from `PushRc`
/// @custom:api private
function push(address to, TI.TokenInfo calldata info, uint qty) external override
    returns(PushResult memory result)
{ unchecked {
    _requireOwner(msg.sender); // Access control

    result = _push(to, info, qty);
}}

/// @notice Push `qty` units of each token to the `to`
/// @dev Allows caller to use this contract's access control rather than approval per token
/// - Caller can log the event consistently upon either forward or pull
/// @param to Transfer recipient
/// @param infos Token info for each transfer
/// @param qty Quantity to push; =0 to push entire balance
/// @return results Items indicates progress where `rc` is set from `PushRc`
/// @custom:api private
function pushAll(address to, TI.TokenInfo[] calldata infos, uint qty) external override
    returns(PushResult[] memory results)
{ unchecked {
    _requireOwner(msg.sender); // Access control

    uint pushed = 0;
    uint infosLen = infos.length;
    results = new PushResult[](infosLen);
    for (uint i = 0; i < infosLen; ++i) { // Ubound: Caller must page
        PushResult memory result = _push(to, infos[i], qty);
        if (result.rc == PushRc.Success) ++pushed;
        results[i] = result;
    }
} }
```
