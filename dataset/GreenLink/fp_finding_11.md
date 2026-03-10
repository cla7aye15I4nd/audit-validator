# maxTokenAmountPerAddress Bypass for taxAddress


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Intended design. |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./src/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The `transfer` function checks the max‐per‐address limit only against the net amount to be delivered (`amount - fee`), but still sends the fee on top of that. If you specify the `taxAddress` as the recipient, it will receive both the net and fee portions, allowing its balance to exceed the configured `maxTokenAmountPerAddress`.

Exploit Demonstration:
1. Ensure the token is initialized with:
   • `isMaxAmountPerAddressSet == true`
   • `maxTokenAmountPerAddress == 100`
   • `taxBPS == 1000` (10% fee)
   • `taxAddress == 0xFEE…` (any address)
   Assume `balanceOf(0xFEE…) == 0`.

2. Compute an `amount` such that the net delivery (amount - fee) ≤ remaining capacity, but the total (amount) > limit. For example:
   • amount = 101
   • fee = (101 * 1000) / 10000 = 10
   • net = 101 - 10 = 91
   Check: 0 + 91 ≤ 100 passes.

3. From any funded account, call:
   transfer(0xFEE…, 101)

4. Inside `_payFeeWhenTransfer`, `_checkMaxAmountPerAddress(0xFEE…, 91)` passes.
   Then the contract:
   • calls `super._transfer(from, 0xFEE…, 10)` (the fee)
   • calls `super._burn(from, 0)` (no deflation)
   returns 91

5. Finally `super.transfer(0xFEE…, 91)` executes, giving `0xFEE…` an additional 91.

Result: `0xFEE…` ends up with 10 + 91 = 101 tokens—exceeding the `maxTokenAmountPerAddress` of 100. This bypasses the per‐address holding limit for the fee recipient.

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
