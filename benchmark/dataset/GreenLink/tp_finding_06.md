# Flawed Balance Check on Self-Transfers Leads to Incorrect Reverts


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | — |
| Triage Verdict | ✅ Valid |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The `_checkMaxAmountPerAddress` function, which is supposed to enforce a maximum token holding limit per address, contains a logical flaw in how it calculates the recipient's future balance. The function calculates the new balance as `balanceOf(to) + amount`, where `amount` is the net amount being transferred (`amountToTransfer`). This calculation is incorrect for self-transfers (where the sender is also the recipient). In a self-transfer, the sender's balance is first debited by the gross amount (including fees) and then credited with the net `amountToTransfer`. The net result is a decrease in balance equal to the total fees. However, the check function only accounts for the credit part, leading it to incorrectly compute a much larger final balance and cause the transaction to revert when it should succeed.

**Exploit Demonstration:**
An auditor can demonstrate this vulnerability by simulating a self-transfer for a user whose balance is at or near the maximum limit.

**Prerequisites:**
1. The contract is initialized with `isMaxAmountPerAddressSet` set to `true`.
2. `maxTokenAmountPerAddress` is set to a value, for example, `1,000` tokens.
3. A transfer fee is configured, for example, a `taxBPS` of `1000` (10%).
4. An account, let's call it `Alice`, holds a balance equal to `maxTokenAmountPerAddress`, i.e., `1,000` tokens.

**Exploit Steps:**
1. As Alice, call the `transfer(address to, uint256 amount)` function with `to` as Alice's own address and `amount` as any value, for instance, `100` tokens. `transfer(alice_address, 100)`.
2. The `_payFeeWhenTransfer` function is called internally. It calculates a `taxAmount` of `10` and an `amountToTransfer` of `90`.
3. The function then calls `_checkMaxAmountPerAddress(alice_address, 90)`.
4. Inside `_checkMaxAmountPerAddress`, the new balance is incorrectly calculated as `balanceOf(Alice) + amountToTransfer`, which is `1000 + 90 = 1090`.
5. This calculated `newAmount` (1090) is greater than `maxTokenAmountPerAddress` (1000), causing the transaction to revert with an `AddrBalanceExceedsMaxAllowed` error.

**Expected vs. Actual Outcome:**
- **Actual:** The transaction reverts, preventing Alice from performing a self-transfer.
- **Expected:** The transaction should succeed. Alice's actual final balance would be `1000 (initial) - 10 (tax fee) = 990` tokens, which is below the maximum limit. The logical flaw in the balance check prevents this valid operation.

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
```

## Related Context

```
_payFeeWhenTransfer ->     function _payFeeWhenTransfer(address from, address to, uint256 amount) internal returns (uint256) {
        address spender = _msgSender();
        // transfer fee
        TaxStorage memory taxStorage = _getTaxStorage();
        uint256 taxAmount = _taxAmount(taxStorage, from, amount);
        uint256 deflationAmount = _deflationAmount(taxStorage, amount);
        uint256 totalFee = taxAmount + deflationAmount;
        uint256 amountToTransfer = amount - totalFee;

        // check max amount per address
        _checkMaxAmountPerAddress(to, amountToTransfer);

        // consume allowance
        if (spender != from && totalFee > 0) {
            if (spender == owner() && isForceTransferAllowed()) {
                // the owner can transfer without consuming allowance
            } else {
                // consume allowance
                super._spendAllowance(from, spender, totalFee);
            }
        }
        if (taxAmount > 0) {
            super._transfer(from, taxStorage.taxAddress, taxAmount);
        }
        if (deflationAmount > 0) {
            super._burn(from, deflationAmount);
        }

        return amountToTransfer;
    }
```
