# Denial-of-Service in `deposit` and `claimReward` due to Reverting Treasury Address


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

The `_trySendFees` function, called by both `deposit` and `claimReward`, sends ETH to `treasury` and `treasury2` addresses. If either of these addresses is a contract designed to reject incoming ETH payments (e.g., by reverting in its receive/fallback function), the ETH transfer will fail. The contract code handles this failure by reverting the entire transaction via `revert SendEtherFailed(...)`. This creates a scenario where a misconfigured or malicious treasury address can permanently block all deposits and reward claims for every user of the contract.Instead of reverting the entire transaction, implement a mechanism that handles failed ETH transfers gracefully. For example, the contract could store the failed transfer amount in a state variable and allow the owner to withdraw it later via a separate, dedicated function. This isolates the fee distribution process from the core user-facing functions, ensuring the contract remains operational even if a treasury address becomes problematic.1. The owner deploys the `InvestmentManager` contract. During deployment, the `treasury` address is set to the address of a malicious contract `MaliciousReceiver`.
2. The `MaliciousReceiver` contract is designed with a `receive()` or `fallback()` function that always reverts.
`contract MaliciousReceiver { receive() external payable { revert("I reject ETH"); } }`
3. A user, Alice, attempts to call `deposit(1000 * 10**18, some_referer_address)`.
4. The `deposit` function executes, calculates fees, and transfers tokens.
5. At the end of the `deposit` function, `_trySendFees()` is called.
6. `_trySendFees()` successfully swaps fee tokens for ETH.
7. The function then attempts to send ETH to the `treasury` address (`MaliciousReceiver`).
8. The `payable(treasury).call{...}` fails because `MaliciousReceiver` reverts.
9. The `if (!success) revert SendEtherFailed(treasury);` line is triggered, causing the entire `deposit` transaction to revert.
10. No user can successfully deposit or claim rewards as long as the `treasury` address is set to `MaliciousReceiver`, effectively causing a permanent Denial of Service.

## Recommendation

Instead of reverting the entire transaction, implement a mechanism that handles failed ETH transfers gracefully. For example, the contract could store the failed transfer amount in a state variable and allow the owner to withdraw it later via a separate, dedicated function. This isolates the fee distribution process from the core user-facing functions, ensuring the contract remains operational even if a treasury address becomes problematic.

## Vulnerable Code

```
function _trySendFees() internal {
    // ... swap logic ...
    if (!success) {
        // ... swap failed handling ...
        return;
    }

    uint256 firstTreasuryAmount = address(this).balance * 70 / 100;
    (success,) = payable(treasury).call{value: firstTreasuryAmount}("");
    if (!success) revert SendEtherFailed(treasury);

    (success,) = payable(treasury2).call{value: address(this).balance}("");
    if (!success) revert SendEtherFailed(treasury2);
}

function deposit(uint256 amount, address referer) external NotInPoolCriteriaUpdate {
    // ... logic ...
    _trySendFees();
}

function claimReward() external NotInPoolCriteriaUpdate {
    // ... logic ...
    _trySendFees();
}
```
