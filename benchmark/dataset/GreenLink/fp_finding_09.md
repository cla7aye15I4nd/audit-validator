# Deflationary Burn Cannot Be Disabled, Leading to Unintended Supply Reduction


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ❌ Invalid |
| Triage Reason | No supply reduction |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./src/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The contract has a feature flag `isDeflationary` intended to control the burn mechanism. However, the internal `_deflationAmount` function, which calculates the burn, only checks if `deflationBPS > 0` and does not consult the `isDeflationary` flag. The `setDeflationConfig` function, which can set `deflationBPS` to zero, is gated by requiring `isDeflationary` to be true. This creates a trap where if the owner sets `isDeflationary` to false while `deflationBPS` is non-zero, they can no longer modify `deflationBPS`, making the burn permanent and uncontrollable.Modify the `_deflationAmount` function to check the `isDeflationary()` feature flag before calculating the burn amount. The line should be `if (isDeflationary() && deflationBps > 0)`. This ensures that turning off the feature flag immediately disables the mechanism.1. The owner initializes the contract with `isDeflationary = true` and calls `setDeflationConfig(500)` to set a 5% burn rate.
2. At a later date, the owner decides to temporarily disable the deflation and sets the `isDeflationary` flag to `false` (assuming a setter function for feature flags exists). They expect this to stop the token burning.
3. However, transfers continue to trigger burns because `_deflationAmount` only checks if `deflationBPS` is non-zero and does not check the `isDeflationary` flag.
4. The owner attempts to permanently stop the burn by calling `setDeflationConfig(0)`.
5. The transaction reverts with the `TokenIsNotDeflationary()` error because the `isDeflationary` flag is now `false`.
6. The owner is now unable to stop the 5% burn on all transfers, leading to a permanent, unintended reduction of total supply.

## Recommendation

Modify the `_deflationAmount` function to check the `isDeflationary()` feature flag before calculating the burn amount. The line should be `if (isDeflationary() && deflationBps > 0)`. This ensures that turning off the feature flag immediately disables the mechanism.

## Vulnerable Code

```
function setDeflationConfig(uint256 deflationBPS_) external onlyOwner whenNotPaused {
    if (!isDeflationary()) {
        revert TokenIsNotDeflationary();
    }
    if (deflationBPS_ > MAX_BPS_AMOUNT) {
        revert InvalidDeflationBPS(deflationBPS_);
    }
    _getTaxStorage().deflationBPS = deflationBPS_;
    emit DeflationConfigSet(deflationBPS_);
}

function _deflationAmount(TaxStorage memory taxStorage,uint256 amount) internal pure returns (uint256 deflationAmount) {
    uint256 deflationBps = taxStorage.deflationBPS;
    if (deflationBps > 0) {
        return (amount * deflationBps) / MAX_BPS_AMOUNT;
    }
    return 0;
}
```
