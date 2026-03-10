# External transferFrom call before state update in deposit


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | high |
| Triage Verdict | ❌ Invalid |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./source_code/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

In "deposit", fivePillarsToken.transferFrom is called before updating investor.lastDepositTimestamp and investor.totalDeposit, violating Checks-Effects-Interactions and allowing reentrancy if the token contract is malicious.Move the external call to fivePillarsToken.transferFrom after updating all relevant state variables, or add a ReentrancyGuard to the deposit function.1. Assume a malicious FivePillarsToken contract that on transferFrom invokes deposit() via reentrancy. 2. Attacker calls deposit(1e18, address(0)). 3. During transferFrom, malicious token’s hook reenters deposit. 4. Reentrancy bypasses depositDelay and other checks since state not updated yet, enabling multiple deposits in one tx. 5. Attacker increases totalDeposit multiple times for minimal actual transfer.

## Recommendation

Move the external call to fivePillarsToken.transferFrom after updating all relevant state variables, or add a ReentrancyGuard to the deposit function.

## Vulnerable Code

```
function deposit(uint256 amount, address referer) external NotInPoolCriteriaUpdate {
    ...
    // external call before state change
    fivePillarsToken.transferFrom(investorAddress, address(this), fee);
    fivePillarsToken.burnFrom(investorAddress, toInvestor);
    // state changes happen later
    investor.lastDepositTimestamp = uint32(block.timestamp);
    investor.totalDeposit += toInvestor;
    totalDepositAmount += toInvestor;
    ...
}
```
