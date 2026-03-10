# Owner Can Cause Denial of Service by Setting Excessive Fees


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | high |
| Triage Verdict | ✅ Valid |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The functions `setTaxConfig` and `setDeflationConfig` only check that the individual `taxBPS` and `deflationBPS` values do not exceed the `MAX_BPS_AMOUNT`. There is no validation to ensure that the sum of `taxBPS` and `deflationBPS` is less than or equal to `MAX_BPS_AMOUNT`. This allows the contract owner to set fee rates that sum up to more than 100%, causing an arithmetic underflow when calculating the final transfer amount (`amount - totalFee`), which makes all transfers revert.In `setTaxConfig` and `setDeflationConfig`, add a check to ensure that the sum of `taxBPS` and `deflationBPS` does not exceed `MAX_BPS_AMOUNT`. The check should be `require(taxBPS_ + deflationBPS() <= MAX_BPS_AMOUNT)` in `setTaxConfig` and `require(taxBPS() + deflationBPS_ <= MAX_BPS_AMOUNT)` in `setDeflationConfig`.The owner can set tax and deflation rates that, when combined, exceed 100%, causing all transfers to fail.

Setup:
- The owner calls `setTaxConfig(anyAddress, 8000)`, setting the tax rate to 80%.
- The owner then calls `setDeflationConfig(3000)`, setting the deflation rate to 30%.
- The sum of `taxBPS` and `deflationBPS` is `8000 + 3000 = 11000`, which is greater than `MAX_BPS_AMOUNT` (10,000).

Attack Scenario:
1. A user, Alice, attempts to transfer any amount of tokens, for example, `transfer(Bob, 1000)`.
2. The contract calls `_payFeeWhenTransfer`.
3. `taxAmount` is calculated as `(1000 * 8000) / 10000 = 800`.
4. `deflationAmount` is calculated as `(1000 * 3000) / 10000 = 300`.
5. `totalFee` becomes `800 + 300 = 1100`.
6. The code attempts to calculate `amountToTransfer = amount - totalFee`, which is `1000 - 1100`.
7. Because Solidity version 0.8.20 is used, this subtraction underflows and causes the transaction to revert.
8. No user can transfer tokens, making the token untradable. While this does not directly lead to a user receiving more tokens, it"s a high-impact availability issue stemming from fee configuration.

## Recommendation

In `setTaxConfig` and `setDeflationConfig`, add a check to ensure that the sum of `taxBPS` and `deflationBPS` does not exceed `MAX_BPS_AMOUNT`. The check should be `require(taxBPS_ + deflationBPS() <= MAX_BPS_AMOUNT)` in `setTaxConfig` and `require(taxBPS() + deflationBPS_ <= MAX_BPS_AMOUNT)` in `setDeflationConfig`.

## Vulnerable Code

```
function setTaxConfig(address taxAddress_, uint256 taxBPS_) external onlyOwner whenNotPaused {
    if (!isTaxable()) {
        revert TokenIsNotTaxable();
    }
    if (taxBPS_ > MAX_BPS_AMOUNT) {
        revert InvalidTaxBPS(taxBPS_);
    }
    //...
}

function setDeflationConfig(uint256 deflationBPS_) external onlyOwner whenNotPaused {
    if (!isDeflationary()) {
        revert TokenIsNotDeflationary();
    }
    if (deflationBPS_ > MAX_BPS_AMOUNT) {
        revert InvalidDeflationBPS(deflationBPS_);
    }
    //...
}
```
