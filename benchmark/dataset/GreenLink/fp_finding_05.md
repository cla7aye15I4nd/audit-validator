# Inconsistent Total Supply via Taxing to a Burn Address


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Intended design |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The `setTaxConfig` function allows the owner to set the `taxAddress` to any arbitrary address. If the owner sets this to a burn address (an address from which funds can never be recovered), the tax fee functions as a burn. However, since the fee is sent via `_transfer` instead of `_burn`, the contract's `totalSupply` is not reduced. This leads to a discrepancy between the effective circulating supply and the reported `totalSupply`, which can mislead users and dApps.The `setTaxConfig` function should be updated to include a check that prevents setting the `taxAddress` to known burn addresses. A simple check would be `require(taxAddress_ != address(0) && taxAddress_ != address(0xdead), "Cannot set tax address to a burn address")`.1. The owner calls `setTaxConfig` with `taxAddress_` set to a known burn address like `0x000000000000000000000000000000000000dEaD` and `taxBPS_` to 500 (5%). We assume `Helper.checkAddress` does not block this address.
2. A user, Alice, transfers 10,000 tokens to Bob.
3. The `_payFeeWhenTransfer` function calculates a `taxAmount` of 500 tokens.
4. It then calls `super._transfer(Alice, "0x...dEaD", 500)`. These 500 tokens are now irrecoverable.
5. Crucially, this operation does not decrease the `totalSupply` variable in the contract.
6. Over many transactions, a significant amount of the token supply is taken out of circulation, but the on-chain `totalSupply` remains inflated, giving a false impression of the token's actual scarcity.

## Recommendation

The `setTaxConfig` function should be updated to include a check that prevents setting the `taxAddress` to known burn addresses. A simple check would be `require(taxAddress_ != address(0) && taxAddress_ != address(0xdead), "Cannot set tax address to a burn address")`.

## Vulnerable Code

```
function setTaxConfig(address taxAddress_, uint256 taxBPS_) external onlyOwner whenNotPaused {
    if (!isTaxable()) {
        revert TokenIsNotTaxable();
    }
    if (taxBPS_ > MAX_BPS_AMOUNT) {
        revert InvalidTaxBPS(taxBPS_);
    }
    Helper.checkAddress(taxAddress_);
    TaxStorage storage taxStorage = _getTaxStorage();
    taxStorage.taxAddress = taxAddress_;
    taxStorage.taxBPS = taxBPS_;
    emit TaxConfigSet(taxStorage.taxAddress, taxStorage.taxBPS);
}
```
