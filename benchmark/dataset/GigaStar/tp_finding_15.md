# acceptAdmin can bypass RoleLenMax and permanently brick role governance by exceeding the admin cap


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/LibraryAC.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/LibraryAC.sol
- **Lines:** 1–1

## Description

`AC.addAccount` effectively enforces role-size constraints only through the role-proposal execution paths (`AC.roleApplyRequestsFrom*()`), which call `_roleRangeCheck()` after executing proposals; however, the two-step admin flow finalizes grants via `Vault.acceptAdmin -> AC.adminGrantStep2 -> AC.addAccount`, and this step-2 path calls `ARI.add()` without any role-length/range check. When `accept == true`, `adminGrantStep2` finalizes a pending admin by setting `pending[account].nonce = NonceAtInit` and calling `addAccount(mgr, account, Role.Admin)`, allowing a proposal to create a pending admin even when `admins.length == RoleLenMax` (since step-1 only emits `AdminAddPending` and doesn’t increment `admins.length`), and then letting acceptance push `admins.length` beyond `RoleLenMax` (5), breaking the system’s stated invariant used for bounded complexity and validation. Once `admins.length > 5`, any subsequent role proposal execution will revert in `_roleRangeCheck()` unless it also reduces `admins` back to `<= 5` within the same transaction; because `createRoleProp` caps role requests to `RoleReqLenMax` (20), if `admins.length` ever exceeds 25 it becomes impossible to remove enough admins in a single proposal to satisfy `_roleRangeCheck()`, permanently preventing any future role proposals (including fixes to roles/quorum) from executing. Fix by enforcing `RoleLenMax` on the step-2 acceptance path (e.g., check `mgr.aris.admins.length < RoleLenMax` before `ARI.add` in `AC.addAccount/adminGrantStep2`, and/or run an equivalent `_roleRangeCheck()` after `acceptAdmin` finalization).

## Recommendation

- Enforce RoleLenMax on the admin acceptance path. In the flow Vault.acceptAdmin -> AC.adminGrantStep2 -> AC.addAccount -> ARI.add, require admins.length < RoleLenMax before adding the new admin and revert on violation. Run the same post-state invariant checks performed by _roleRangeCheck() after finalization and revert if any role array exceeds its limit.

- Centralize invariant enforcement in AC.addAccount. Make AC.addAccount the single choke point that validates role-size/range constraints for all callers (role proposals and admin acceptance), and prevent any path from calling ARI.add directly without passing through these checks.

- Preserve atomicity and ordering. Perform capacity checks before mutating pending/nonce state in adminGrantStep2; ensure the whole transaction reverts on any violation so no partial state persists.

- Optionally block unfulfillable pendings. Reject creation of a pending admin when admins.length >= RoleLenMax to prevent griefing via pendings that can never be accepted.

- Provide a recovery path for deployments already over the cap. Add a governance-controlled, shrink-only mechanism (or temporarily raise RoleReqLenMax for a one-time cleanup) that allows removing sufficient admins to return to <= RoleLenMax without being blocked by _roleRangeCheck(). Ensure the recovery path cannot increase any role sizes.

- Add regression and property tests. Assert that any sequence of role proposals and acceptAdmin calls cannot push any role length beyond its cap; include boundary tests (e.g., 4→5 allowed, 5→6 reverts; many pendings with cap).

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
