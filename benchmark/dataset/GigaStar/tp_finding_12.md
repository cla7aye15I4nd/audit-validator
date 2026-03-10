# Instrument revenue currency can diverge from proposal currency, breaking accounting and collateralization


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/InstRevMgr.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/InstRevMgr.sol
- **Lines:** 1–1

## Description

propExecInstRev/_propExecInstRev performs funds-availability checks and transferFrom using the proposal header currency (PropHdr.ccyAddr / ph.ccyAddr; ctx.ccyAddr = ph.ccyAddr), but the per-instrument entry IR.InstRev includes its own ccyAddr that is stored from caller input by propAddInstRev without validation or overwriting, allowing instRev.ccyAddr != PropHdr.ccyAddr. RevMgr later reads the stored IR.InstRev.ccyAddr (via getInstRev) to determine which token balance to credit/debit for owners, so execution can move token A into/out of the vault while crediting liabilities/claims in token B. This mismatch can create unbacked liabilities in an arbitrary token, mis-credit the wrong token, cause claims to revert due to missing funds, drain unrelated token balances held by the vault, and potentially lead to vault insolvency for that token or an irrecoverable asset/liability mismatch. Additionally, the executed InstRev copied into executed state will persist the (potentially wrong) instRev.ccyAddr, permanently corrupting historical/accounting data. Mitigate by enforcing the invariant at upload time (preferred) with require(instRev.ccyAddr == PropHdr.ccyAddr) (and nonzero) or by ignoring calldata ccyAddr and setting stored InstRev.ccyAddr to PropHdr.ccyAddr, and add a defensive equality check in propExecInstRev/_propExecInstRev (or overwrite before persisting executed state) to ensure a single source of truth for currency across transfers and balance updates.

## Recommendation

- Treat PropHdr.ccyAddr as the single source of truth for currency on a proposal.
- In propAddInstRev, enforce the invariant at upload time: require(instRev.ccyAddr == PropHdr.ccyAddr) (and nonzero); or ignore calldata and set the stored IR.InstRev.ccyAddr to PropHdr.ccyAddr.
- In propExecInstRev/_propExecInstRev, defensively re-check equality before any funds-availability checks, transfers, or accounting updates, and ensure the executed InstRev persisted uses PropHdr.ccyAddr (overwrite mismatched values before storing).
- Ensure RevMgr and any getters operate on the normalized/stored ccyAddr so that transfers, credits, and debits reference the same token.
- Validate nonzero addresses everywhere this field is used; add a migration or guard to block execution of any pre-existing records with mismatched currency until corrected.
- Add invariant tests and assertions to cover storage, events, and executed-state copies to prevent future regressions.

## Vulnerable Code

```
function propExecInstRev(uint pid, uint iInstRev) external override returns(IRevMgr.ExecRevRc rc) {
        _requireOnlyRevMgr(msg.sender); // Access control
        rc = _propExecInstRev(pid, iInstRev);
    }
```
