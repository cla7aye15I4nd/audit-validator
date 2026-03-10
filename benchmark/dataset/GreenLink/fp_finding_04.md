# DoS by Setting a Tax Recipient Contract that Rejects Transfers


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | high |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Context not considerred |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The `setTaxConfig` function allows the owner to set the `taxAddress` to any address, including a smart contract. If the owner sets the tax address to a contract that is coded to reject incoming token transfers (e.g., by reverting in its fallback function), any subsequent user token transfer will fail. This is because the `_payFeeWhenTransfer` function will attempt to transfer the tax fee to this rejecting contract, causing the entire transaction to revert and creating a permanent Denial of Service (DoS) for all transfer operations.The `setTaxConfig` function should ensure that the provided `taxAddress_` is not a contract, or if it is a contract, that it can successfully receive tokens. This can be done by checking `taxAddress_.code.length == 0` to allow only EOAs, or by performing a test transfer of a negligible amount to the address within the function to verify its ability to receive tokens before setting it.1. The owner deploys a contract `Rejector.sol` that has a `fallback() external payable { revert(); }` function.
2. The owner calls `setTaxConfig(address(Rejector), 500)` to set the tax recipient to this new contract and a tax rate of 5%.
3. A regular user, Alice, attempts to transfer any amount of tokens to another user, Bob, by calling `transfer(Bob, 1000)`.
4. The `transfer` function calls `_payFeeWhenTransfer` internally. A non-zero `taxAmount` is calculated.
5. The function then attempts to send the tax tokens via `super._transfer(from, taxStorage.taxAddress, taxAmount)`.
6. The transfer to the `Rejector` contract address is executed, which triggers the `fallback()` function and immediately reverts.
7. Because the internal `_transfer` call reverts, Alice's entire `transfer` transaction fails.
8. This condition persists for all users and all transfers (except those from the tax address itself), effectively freezing all token transfers.

## Recommendation

The `setTaxConfig` function should ensure that the provided `taxAddress_` is not a contract, or if it is a contract, that it can successfully receive tokens. This can be done by checking `taxAddress_.code.length == 0` to allow only EOAs, or by performing a test transfer of a negligible amount to the address within the function to verify its ability to receive tokens before setting it.

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

function _payFeeWhenTransfer(address from, address to, uint256 amount) internal returns (uint256) {
    // ...
    if (taxAmount > 0) {
        super._transfer(from, taxStorage.taxAddress, taxAmount);
    }
    // ...
}
```
