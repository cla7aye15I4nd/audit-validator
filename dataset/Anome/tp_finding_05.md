# Missing Cycle Check Allows Referral Graph Loop


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
- **Lines:** 80–90

## Description

Vulnerability: The internal function _rebindSponsor only enforces that sponsor ≠ address(0), sponsor ≠ account, and that accountSponsor[account] is unset. It does not verify that the chosen sponsor isn’t already in the account’s downstream referral tree. As a result, you can rebind an ancestor under one of its own descendants, creating a cycle in the sponsor graph.

Exploit Steps:
1. Deploy or access the ShopReferral contract (which exposes public bindSponsor and changeSponsor functions that invoke _rebindSponsor internally).
2. Account A calls bindSponsor(0) → _rebindSponsor(A, defaultSponsor).
3. Account B calls bindSponsor(codeOfA) → _rebindSponsor(B, A).
4. Account C calls bindSponsor(codeOfB) → _rebindSponsor(C, B).
   • At this point the referral chain is defaultSponsor → A → B → C.
5. Account A calls changeSponsor(C) → internally _removeRecruit(defaultSponsor, A) clears A’s old sponsor, then calls _rebindSponsor(A, C).
   • Since A’s accountSponsor was reset to address(0), _rebindSponsor allows A to bind under C without checking for cycles.
6. Validate storage:
   • data.accountSponsor[A] == C
   • data.accountSponsor[C] == B
   • data.accountSponsor[B] == A
   ⇒ A → C → B → A forms a cycle.

Impact: Any routine that walks the sponsor chain (e.g. referral reward distribution, depth-based ranking) will loop indefinitely or exhaust gas, causing Denial-of-Service or logic failures in downstream features.

## Vulnerable Code

```
function _rebindSponsor(address account, address sponsor) internal {
    ShopStorage.Layout storage data = ShopStorage.layout();
    if (sponsor == address(0)) revert InvalidAccount(sponsor);
    if (sponsor == account) revert InvalidSponsor(sponsor);
    if (data.accountSponsor[account] != address(0)) revert AccountAlreadyCreated();

    data.accountSponsor[account] = sponsor;
    data.accountRecruits[sponsor].push(ShopTypes.Recruit({account: account, timestamp: block.timestamp}));

    emit RelationBinded(msg.sender, account, sponsor);
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
