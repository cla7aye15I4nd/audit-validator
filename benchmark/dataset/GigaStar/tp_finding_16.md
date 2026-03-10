# roleApplyRequestsFromCd allows initializing roles with address(0), potentially bricking governance/quorum permanently


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./source_code/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/LibraryAC.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/LibraryAC.sol
- **Lines:** 1–1

## Description

AC.roleApplyRequestsFromCd applies role changes without validating RoleRequest contents (notably rr.account != address(0)). During initialization (AC._AccountMgr_init via Vault.initialize), this allows adding address(0) as an Admin/Agent/Voter. Because quorum/role invariants are checked only by array lengths (_roleRangeCheck) rather than liveness, including address(0) can make the effective voter/agent set smaller than required (e.g., quorum=2 with voters [address(0), realVoter] passes _roleRangeCheck but no proposal can ever reach quorum; similarly, an Agent role set containing only address(0) prevents any proposal creation). This can permanently lock role management and proposal execution, potentially freezing critical vault operations. Fix: in roleApplyRequestsFromCd (or in _AccountMgr_init before calling it), require rr.account != address(0) for both add/remove requests and require rr.role to be in {Admin,Voter,Agent} when rr.add==true (matching the validation already done in Vault.createRoleProp).

## Recommendation

- Enforce input validation in roleApplyRequestsFromCd and use it during _AccountMgr_init/Vault.initialize:
  - Reject any RoleRequest with rr.account == address(0), for both add and remove.
  - When rr.add == true, require rr.role ∈ {Admin, Voter, Agent}, matching Vault.createRoleProp.
  - Reject duplicates and inconsistent operations (add when already present, remove when absent).

- After applying requests, assert role invariants based on live accounts (non-zero, unique):
  - Voter count >= quorum.
  - At least one Agent if proposal creation requires Agents.
  - No address(0) present in any role set.

- Unify validation logic so initialization cannot bypass the same checks used by Vault.createRoleProp.

- For existing deployments, provide an admin-only migration/cleanup to purge address(0) from role sets and re-validate quorum/role invariants.

- Add tests for zero-address attempts via initialization and proposals, and for invariant enforcement after role updates.

## Vulnerable Code

```
function roleApplyRequestsFromCd(AccountMgr storage mgr, RoleRequest[] calldata roleRequests) internal {
        uint roleRequestsLen = roleRequests.length;
        for (uint i = 0; i < roleRequestsLen; ++i) { // Upper bound: RoleReqLenMax
            RoleRequest calldata rr = roleRequests[i];
            if (rr.add) {
                addAccount(mgr, rr.account, rr.role);
            } else {
                removeAccount(mgr, rr.account);
            }
        }
        _roleRangeCheck(mgr);
    }
```
