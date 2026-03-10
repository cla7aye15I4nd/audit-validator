# `getTokenDelta()` Function Vulnerable to Manipulation via Direct Token Donations


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `9dcb6170-9768-11f0-942e-3b2f23c44445` |
| Commit | `ce0a43a3882d7e2ac82b457705b51e7d3b5e716b` |

## Location

- **Local path:** `./src/contracts/Base.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/9dcb6170-9768-11f0-942e-3b2f23c44445/source?file=$/github/u8-protocol/u8-contract/ce0a43a3882d7e2ac82b457705b51e7d3b5e716b/contracts/Base.sol
- **Lines:** 21–33

## Description

The `getTokenDelta()` function calculates token deltas by comparing current pair balances against reserves, making it vulnerable to manipulation through direct token donations to the pair contract.

```solidity
function getTokenDelta(address token) internal view returns (uint256) {
    IUniswapV2Pair mainPair = IUniswapV2Pair(pair);
    (uint112 reserve0, uint112 reserve1, ) = mainPair.getReserves();
    if (token == USDT) {
        uint256 bal = IERC20(USDT).balanceOf(address(mainPair));
        return bal > reserve0 ? bal - reserve0 : reserve0 - bal;
    }
    // ...
}
```

The function is used in the buy processing logic to calculate `usdtAmount` for `IPool(pool).processBuy()`, meaning manipulated deltas can affect pool operations and enable exploits in the pool contract.

## Recommendation

Remove reliance on balance-based delta calculations and use more reliable mechanisms.

## Vulnerable Code

```
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IV2SwapRouter.sol";
import "./interfaces/IUniswapV2Pair.sol";

address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
IV2SwapRouter constant ROUTER = IV2SwapRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);

abstract contract Base is Ownable {
    address public immutable pair;
    address public pool;
    uint256 public sellFeeRate;

    constructor() {
        require(USDT < address(this), "token address limit");
        pair = IUniswapV2Factory(ROUTER.factory()).createPair(address(this), USDT);
    }

    function getTokenDelta(address token) internal view returns (uint256) {
        IUniswapV2Pair mainPair = IUniswapV2Pair(pair);
        (uint112 reserve0, uint112 reserve1, ) = mainPair.getReserves();
        if (token == USDT) {
            uint256 bal = IERC20(USDT).balanceOf(address(mainPair));
            return bal > reserve0 ? bal - reserve0 : reserve0 - bal;
        } else if (token == address(this)) {
            uint256 bal = IERC20(address(this)).balanceOf(address(mainPair));
            return bal > reserve1 ? bal - reserve1 : reserve1 - bal;
        } else {
            revert("Invalid token");
        }
    }

    function _isAddLiquidity() internal view returns (bool isAdd) {
        IUniswapV2Pair mainPair = IUniswapV2Pair(pair);
        (uint112 reserve0, uint112 reserve1, ) = mainPair.getReserves();
        uint256 bal0 = IERC20(USDT).balanceOf(address(mainPair));
        uint256 bal1 = IERC20(address(this)).balanceOf(address(mainPair));
        bool add0 = bal0 > reserve0 && bal1 >= reserve1;
        bool add1 = bal1 > reserve1 && bal0 >= reserve0;
        isAdd = add0 || add1;
    }

    function _isRemoveLiquidity() internal view returns (bool isRemove) {
        IUniswapV2Pair mainPair = IUniswapV2Pair(pair);
        (uint112 reserve0, uint112 reserve1, ) = mainPair.getReserves();
        uint256 bal0 = IERC20(USDT).balanceOf(address(mainPair));
        uint256 bal1 = IERC20(address(this)).balanceOf(address(mainPair));
        bool remove0 = bal0 < reserve0 && bal1 <= reserve1;
        bool remove1 = bal1 < reserve1 && bal0 <= reserve0;
        isRemove = remove0 || remove1;
    }

    function setPool(address _pool) external onlyOwner {
        pool = _pool;
    }

    function setSellFeeRate(uint256 _sellFeeRate) external onlyOwner {
        require(_sellFeeRate <= 100, "max sell fee limit");
        sellFeeRate = _sellFeeRate;
    }
}
```
