# Unchecked return value of transferFrom in deposit


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | high |
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

The contract calls IFivePillarsToken.transferFrom without checking the returned boolean value, violating the ERC-20 standard that transferFrom should return a boolean.Use OpenZeppelin SafeERC20 or explicitly check the return value of transferFrom and revert if false.Deploy a malicious token where transferFrom(address,address,uint256) returns false (instead of reverting). Call deposit() with amount=1e18. The call to transferFrom returns false but is ignored, so no tokens are transferred, yet the contract proceeds to burn tokens, credit depositor, and update state, allowing the depositor to bypass fee payment.

## Recommendation

Use OpenZeppelin SafeERC20 or explicitly check the return value of transferFrom and revert if false.

## Vulnerable Code

```
function deposit(uint256 amount, address referer) external NotInPoolCriteriaUpdate {
    ...
    (uint256 toInvestor, uint256 fee) = _calcFee(amount, depositFeeInBp);
    fivePillarsToken.transferFrom(investorAddress, address(this), fee);
    ...
}
```
