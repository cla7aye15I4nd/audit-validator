# Unauthorized Mint in claimReward


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | info |
| Triage Verdict | ❌ Invalid |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./src/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The claimReward function calls the token’s mint() method without any access control, allowing any user to trigger arbitrary token creation via InvestmentManager.Enforce proper role-based access control on the token’s mint function (e.g., onlyOwner or specific MINTER_ROLE). Verify that only trusted contracts/users can mint tokens.1. User deposits sufficient tokens and accumulates ≥1 token of rewards.
2. Call claimReward().
3. InvestmentManager invokes fivePillarsToken.mint(investorAddress, toInvestor) and mints tokens to the caller without any owner or minter checks.

## Recommendation

Enforce proper role-based access control on the token’s mint function (e.g., onlyOwner or specific MINTER_ROLE). Verify that only trusted contracts/users can mint tokens.

## Vulnerable Code

```
function claimReward() external NotInPoolCriteriaUpdate {
    …
    fivePillarsToken.mint(address(this), fee);
    fivePillarsToken.mint(investorAddress, toInvestor);
    …
}
```
