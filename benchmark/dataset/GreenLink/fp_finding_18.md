# Spender Can Weaponize Allowance to Force Fee Payments on Token Owner


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Line 710 |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The `transferFrom` function contains a logical flaw within its fee-handling mechanism in the `_payFeeWhenTransfer` internal function. Specifically, an approved spender can trigger fee payments from a token owner's (`from`) account without the owner's consent for that specific transaction, even for transfers that result in no change to the recipient's balance. The fee is calculated on the `amount` specified by the spender, and the corresponding fee amount is immediately transferred from the `from` account's balance. This occurs because the function first pays the fees and then processes the main transfer for the remaining amount. A malicious spender can exploit this by initiating a transfer where the recipient (`to`) is the same as the sender (`from`). While the main part of the transfer is a no-op, the initial fee payment is still executed, causing a financial loss for the token owner and consuming the spender's allowance. This effectively allows the spender to use their allowance to force the token owner to pay taxes or burn tokens involuntarily.

**Exploit Demonstration:**

1.  **Prerequisites:**
    *   The Victim (`from`) holds a significant balance of the token.
    *   The Attacker (`spender`) has been approved by the Victim to spend `N` tokens (e.g., `allowance(victim, attacker)` is `1,000,000`).
    *   The token contract has a non-zero transfer fee (either `taxBPS` or `deflationBPS` is greater than 0). Let's assume a total fee of 5%.

2.  **Exploitation Step:**
    The Attacker calls the `transferFrom` function with the Victim's address as both the sender (`from`) and the recipient (`to`), and the full allowance amount as the `amount`.
    `transferFrom(victim_address, victim_address, 1_000_000)`

3.  **Execution Analysis:**
    *   The `_payFeeWhenTransfer` function is called with `amount` = 1,000,000.
    *   A `totalFee` of 50,000 (5% of 1M) is calculated. The `amountToTransfer` becomes 950,000.
    *   The Attacker's allowance for the Victim is reduced by the `totalFee` (50,000).
    *   The contract transfers 50,000 tokens from the Victim's balance to the `taxAddress` and/or burns them. The Victim's balance is now debited by 50,000 tokens.
    *   The function returns `amountToTransfer` = 950,000.
    *   The `transferFrom` function then proceeds to call `super.transferFrom(victim_address, victim_address, 950_000)`.
    *   This consumes the rest of the Attacker's allowance (950,000) and executes a transfer of 950,000 tokens from the Victim to the Victim. This final transfer has no net effect on the Victim's balance.

4.  **Outcome:**
    The Attacker has successfully used their allowance to force the Victim to pay 50,000 tokens in fees for a transfer that ultimately sent no value to an external recipient. The Victim has lost 50,000 tokens, and the Attacker has exhausted their allowance, effectively weaponizing the approval mechanism to inflict a financial loss.

## Vulnerable Code

```
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

isForceTransferAllowed ->     /// @dev Return if the token is forceTransferAllowed
    function isForceTransferAllowed() public view returns (bool) {
        return _getTokenStorage().features.isForceTransferAllowed;
    }
```
