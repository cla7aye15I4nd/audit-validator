# addAccount ignores pending-admin state when granting other roles, creating states where removals don’t do what governance expects


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex, aiflow_scanner_smart, aiflow_scanner_taint |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./source_code/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/LibraryAC.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/LibraryAC.sol
- **Lines:** 1–1

## Description

A control-flow flaw in `AC.removeAccount(account)` causes it to prioritize canceling a pending admin grant (`if (mgr.pending[account].role == Role.Admin)`) by executing `delete mgr.pending[account]`, emitting `AdminAddCanceled`, and immediately `return`ing, which skips the later logic that would remove the account’s active role from `AccountRoleInfo` (ARI) via `ARI.remove`. This incorrect assumption—that an address cannot be both pending `Admin` and actively assigned another role—is reachable because `AC.addAccount` only checks the currently granted role via `ARI.getRole()` (inspecting `aris` storage) and does not check `mgr.pending`, allowing an address to become pending Admin and then be granted an active non-admin role such as `Voter`/`Agent` (e.g., by calling `addAccount` twice, including via `roleApplyRequestsFromCd`, first Admin to create `mgr.pending` then Voter while `ARI.getRole` still returns `Role.None`). In this inconsistent state, any removal attempt (directly or through flows like `ragequit`, `kick`, `withdraw`, or `roleApplyRequests*`) will only clear the pending admin entry and leave the active role intact, making revocation/governance actions appear successful while privileges persist, breaking invariants and potentially enabling economic abuse if removal gates withdrawals (e.g., withdrawing staked funds while retaining voting power, or re-calling `ragequit` to double-claim). Fix by blocking granting any role to an address with an existing pending admin entry (or automatically clearing the pending entry when assigning a different role) and/or adjusting `removeAccount` to handle “pending admin + active role” by canceling pending admin and also removing any active role, reverting only when neither exists (e.g., removing the early `return`).

## Recommendation

- Enforce the invariant: an address must never simultaneously have a pending Admin entry and any active role.
- In all role-granting paths (including addAccount and roleApplyRequests*), check mgr.pending[account]. If a pending Admin exists:
  - Prefer reverting the grant of any role (including Admin) until the pending entry is resolved; or
  - If auto-resolution is desired, explicitly cancel the pending Admin before proceeding, and emit the appropriate cancellation event.
- In removeAccount, handle combined states. If both a pending Admin and an active role exist:
  - Cancel the pending Admin and also remove the active role in the same call.
  - Remove the early return so the function continues to process active-role removal after clearing pending state.
  - Only revert when neither a pending entry nor an active role exists.
- Route all role changes through a single internal function that enforces the above checks, so flows like ragequit, kick, withdraw, and roleApplyRequests* cannot bypass them.
- Ensure events reflect both actions when applicable (e.g., emit pending-admin cancellation and role removal), and maintain a deterministic emission order.
- Add invariant checks in tests and, optionally, runtime assertions to prevent reintroduction of the “pending Admin + active role” state.
- If deploying to a live system, run a one-time reconciliation to resolve any existing accounts in the inconsistent state.

## Vulnerable Code

```
function addAccount(AccountMgr storage mgr, address account, Role role) internal {
        AC.Role currRole = ARI.getRole(mgr.aris, account);
        if (currRole != AC.Role.None) revert ARI.AccountHasRole(account, currRole); // Already has role

        uint peakNonce = mgr.peakNonce;

        // Admins do a 2-step grant (pending + accept), except during `_AccountMgr_init` when peakNonce == NonceAtInit
        if (role == Role.Admin && peakNonce > NonceAtInit) { // then check for a pending account
            // When used in the `mgr.pending`, AccountInfo fields meanings are overidden (less size), described below
            ARI.AccountInfo storage ai = mgr.pending[account];
            if (ai.nonce != NonceAtInit) { // then, Add Admin (step 1 of 2)
                if (ai.role != Role.None) revert ChangeAlreadyPending(account, role);
                ai.role = Role.Admin;   // Pending role
                // `account`            // Not used in a 2-step grant
                // `nonce`              // Controls execution path during a 2-step grant
                emit AdminAddPending(account);
                return;
            }
            // Add Admin (step 2 of 2)
            delete mgr.pending[account];
        }

        ARI.add(mgr.aris, account, role, peakNonce);
    }
```
