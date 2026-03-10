// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

interface IRouter {
    function addLiquidity(
        address token,
        uint256 amountEquivalentDesired,
        uint256 amountTokenDesired,
        uint256 amountEquivalentMin,
        uint256 amountTokenMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountEquivalent,
            uint256 amountToken,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountEquivalent,
            uint256 amountToken,
            uint256 liquidity
        );

    function removeLiquidity(
        address token,
        uint256 liquidity,
        uint256 amountEquivalentMin,
        uint256 amountTokenMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountEquivalent, uint256 amountToken);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactETHForToken(
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    function swapTokenForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address token,
        address to,
        uint256 deadline
    ) external returns (uint256 amountIn);

    function swapExactTokenForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function swapETHForExactToken(
        uint256 amountOut,
        address token,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountIn);

    function swapExactTokenForEquivalent(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external returns (uint256 amounts);

    function swapTokenForExactEquivalent(
        uint256 amountOut,
        uint256 amountInMax,
        address token,
        address to,
        uint256 deadline
    ) external returns (uint256 amounts);

    function swapEquivalentForExactToken(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external returns (uint256 amounts);

    function swapExactEquivalentForToken(
        uint256 amountOut,
        uint256 amountInMax,
        address token,
        address to,
        uint256 deadline
    ) external returns (uint256 amounts);

    function quote(
        uint256 amountEquivalent,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountToken);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);
}
