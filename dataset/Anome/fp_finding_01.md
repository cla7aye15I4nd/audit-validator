# Banned Users Can Receive Battle and Referral Rewards


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Banned Users Can not join the game |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./src/projects/anome 2/shop/battle/BattleServiceInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/battle/BattleServiceInternal.sol
- **Lines:** 89–102

## Description

The `_sendVnome` function is responsible for minting vNome reward tokens to a specified account. The function contains a check to prevent minting to the zero address but lacks a crucial check to verify if the recipient account has been banned. The contract's storage includes a mapping `isAccountBanned` to track banned users, but this status is ignored within the `_sendVnome` function. This oversight allows an account marked as banned to continue receiving vNome tokens from battle participation (as a winner or loser) or from referral activities (as a sponsor). This flaw undermines the banning mechanism, as banned users can still passively accumulate rewards from the ecosystem.

**Exploit Demonstration:**
1. A user, `BannedUser`, is banned by the project owner, setting `isAccountBanned[BannedUser]` to `true`.
2. Another active user, `Player`, participates in a battle and wins. `Player` had previously set `BannedUser` as their sponsor, so `accountSponsor[Player]` equals `BannedUser`'s address.
3. The `_onBattled` function is triggered, which calls `_processVnomeDistribution` to calculate rewards.
4. `_processVnomeDistribution` allocates a 10% sponsor reward to `BannedUser` and calls `_sendVnome` with `BannedUser`'s address as the recipient.
5. The `_sendVnome` function executes. It verifies that `BannedUser`'s address is not the zero address but fails to check the `isAccountBanned` status.
6. Consequently, the function calls `IVnome(...).mint(BannedUser, rewardAmount)`, and `BannedUser` successfully receives the vNome referral rewards despite being banned.

## Vulnerable Code

```
function _sendVnome(address account, uint256 amount, bool isReferral) internal {
        if (account == address(0)) {
            return;
        }

        ShopStorage.Layout storage data = ShopStorage.layout();
        IVnome(data.config.vnome()).mint(account, amount);

        if (isReferral) {
            emit OnReferralRewawrd(account, amount);
        } else {
            emit OnBattleRewawrd(account, amount);
        }
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

vnome -> None

mint ->     function mint(address account, uint256 amount) external;
```
