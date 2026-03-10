# Per-Address Max Cap Bypass via Internal Fee Transfer


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

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

In _payFeeWhenTransfer, the contract enforces the per-address max balance only on the net amount delivered to `to` (via _checkMaxAmountPerAddress(to, amountToTransfer)), but does not re-check or block the separate internal tax transfer (super._transfer(from, taxStorage.taxAddress, taxAmount)). As a result, when transferring to the tax collector address itself you can bypass the max cap and cause that address to hold more than the configured maximum.

Exploit Steps:
1. Deploy or initialize the token with:
   - `features.isMaxAmountPerAddressSet = true`
   - `maxTokenAmountPerAddress = M` (e.g. 100 tokens)
   - `taxStorage.taxBPS = p` > 0 (e.g. 5000 for 50%)
   - `taxStorage.deflationBPS = 0` (to isolate the effect)
2. Compute a gross transfer amount `X` so that the net delivered equals the cap:
      X – (X * p / 10000) = M
   For M=100 and p=5000, X = 200.
3. From an EOA holding ≥X tokens, call:
      transfer(taxAddress, X)
4. Inside _payFeeWhenTransfer:
   • taxAmount = 200 * 5000/10000 = 100
   • amountToTransfer = 200 – 100 = 100
   • _checkMaxAmountPerAddress(taxAddress, 100) passes (0+100 ≤ 100)
   • super._transfer(from, taxAddress, 100) executes WITHOUT a max check
   → taxAddress balance = 100
   • (no deflation)
   → function returns 100
5. The wrapper then executes super.transfer(taxAddress, 100):
   → taxAddress balance becomes 200 (100 from fee + 100 from main transfer)
6. You have now forced taxAddress to hold 200 > M = 100, demonstrating the max-per-address cap was bypassed on the fee transfer.

Because the internal fee transfer is never subject to the same max-balance check, the tax collector can accumulate tokens beyond the configured limit, violating the intended per-address cap.

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
