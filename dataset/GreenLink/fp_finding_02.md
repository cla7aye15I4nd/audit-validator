# Spender Can Consume an Entire Allowance to Pay Fees for a Zero-Value Transfer


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | no fee is collected for zero value transfers |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./src/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The `_payFeeWhenTransfer` function, when invoked by `transferFrom`, separates the allowance consumption into two steps. It first consumes the allowance for the calculated fees and immediately executes the fee transfer/burn. Afterwards, the `transferFrom` function consumes the allowance for the remaining amount (`amountToTransfer`). This logic is flawed. A malicious spender can construct a `transferFrom` call where the specified `amount` results in the `amountToTransfer` being zero, because the fees equal the total `amount`. In such a scenario, the spender's entire approved allowance is used to pay fees from the token holder's (`from`) account. The main transfer of zero tokens then successfully executes, as it requires no further allowance. This subverts the token holder's intent, as their approved funds are entirely spent on fees without any value being transferred to the intended recipient.

**Exploit Demonstration:**

1.  **Prerequisites:** An administrator has configured the token with a total fee of 100%. For example, `taxBPS` is `10000` (100%) and `deflationBPS` is `0`.
2.  **Victim's Action:** A user, Alice, who holds at least 100 tokens, approves a malicious actor, Bob, to spend 100 of her tokens by calling `approve(bob_address, 100)`.
3.  **Exploitation:** Bob calls the `transferFrom` function with the following parameters:
    *   `from`: `alice_address`
    *   `to`: `bob_address` (or any other address)
    *   `amount`: `100`
4.  **Execution Analysis:**
    *   The internal `_payFeeWhenTransfer` function is called with `amount` = 100.
    *   The function calculates `taxAmount` as 100 (100% of 100) and `deflationAmount` as 0. The `totalFee` is 100.
    *   Consequently, `amountToTransfer` is calculated as `100 - 100 = 0`.
    *   The function then consumes Bob's allowance for the `totalFee` by calling `super._spendAllowance(alice_address, bob_address, 100)`. This succeeds because Bob has an allowance of 100.
    *   Next, 100 tokens are transferred from Alice's account to the `taxAddress`.
    *   The function returns `0` to the public `transferFrom` function.
    *   The `transferFrom` function then attempts the main transfer by calling `super.transferFrom(alice_address, bob_address, 0)`. This transaction succeeds because the subsequent allowance check for 0 tokens passes, and a transfer of 0 value is valid.
5.  **Outcome:** The transaction completes successfully. Alice loses 100 tokens to the tax address. Bob's allowance is consumed, and the intended recipient gets 0 tokens. Bob has successfully forced Alice to spend her approved 100 tokens entirely on fees.

## Vulnerable Code

```
function _payFeeWhenTransfer(address from, address to, uint256 amount) internal returns (uint256) {
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

## Related Context

```
_getTaxStorage ->         /**
         * @dev Get the tax storage.
         * @return $ The tax storage.
         */
        function _getTaxStorage() internal pure returns (TaxStorage storage $) {
            assembly {
                $.slot := TAX_STORAGE_LOCATION
            }
        }

_taxAmount ->     /**
     * @dev Calculate tax amount during a transfer
     * @param sender - Transfer sender
     * @param amount - Transfer amount
     * @dev If sender is tax address, tax fee is 0
     */
    function _taxAmount(TaxStorage memory taxStorage, address sender, uint256 amount) internal pure returns (uint256 taxAmount) {
        if (taxStorage.taxBPS > 0 && taxStorage.taxAddress != sender) {
            return (amount * taxStorage.taxBPS) / MAX_BPS_AMOUNT;
        }
        return 0;
    }

_deflationAmount ->     function _deflationAmount(TaxStorage memory taxStorage,uint256 amount) internal pure returns (uint256 deflationAmount) {
        uint256 deflationBps = taxStorage.deflationBPS;
        if (deflationBps > 0) {
            return (amount * deflationBps) / MAX_BPS_AMOUNT;
        }
        return 0;
    }

_checkMaxAmountPerAddress -> function _checkMaxAmountPerAddress(address to, uint256 amount) private view {
        if (!isMaxAmountPerAddressSet()) {
            return;
        }
        uint256 newAmount = balanceOf(to) + amount;
        if (newAmount > _getTokenStorage().maxTokenAmountPerAddress) {
            revert AddrBalanceExceedsMaxAllowed(to, newAmount);
        }
    }

isForceTransferAllowed ->     /// @dev Return if the token is forceTransferAllowed
    function isForceTransferAllowed() public view returns (bool) {
        return _getTokenStorage().features.isForceTransferAllowed;
    }
```
