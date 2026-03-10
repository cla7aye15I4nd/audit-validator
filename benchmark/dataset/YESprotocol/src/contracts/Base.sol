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
