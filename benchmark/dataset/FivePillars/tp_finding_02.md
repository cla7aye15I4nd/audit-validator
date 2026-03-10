# Bypassing Minimum Deposit Requirement via Reward Redistribution


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

- **Local path:** `./source_code/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The `deposit` function enforces a minimum deposit amount for new investors, but the `claimReward` function does not. A user with no deposit can receive rewards (e.g., from a whitelisted pool), and upon claiming, 50% of the reward is redistributed and added to their `totalDeposit`. This process bypasses the minimum deposit check, allowing a user to become a registered investor with a `totalDeposit` balance that is below the required threshold, which is an incorrect balance update relative to the system rules.In the `claimReward` function, before updating the user's `totalDeposit`, add a check to ensure that if the user's current `totalDeposit` is zero, the `toRedistribute` amount meets the minimum deposit requirement of `10**18`.1. The contract owner whitelists an attacker for Pool 7 via `setWhitelist(attacker_address, 7, true)`. The attacker has `totalDeposit = 0`.
2. The attacker waits to accumulate a small amount of rewards, for instance, `2 ether`.
3. The attacker calls `claimReward()`. The check `_checkDepositOrClaimAmount(2 ether)` passes.
4. Assume `claimFeeInBp` is 0 for simplicity. `toInvestor` becomes `2 ether`. `toRedistribute` becomes `1 ether`, and the user is minted `1 ether`.
5. The code checks `if (investor.totalDeposit == 0)`, which is true. The attacker is added to the `_investors` array.
6. Crucially, the attacker's `totalDeposit` is updated: `accountToInvestorInfo[attacker_address].totalDeposit += 1 ether`.
7. The `deposit` function requires a first-time deposit of at least `10**18` (1 ether). While this example meets it, if the reward was smaller (e.g., total reward of 0.2 ether), the `toRedistribute` would be less than the minimum, allowing the attacker to become an investor and earn daily rewards on a sub-threshold deposit, violating the system's intended economic constraints. This update to their internal balance (`totalDeposit`) allows them to gain a status and future earnings they should not have access to.

## Recommendation

In the `claimReward` function, before updating the user's `totalDeposit`, add a check to ensure that if the user's current `totalDeposit` is zero, the `toRedistribute` amount meets the minimum deposit requirement of `10**18`.

## Vulnerable Code

```
function claimReward() external NotInPoolCriteriaUpdate {
    // ...
    // Redistribute half user reward
    if (investor.totalDeposit == 0) {
        _investors.push(investorAddress);
        if (isWhitelisted[investorAddress][7] || isWhitelisted[investorAddress][8]) onlyWhitelistedInvestorsCount -= 1;
    }
    if (investor.referer != address(0)) _updateReferers(investor.referer, toRedistribute, false);
    _updatePoolRewards(toRedistribute, investorAddress, investor.referer);
    accountToInvestorInfo[investorAddress].totalDeposit += toRedistribute;
    totalDepositAmount += toRedistribute;
    // ...
}
```
