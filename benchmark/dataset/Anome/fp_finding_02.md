# Incomplete Removal of Recruit Entries in _removeCode Allows Duplicate Referrals


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | _removeAllRecruit(account); used to remove the Sponsor |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./src/projects/anome 2/shop/referral/ShopReferralInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/referral/ShopReferralInternal.sol
- **Lines:** 53–65

## Description

Vulnerability:
• The internal function _removeCode deletes data.accountSponsor[account] via _removeSponsor(account) but never removes the corresponding entry in the original sponsor’s data.accountRecruits array. As a result, when the same account re-binds to its old sponsor, a fresh entry is pushed onto the sponsor’s recruits list without clearing the stale one.
• Over repeated remove-and-rebind cycles, the sponsor’s recruit array accumulates duplicate references to the same account, allowing inflation of referral counts or rewards that iterate over data.accountRecruits.

Exploit Demonstration (assuming external wrappers removeCode(bool)→_removeCode(msg.sender,…) and bindSponsor(uint)→_bindSponsor(msg.sender,…)):
1. Attacker A uses bindSponsor(codeOfS) to bind itself to sponsor S. After this call, ShopStorage.layout().accountRecruits[S] contains a single entry [A].
2. Attacker calls removeCode(true). Internally:
   – _removeSponsor(A) deletes accountSponsor[A] but does not remove A from S’s accountRecruits.
   – _removeAllRecruit(A) clears A’s own recruits, irrelevant here.
   – S’s accountRecruits still includes the stale entry [A].
3. Attacker calls bindSponsor(codeOfS) again. Internally _rebindSponsor pushes a second entry [A] into S’s accountRecruits.
4. Verify ShopStorage.layout().accountRecruits[S] now contains [A, A].
5. Repeat steps 2–4 N times. After N cycles, S’s recruit list contains N+1 entries all pointing to A.
6. When S triggers any reward or calculation that iterates over data.accountRecruits[S], S receives (N+1)× the intended benefit for a single recruit. This logical flaw can be used to siphon excessive referral bonuses to S or to drain associated reward pools.

## Vulnerable Code

```
function _removeCode(address account, bool isRemoveRelation) internal {
    ShopStorage.Layout storage data = ShopStorage.layout();
    uint256 oldCode = data.accountCode[account];
    delete data.accountCode[account];
    delete data.accountByCode[oldCode];

    if (isRemoveRelation) {
        _removeSponsor(account);
        _removeAllRecruit(account);
    }

    emit CodeRemoved(msg.sender, account, oldCode);
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

_removeSponsor -> function _removeSponsor(address account) internal {
        if (account == address(0)) {
            return;
        }

        ShopStorage.Layout storage data = ShopStorage.layout();
        delete data.accountSponsor[account];
    }

_removeAllRecruit ->     function _removeAllRecruit(address account) internal {
        if (account == address(0)) {
            return;
        }

        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.Recruit[] memory recruits = data.accountRecruits[account];
        for (uint i = 0; i < recruits.length; i++) {
            _removeSponsor(recruits[i].account);
        }

        delete data.accountRecruits[account];
    }
```
