# Out-of-Bounds Read in getInvestorPoolRewardPerTokenPaid


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./src/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The function getInvestorPoolRewardPerTokenPaid reads from a fixed-size array poolRewardPerInvestorPaid[9] using a user-supplied poolId without any bounds check.Add a require(poolId < 9, "Invalid poolId"); before accessing poolRewardPerInvestorPaid.1. Call getInvestorPoolRewardPerTokenPaid(0x1234..., 10) as any user.
2. The contract does not revert and returns a value from storage slot beside the array, leaking internal storage data.
3. Repeating with poolId=255 reads further unrelated storage slots.

## Recommendation

Add a require(poolId < 9, "Invalid poolId"); before accessing poolRewardPerInvestorPaid.

## Vulnerable Code

```
function getInvestorPoolRewardPerTokenPaid(address investor, uint8 poolId) external view returns(uint256) {
    return accountToInvestorInfo[investor].poolRewardPerInvestorPaid[poolId];
}
```
