# Unbounded accountRecruits Array Growth


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | — |
| Triage Verdict | ✅ Valid |
| Triage Reason | Valid finding |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./src/projects/anome 2/shop/referral/ShopReferralInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/referral/ShopReferralInternal.sol
- **Lines:** 108–126

## Description

The internal _removeRecruit uses delete to clear matching entries but never shrinks the storage array, and it unconditionally calls _removeSponsor. As a result, each time a user’s sponsor relationship is reset and recreated (even to the same sponsor), a new entry is appended while the old slot becomes a permanent zeroed ‘hole’. Over repeated cycles the sponsor’s recruits list grows without bound, accumulating holes that still count toward recruits.length.

Exploit Demonstration:
1. Ensure your account is already bound to Sponsor A (either by bindSponsor(0) or a prior bindSponsor(code) call).
2. Call the external changeSponsor function (which calls _changeSponsor(msg.sender, newSponsor)) with newSponsor = address of Sponsor A. Internally:
   • _changeSponsor reads oldSponsor = A and invokes _removeRecruit(A, yourAddress). This loops through accountRecruits[A], deletes your old Recruit entry (sets it to (0,0)) but leaves the slot, then calls _removeSponsor(yourAddress). 
   • _changeSponsor then calls _rebindSponsor(yourAddress, A), pushing a fresh Recruit struct onto accountRecruits[A]. Now recruits.length for A has grown by one, with a hole at the old index.
3. Repeat step 2 N times. After N cycles, accountRecruits[A].length = initial+N, with N holes and N active entries.
4. When Sponsor A later calls any function iterating over accountRecruits[A] (e.g., an external removeAllRecruit(A) or other referral-processing loop), the operation must loop over all slots (including holes), burning O(N) gas. For large N this can exceed block gas limits and block Sponsor A from managing or clearing their recruits list—resulting in a denial-of-service against Sponsor A’s referral management.

## Vulnerable Code

```
function _removeRecruit(address account, address recruit) internal {
    if (account == address(0)) {
        return;
    }

    if (recruit == address(0)) {
        return;
    }

    ShopStorage.Layout storage data = ShopStorage.layout();
    ShopTypes.Recruit[] storage recruits = data.accountRecruits[account];
    for (uint i = 0; i < recruits.length; i++) {
        if (recruits[i].account == recruit) {
            delete recruits[i];
        }
    }

    _removeSponsor(recruit);
}
```

## Related Context

```
layout ->     function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
```
