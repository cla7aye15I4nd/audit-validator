# Fee Distribution to Treasuries Can Be Circumvented


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | high |
| Triage Verdict | ✅ Valid |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./source_code/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The `_trySendFees` function splits the collected ETH balance between two treasury addresses, `treasury` and `treasury2`, with a 70/30 ratio. However, the contract does not validate that these two addresses are unique. If the owner sets both treasury addresses to be the same, the first transfer sends 70% of the balance, and the second transfer sends the remaining 30% to the *same address*. This incorrectly allocates 100% of the fees to a single treasury, violating the intended fee distribution mechanism.Before sending the funds, add a check to ensure that `treasury` and `treasury2` are not the same address. This can be enforced in the constructor and in any function that might change these addresses in the future. `if (treasury == treasury2) revert SameTreasuryAddress();`1. Assume the contract has successfully swapped tokens and now holds 10 ETH.
2. The code calculates `firstTreasuryAmount = 10 ETH * 70 / 100 = 7 ETH`.
3. It sends 7 ETH to `treasury`. The contract's balance is now 3 ETH.
4. The next line attempts to send the remaining balance to `treasury2`: `payable(treasury2).call{value: address(this).balance}("")`. This sends the remaining 3 ETH.
5. `treasury` receives 70% of the funds, and `treasury2` receives 30%.
6. Now, assume the owner sets `treasury` and `treasury2` to the same address.
7. The contract sends 7 ETH to the address. The balance is 3 ETH.
8. It then sends the remaining 3 ETH to the same address.
9. The single treasury address receives 100% of the funds, bypassing the intended 70/30 split. While controlled by the owner, this represents a flaw in enforcing the fee distribution structure, as a single misconfiguration (intentional or not) centralizes all fees to one treasury.

## Recommendation

Before sending the funds, add a check to ensure that `treasury` and `treasury2` are not the same address. This can be enforced in the constructor and in any function that might change these addresses in the future. `if (treasury == treasury2) revert SameTreasuryAddress();`

## Vulnerable Code

```
function _trySendFees() internal {
    uint256 accumulatedFees = fivePillarsToken.balanceOf(address(this));
    uint256 amountOutMin = accumulatedFees * minSwapPrice / 10 ** 18;
    if(accumulatedFees > 0) {
        fivePillarsToken.approve(dexRouter, accumulatedFees);
        address[] memory path = new address[](2);
        path[0] = address(fivePillarsToken);
        path[1] = IPancakeRouter01(dexRouter).WETH();
        (bool success, ) = dexRouter.call(abi.encodeWithSelector(
            IPancakeRouter01.swapExactTokensForETH.selector,
            accumulatedFees,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        ));
        // ...
        uint256 firstTreasuryAmount = address(this).balance * 70 / 100;
        (success,) = payable(treasury).call{value: firstTreasuryAmount}("");
        if (!success) revert SendEtherFailed(treasury);

        (success,) = payable(treasury2).call{value: address(this).balance}("");
        if (!success) revert SendEtherFailed(treasury2);
    }
}
```
