# DoS Situation of Transfer BABY Token


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `40f87c60-9f63-11ef-9b50-5f24ad33b80d` |
| Commit | `0x7f0fd26847c8bf4beb1ba80570d7f93f33333333` |

## Location

- **Local path:** `./src/BABY.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/40f87c60-9f63-11ef-9b50-5f24ad33b80d/source?file=$/bsc/mainnet/0x7f0fd26847c8bf4beb1ba80570d7f93f33333333/BABY.sol
- **Lines:** 1185–1185

## Description

The `swapAndSendToMarketingWallet()` function is intended to swap `BABY` token fees to `BNB` and send to the `marketingWallet` address. It calls the `swapExactTokensForETHSupportingFeeOnTransferTokens()` function from the Uniswap router, providing the `path` parameter. 
```solidity
   function swapAndSendToMarketingWallet(uint256 tokens) private inSwap {
        address[] memory path = new address[](4);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokens);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokens,
            0,
            path,
            marketingWallet,
            block.timestamp
        );
    }
```
Meanwhile, the `swapExactTokensForETHSupportingFeeOnTransferTokens()` function requires that the last token in the path be `BNB`.
```solidity
   require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
```
However, the `path` array is declared with four elements, but only the first two are initialized. As a result, the last token in the path defaults to the zero address, causing the aforementioned check to fail.

Additionally, the condition `!swapping && !_isAutomatedMarketMakerPair[from] && isSwapBackEnabled` always evaluates to true. If there are more `BABY` tokens in the contract than the threshold value `swapTokensAtAmount`, token transfers will be blocked, leading to a Denial of Service (DOS) issue.

## Recommendation

Recommend setting the length of the `path` array to 2.

## Vulnerable Code

```
) {
            swapAndSendToMarketingWallet(contractTokenBalance);
        }

        bool takeFee = true;
        if (
            _isExcludedFromFees[from] ||
            _isExcludedFromFees[to] ||
            swapping ||
            whitelist[from] ||
            whitelist[to] ||
            from == presaleWallet ||
            !_isAutomatedMarketMakerPair[from]
        ) {
            takeFee = false;
        }

        if (takeFee) {
            uint256 marketingTax = (marketingTaxBuy * amount) / denominator;

            uint256 totalTax = marketingTax;
            amount -= totalTax;
            super._transfer(from, address(this), totalTax);
        }

        super._transfer(from, to, amount);
    }

    function swapAndSendToMarketingWallet(uint256 tokens) private inSwap {
        address[] memory path = new address[](4);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokens);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokens,
            0,
            path,
            marketingWallet,
            block.timestamp
        );
    }

    function addWhitelist(address account) external onlyOwner {
        whitelist[account] = true;
    }

    function excludeOwnerFromFees() external onlyOwner {
        _isExcludedFromFees[owner()] = true;
        emit UpdateExcludeFromFees(owner(), true);
    }
}
```
