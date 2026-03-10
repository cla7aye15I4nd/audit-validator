# Incomplete Privilege Transfer When Setting `FEE_RECEIVER` Address


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `fd716360-e0af-11ef-b1db-b3bb1353eef6` |
| Commit | `0x86da4b72f0ce7a9d263263f521f37b3aa9a996d4` |

## Location

- **Local path:** `./source_code/bsc/mainnet/0x86da4b72f0ce7a9d263263f521f37b3aa9a996d4/Trader.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/fd716360-e0af-11ef-b1db-b3bb1353eef6/source?file=$/bsc/mainnet/0x86da4b72f0ce7a9d263263f521f37b3aa9a996d4/Trader.sol
- **Lines:** 1185–1186

## Description

The `FEE_RECEIVER` address in the `Trader` contract is assigned several important privileges, including:

- Receiving all BNB collected via fee mechanisms (`swapAndLiquify()`, `recoverBalance()`)
- Receiving all ERC20 tokens recovered via `recoverTokens()`
- Receiving approved token allowance from the contract (`_approve(address(this), FEE_RECEIVER, type(uint256).max);`)

However, when `FEE_RECEIVER` is changed via the `setFeeWallet()` function, these associated privileges are **not fully transferred** to the new address:

- The previous address retains the `type(uint256).max` allowance indefinitely unless manually revoked.
- The new address does not automatically receive an updated token allowance.
- If any external integrations or permissions depend on the prior `FEE_RECEIVER`, they may remain active or cause inconsistency.

This fragmented transfer of authority could result in unintended behavior or retained privileges for the previous `FEE_RECEIVER`, potentially introducing a centralization or security risk. 

In particular, the maximum allowance for an old `FEE_RECEIVER` might lead to tokens being stolen if this account gets compromised.

## Recommendation

We recommend centralizing the privilege logic for the `FEE_RECEIVER` role to ensure an atomic and complete transfer of rights. Specifically:

1. Revoke allowance from the old `FEE_RECEIVER` and grant it to the new one inside the `setFeeWallet()` function.
2. Consider emitting an event that clearly indicates the effective transfer of *all* responsibilities.

## Vulnerable Code

```
function isStageTwoParticipant(address _holder) public view returns (bool) {
        for (uint256 i = 0; i < partners.length; i++) {
            if (partners[i] == _holder) {
                return true;
            }
        }
        return false;
    }

    function isStageThreeParticipant(
        address _holder
    ) public view returns (bool) {
        for (uint256 i = 0; i < concil.length; i++) {
            if (concil[i] == _holder) {
                return true;
            }
        }
        return false;
    }

    function isWhiteListStageFinished() public view returns (bool) {
        return
            block.timestamp >
            startTime +
                stageOneDuration +
                stageTwoDuration +
                stageThreeDuration;
    }

    function setFeeWallet(address _feeWallet) external onlyOwner {
        FEE_RECEIVER = _feeWallet;
    }
    function excludeFromFees(address account, bool value) external onlyOwner {
        _isExcludedFromFees[account] = value;
    }

    function blacklistAddress(address account, bool value) external onlyOwner {
        _isBlacklisted[account] = value;
    }

    function changeConfig(
        uint256 _standardBuyFee,
        uint256 _standardSellFee,
        uint256 _standardTransferFee,
        uint256 _whaleSellFee,
        uint256 _whaleTransferFee,
        uint256 _amountToSwap,
        uint256 _whaleTx
    ) external onlyOwner {
        standardBuyFee = _standardBuyFee;
        standardSellFee = _standardSellFee;
        standardTransferFee = _standardTransferFee;
        whaleSellFee = _whaleSellFee;
        whaleTransferFee = _whaleTransferFee;
        amountToSwap = _amountToSwap;
        swapTokensAtAmount = amountToSwap * decimalMultiplier;
        whaleTx = _whaleTx;
        whaleTransactionAmount = whaleTx * decimalMultiplier;
    }

    function recoverBalance() external onlyOwner {
```
