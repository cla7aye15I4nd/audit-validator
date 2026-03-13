// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

import '../interfaces/IPair.sol';
import '../interfaces/IERC25.sol';
import '../interfaces/IFactory.sol';
import './SafeMath.sol';

library NoneLibrary {
    using SafeMath for uint256;

    function pairFor(address factory, address token) internal view returns (address pair) {
        return IFactory(factory).getPair(token);
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address token)
        internal
        view
        returns (uint256 reserveEquivalent, uint256 reserveToken)
    {
        (reserveEquivalent, reserveToken, ) = IPair(pairFor(factory, token)).getReserves();
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, 'Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'Library: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'Library: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = amountIn.mul(reserveOut);
        uint256 denominator = reserveIn.add(amountIn);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'Library: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn.mul(amountOut);
        uint256 denominator = reserveOut.sub(amountOut, 'Library: amountOut exceeds reserveOut');
        amountIn = (numerator / denominator).add(1);
    }

    function getTax(
        address token,
        uint256 cost,
        uint256 amountEquivalent
    ) internal view returns (uint256 amountTax) {
        uint256 taxRate = IERC25(token).taxRate();
        if (cost >= amountEquivalent) {
            return 0;
        }
        uint256 profits = amountEquivalent.sub(cost, 'Library: cost exceeds amount equivalent');
        amountTax = profits.mul(taxRate) / 100;
    }
}
