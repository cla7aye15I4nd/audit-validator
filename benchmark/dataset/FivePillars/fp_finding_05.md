# Failure to Swap Fees Leads to Locked Tokens in Contract


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ❌ Invalid |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./source_code/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The `claimReward` function mints fee tokens directly to the contract and then immediately attempts to swap them for ETH via `_trySendFees`. If this swap fails for any reason (e.g., unfavorable market conditions, insufficient liquidity), the function simply returns. The minted fee tokens are not reverted; they remain in the contract's balance. Since there is no other mechanism to withdraw these specific tokens, they become effectively locked, and the balance update (minting) does not lead to the intended outcome of fee distribution.Decouple fee collection from the swap and distribution process. Instead of minting fees and immediately trying to swap them, accumulate the minted fees in the contract. Implement a separate, privileged (owner-only) function to withdraw these collected fee tokens or to execute the swap under more controlled conditions. This ensures that a temporary failure in the DEX interaction does not lead to a permanent lock-up of fee revenue.1. An investor calls `claimReward()`. The contract calculates a `fee` of `100` tokens.
2. The line `fivePillarsToken.mint(address(this), 100)` executes, increasing the `InvestmentManager` contract's token balance by 100.
3. The `_trySendFees()` function is called to swap these tokens for ETH and send them to the treasuries.
4. The swap fails, for example, because the `minSwapPrice` is set too high, or there is not enough liquidity in the DEX.
5. The `_trySendFees()` function returns early, and the `SwapFeesFailed` event is emitted.
6. The 100 fee tokens that were minted remain in the `InvestmentManager` contract's possession. They are not transferred to the treasuries as intended.
7. If this issue persists across many claims, a large balance of fee tokens will become stranded in the contract, representing a loss of revenue for the project. This is an incorrect final state for the fee balance.

## Recommendation

Decouple fee collection from the swap and distribution process. Instead of minting fees and immediately trying to swap them, accumulate the minted fees in the contract. Implement a separate, privileged (owner-only) function to withdraw these collected fee tokens or to execute the swap under more controlled conditions. This ensures that a temporary failure in the DEX interaction does not lead to a permanent lock-up of fee revenue.

## Vulnerable Code

```
function claimReward() external NotInPoolCriteriaUpdate {
    // ...
    (uint256 toInvestor, uint256 fee) = _calcFee(investor.accumulatedReward, claimFeeInBp);
    // ...
    fivePillarsToken.mint(address(this), fee);
    // ...
    _trySendFees();
}

function _trySendFees() internal {
    uint256 accumulatedFees = fivePillarsToken.balanceOf(address(this));
    // ...
    (bool success, ) = dexRouter.call(abi.encodeWithSelector(
        IPancakeRouter01.swapExactTokensForETH.selector,
        // ...
    ));
    if (!success) {
        fivePillarsToken.approve(dexRouter, 0);
        emit SwapFeesFailed(accumulatedFees);
        return; // Fee tokens are left in the contract
    }
    // ...
}
```
