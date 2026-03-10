# Old Referral Codes Remain Active After Being Replaced


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | — |
| Triage Verdict | ✅ Valid |
| Triage Reason | Valid finding |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./src/projects/anome 2/shop/referral/ShopReferralInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/referral/ShopReferralInternal.sol
- **Lines:** 46–51

## Description

The `_setCode` function is responsible for assigning a referral code to an account. When an account that already has a code is assigned a new one (e.g., through a function like `_recreateCode`), `_setCode` overwrites the forward mapping (`accountCode`) with the new code but fails to clear the reverse mapping (`accountByCode`) for the old code. Consequently, the old code's entry in `accountByCode` still points to the original account. This results in the account having two active referral codes: the new, official code and the old, 'ghost' code. This is unintended behavior, as old codes should be deactivated but instead remain functional, allowing a user to accumulate multiple active referral codes.

**Exploit Demonstration:**
An auditor can confirm the bug by following these steps, assuming public functions exist that call `_createCode` and `_recreateCode` respectively.

1.  **Initial Code Creation:** User A calls a function that executes `_createCode(UserA)`. A unique code, e.g., `1001`, is generated. The state becomes `accountCode[UserA] = 1001` and `accountByCode[1001] = UserA`.

2.  **Code Recreation:** User A calls a function that executes `_recreateCode(UserA)`. A new unique code, e.g., `2002`, is generated, and `_setCode(UserA, 2002)` is called.

3.  **Inconsistent State:** The function updates `accountCode[UserA]` to `2002` and sets `accountByCode[2002] = UserA`. However, the old mapping `accountByCode[1001]` is not cleared and still points to User A.

4.  **Verification:** An auditor can verify that both `accountByCode[1001]` and `accountByCode[2002]` resolve to User A's address. If a new user, User B, attempts to register using the old code `1001`, any function relying on the `accountByCode` mapping will identify User A as the sponsor. This confirms that the supposedly replaced code remains active, which constitutes a logical flaw.

## Vulnerable Code

```
function _setCode(address account, uint256 code) internal {
    ShopStorage.Layout storage data = ShopStorage.layout();
    data.accountCode[account] = code;
    data.accountByCode[code] = account;
    emit CodeSet(msg.sender, account, code);
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
