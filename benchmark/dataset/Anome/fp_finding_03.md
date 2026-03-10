# Unauthorized Pre-binding of Recruits Without Consent


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Intended design |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./source_code/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/referral/ShopReferral.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/referral/ShopReferral.sol
- **Lines:** 30–41

## Description

The bindRecruit function lets any registered sponsor (msg.sender with a non-zero accountCode and accountSponsor) bind an arbitrary address as their recruit, without verifying that the recruit has registered or agreed. Because _rebindSponsor only checks that the sponsor is valid and that the recruit has no existing sponsor, an attacker can force any victim address into their referral tree by paying the 0.1 token minimum. Once bound, the victim’s accountSponsor is non-zero and they can no longer call bindSponsor (or any similar function) to choose their intended sponsor.

Exploit Steps:
1. Attacker calls buyCode() and then bindSponsor(code) with a legitimate code to become a registered sponsor (accountCode ≠ 0 and accountSponsor ≠ 0).
2. Attacker approves the referral card contract to spend at least 0.1 tokens on their behalf.
3. Attacker calls bindRecruit(victimAddress, cardAddress, 1e17):
   • realCard.transferFrom(attacker, victimAddress, 0.1) transfers tokens to the victim’s address.
   • _rebindSponsor(victimAddress, attacker) sets data.accountSponsor[victimAddress] = attacker and records the recruit.
4. When the victim later tries to register by calling buyCode() and bindSponsor(...), _rebindSponsor will immediately revert with AccountAlreadyCreated since their accountSponsor is already set. The victim cannot join under any sponsor or change the relationship.

By omitting any consent or registration check on the recruit side, bindRecruit enables a griefing attack that hijacks referral relationships and blocks legitimate user registration.

## Vulnerable Code

```
function bindRecruit(address recruit, address card, uint256 amount) external override {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ICard realCard = data.pools[data.cardsIndex[card]].card;
        if (realCard != ICard(card)) revert InvalidReferralCardAddress();
        if (amount < 1e17) revert InvalidReferralAmount();

        if (data.accountCode[msg.sender] == 0) revert AccountNotRegister(msg.sender);
        if (data.accountSponsor[msg.sender] == address(0)) revert AccountHasNoSponsor(msg.sender);

        realCard.transferFrom(msg.sender, recruit, amount);
        _rebindSponsor(recruit, msg.sender);
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

_rebindSponsor ->     function _rebindSponsor(address account, address sponsor) internal {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (sponsor == address(0)) revert InvalidAccount(sponsor);
        if (sponsor == account) revert InvalidSponsor(sponsor);
        if (data.accountSponsor[account] != address(0)) revert AccountAlreadyCreated();

        data.accountSponsor[account] = sponsor;
        data.accountRecruits[sponsor].push(ShopTypes.Recruit({account: account, timestamp: block.timestamp}));

        emit RelationBinded(msg.sender, account, sponsor);
    }
```
