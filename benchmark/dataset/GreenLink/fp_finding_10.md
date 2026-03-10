# Sender's Balance Excessively Reduced Through Multiple Debits in a Single Transfer


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ❌ Invalid |
| Triage Reason | No excessive reduction |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./src/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The root cause of the vulnerability is the flawed design of the fee payment mechanism within the `transfer` and `transferFrom` functions. The `_payFeeWhenTransfer` function executes separate, direct balance-reducing calls (`super._transfer` for tax and `super._burn` for deflation) before the main transfer operation. This results in multiple, sequential deductions from the sender's balance for a single logical transaction, which is a deviation from the atomic operation expected in a standard token transfer. While the total debited amount is correct, the multiple reductions can be considered an excessive and improper handling of the user's balance.The fee deduction and the main transfer should be handled within a single, atomic operation. The recommended approach is to override the `_update` (or `_transfer` in older OpenZeppelin versions) function. This function should receive the full transfer amount, and within it, calculate and distribute the fees to the tax address and burn address, while sending the remaining amount to the recipient. This ensures that the sender's balance is debited only once for the total amount.An attacker can exploit this vulnerability to cause a user's balance to be debited multiple times within a single `transferFrom` call, which contradicts the standard ERC20 behavior and can be considered an excessive reduction in the number of debit operations.

**Scenario:**

1.  **Setup:**
    *   `Alice` has a balance of 10,000 GLDB tokens.
    *   `Bob` is the recipient.
    *   `Spender` is an authorized spender for Alice.
    *   The contract is configured with `taxBPS = 1000` (10%) and `deflationBPS = 500` (5%).
    *   Alice approves the `Spender` to spend 1,000 GLDB tokens.
    `GLDBToken.approve(Spender, 1000)`

2.  **Attack Execution:**
    *   The `Spender` calls `transferFrom(Alice, Bob, 1000)`.

3.  **Internal Execution Flow:**
    *   The `transferFrom` function calls `_payFeeWhenTransfer(Alice, Bob, 1000)`.
    *   Inside `_payFeeWhenTransfer`:
        *   `taxAmount` is calculated as 100 tokens.
        *   `deflationAmount` is calculated as 50 tokens.
        *   `totalFee` is 150 tokens.
        *   `amountToTransfer` is 850 tokens.
        *   `super._transfer(Alice, taxAddress, 100)` is called. **Alice's balance is reduced by 100.** (First deduction)
        *   `super._burn(Alice, 50)` is called. **Alice's balance is reduced by 50.** (Second deduction)
        *   The function returns `amountToTransfer` (850).
    *   The `transferFrom` function then calls `super.transferFrom(Alice, Bob, 850)`.
    *   Inside `super.transferFrom`, `_transfer(Alice, Bob, 850)` is called. **Alice's balance is reduced by 850.** (Third deduction)

4.  **Result:**
    *   Alice's balance is reduced by a total of 1,000 tokens (100 + 50 + 850), which is mathematically correct.
    *   However, her balance was debited three separate times for a single operation authorized by the spender. The standard expectation for `transferFrom` is a single debit from the sender's account. This multi-debit behavior constitutes an excessive and unexpected series of balance reductions, breaking the atomicity of the transfer operation from the user's perspective.

## Recommendation

The fee deduction and the main transfer should be handled within a single, atomic operation. The recommended approach is to override the `_update` (or `_transfer` in older OpenZeppelin versions) function. This function should receive the full transfer amount, and within it, calculate and distribute the fees to the tax address and burn address, while sending the remaining amount to the recipient. This ensures that the sender's balance is debited only once for the total amount.

## Vulnerable Code

```
function transfer(address to, uint256 amount)
    public
    virtual
    override
    whenNotPaused
    checkTransfer(_msgSender(), to)
    returns (bool)
{
    uint256 amountToTransfer = _payFeeWhenTransfer(_msgSender(), to, amount);
    return super.transfer(to, amountToTransfer);
}

function transferFrom(address from, address to, uint256 amount)
    public
    virtual
    override
    whenNotPaused
    checkTransfer(from, to)
    returns (bool)
{
    uint256 amountToTransfer = _payFeeWhenTransfer(from, to, amount);

    // Force transfer
    if (isForceTransferAllowed() && _msgSender() == owner()) {
        super._transfer(from, to, amountToTransfer);
        return true;
    }
    // Normal transfer
    return super.transferFrom(from, to, amountToTransfer);
}

function _payFeeWhenTransfer(address from, address to, uint256 amount) internal returns (uint256) {
    address spender = _msgSender();
    // transfer fee
    TaxStorage memory taxStorage = _getTaxStorage();
    uint256 taxAmount = _taxAmount(taxStorage, from, amount);
    uint256 deflationAmount = _deflationAmount(taxStorage, amount);
    uint256 totalFee = taxAmount + deflationAmount;
    uint256 amountToTransfer = amount - totalFee;

    // ... (omitted for brevity)

    if (taxAmount > 0) {
        super._transfer(from, taxStorage.taxAddress, taxAmount);
    }
    if (deflationAmount > 0) {
        super._burn(from, deflationAmount);
    }

    return amountToTransfer;
}
```
