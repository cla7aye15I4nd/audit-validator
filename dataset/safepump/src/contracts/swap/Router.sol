// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

import '../libraries/SafeMath.sol';
import '../libraries/TransferHelper.sol';
import '../libraries/NoneLibrary.sol';
import '../libraries/Ownable.sol';
import '../libraries/SafeERC20.sol';
import '../libraries/ReentrancyGuard.sol';
import '../interfaces/IFactory.sol';
import '../interfaces/IERC25.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IPair.sol';
import '../interfaces/IRouter.sol';
import '../interfaces/IWETH.sol';

contract Router is IRouter, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public factory;
    address public feeTo;
    address public WETH;
    uint8 public feeRate;
    mapping(address => uint256) public totalFees;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'Router: EXPIRED');
        _;
    }

    constructor(
        address _factory,
        address _WETH,
        uint8 _feeRate
    ) Ownable(msg.sender) {
        require(_factory != address(0), 'Router: _factory is zero address');
        require(_WETH != address(0), 'Router: _WETH is zero address');
        factory = _factory;
        WETH = _WETH;
        feeRate = _feeRate;
        feeTo = IFactory(factory).feeTo();
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function _mintFee(uint256 amountIn, address token) internal returns (uint256 fee) {
        fee = amountIn.mul(feeRate).div(1000);
        IERC20(token).transfer(IFactory(factory).feeTo(), fee);
    }

    function setFeeRate(uint8 _feeRate) public onlyOwner {
        feeRate = _feeRate;
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address token,
        uint256 amountEquivalentDesired,
        uint256 amountTokenDesired,
        uint256 amountEquivalentMin,
        uint256 amountTokenMin
    )
        internal
        returns (
            uint256 amountEquivalent,
            uint256 amountToken,
            address pair
        )
    {
        pair = IFactory(factory).getPair(token);
        if (pair == address(0)) {
            pair = IFactory(factory).createPair(token);
        }

        (uint256 reserveEquivalent, uint256 reserveToken) = NoneLibrary.getReserves(factory, token);
        if (reserveEquivalent == 0 && reserveToken == 0) {
            (amountEquivalent, amountToken) = (amountEquivalentDesired, amountTokenDesired);
        } else {
            uint256 amountTokenOptimal = NoneLibrary.quote(amountEquivalentDesired, reserveEquivalent, reserveToken);
            if (amountTokenOptimal <= amountTokenDesired) {
                require(amountTokenOptimal >= amountTokenMin, 'Router: INSUFFICIENT_B_AMOUNT');
                (amountEquivalent, amountToken) = (amountEquivalentDesired, amountTokenOptimal);
            } else {
                uint256 amountEquivalentOptimal = NoneLibrary.quote(
                    amountTokenDesired,
                    reserveToken,
                    reserveEquivalent
                );
                assert(amountEquivalentOptimal <= amountEquivalentDesired);
                require(amountEquivalentOptimal >= amountEquivalentMin, 'Router: INSUFFICIENT_A_AMOUNT');
                (amountEquivalent, amountToken) = (amountEquivalentOptimal, amountTokenDesired);
            }
        }
    }

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
        override
        ensure(deadline)
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        )
    {
        require(IERC25(token).equivalent() == WETH, 'Router: equivalent is not weth');

        address pair;
        (amountETH, amountToken, pair) = _addLiquidity(
            token,
            msg.value,
            amountTokenDesired,
            amountETHMin,
            amountTokenMin
        );

        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));

        liquidity = IPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

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
        override
        ensure(deadline)
        returns (
            uint256 amountEquivalent,
            uint256 amountToken,
            uint256 liquidity
        )
    {
        address pair;

        (amountEquivalent, amountToken, pair) = _addLiquidity(
            token,
            amountEquivalentDesired,
            amountTokenDesired,
            amountEquivalentMin,
            amountTokenMin
        );

        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        TransferHelper.safeTransferFrom(IPair(pair).equivalent(), msg.sender, pair, amountEquivalent);
        liquidity = IPair(pair).mint(to);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address token,
        uint256 liquidity,
        uint256 amountEquivalentMin,
        uint256 amountTokenMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountEquivalent, uint256 amountToken) {
        address pair = NoneLibrary.pairFor(factory, token);
        IPair(pair).transferFrom(msg.sender, pair, liquidity);
        (amountEquivalent, amountToken) = IPair(pair).burn(to);
        require(amountEquivalent >= amountEquivalentMin, 'Router: INSUFFICIENT_A_AMOUNT');
        require(amountToken >= amountTokenMin, 'Router: INSUFFICIENT_B_AMOUNT');
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountETH, uint256 amountToken) {
        require(IERC25(token).equivalent() == WETH, 'Router: equivalent is not weth');
        (amountETH, amountToken) = removeLiquidity(
            token,
            liquidity,
            amountETHMin,
            amountTokenMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function swapExactETHForToken(
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external payable override nonReentrant ensure(deadline) returns (uint256 amountOut) {
        require(IERC25(token).equivalent() == WETH, 'Router: equivalent not weth');

        (uint256 reserveETH, uint256 reserveToken) = NoneLibrary.getReserves(factory, token);

        IWETH(WETH).deposit{value: msg.value}();
        uint256 fee = _mintFee(msg.value, WETH);
        totalFees[token] = totalFees[token].add(fee);

        uint256 amountInWithFee = msg.value.sub(fee);
        amountOut = NoneLibrary.getAmountOut(amountInWithFee, reserveETH, reserveToken);
        require(amountOut >= amountOutMin, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');

        address pair = NoneLibrary.pairFor(factory, token);
        assert(IWETH(WETH).transfer(pair, amountInWithFee));
        IPair(pair).swap(0, amountOut, amountInWithFee, to);
    }

    function swapETHForExactToken(
        uint256 amountOut,
        address token,
        address to,
        uint256 deadline
    ) external payable override nonReentrant ensure(deadline) returns (uint256 amountIn) {
        require(IERC25(token).equivalent() == WETH, 'Router: equivalent not weth');

        (uint256 reserveETH, uint256 reserveToken) = NoneLibrary.getReserves(factory, token);
        amountIn = NoneLibrary.getAmountIn(amountOut, reserveETH, reserveToken);

        uint256 fee = amountIn.mul(feeRate).div(1000);
        totalFees[token] = totalFees[token].add(fee);
        IWETH(WETH).deposit{value: fee}();
        _mintFee(amountIn, WETH);

        address pair = NoneLibrary.pairFor(factory, token);

        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(pair, amountIn));
        IPair(pair).swap(0, amountOut, amountIn, to);

        // refund dust eth, if any
        if (msg.value > amountIn + fee) TransferHelper.safeTransferETH(msg.sender, msg.value - amountIn - fee);
    }

    function swapTokenForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address token,
        address to,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) returns (uint256 amountIn) {
        require(IERC25(token).equivalent() == WETH, 'Router: equivalent not weth');

        (uint256 reserveETH, uint256 reserveToken) = NoneLibrary.getReserves(factory, token);
        amountIn = NoneLibrary.getAmountIn(amountOut, reserveToken, reserveETH);
        require(amountIn <= amountInMax, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');

        address pair = NoneLibrary.pairFor(factory, token);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountIn);
        IPair(pair).swap(amountOut, 0, amountIn, address(this));

        uint256 fee = _mintFee(amountOut, WETH);
        totalFees[token] = totalFees[token].add(fee);

        uint256 balance = IERC20(WETH).balanceOf(address(this));
        IWETH(WETH).withdraw(balance);
        TransferHelper.safeTransferETH(to, balance);
    }

    function swapExactTokenForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) returns (uint256 amountOut) {
        require(IERC25(token).equivalent() == WETH, 'Router: equivalent not weth');

        (uint256 reserveETH, uint256 reserveToken) = NoneLibrary.getReserves(factory, token);
        amountOut = NoneLibrary.getAmountOut(amountIn, reserveToken, reserveETH);
        require(amountOut >= amountOutMin, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');

        address pair = NoneLibrary.pairFor(factory, token);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountIn);
        IPair(pair).swap(amountOut, 0, amountIn, address(this));

        uint256 fee = _mintFee(amountOut, WETH);
        totalFees[token] = totalFees[token].add(fee);
        uint256 balance = IERC20(WETH).balanceOf(address(this));
        IWETH(WETH).withdraw(balance);
        TransferHelper.safeTransferETH(to, balance);
    }

    //  **** SELL Token to Equivalent ****
    function swapExactTokenForEquivalent(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) returns (uint256 amountOut) {
        (uint256 reserveEquivalent, uint256 reserveToken) = NoneLibrary.getReserves(factory, token);
        amountOut = NoneLibrary.getAmountOut(amountIn, reserveToken, reserveEquivalent);
        require(amountOut >= amountOutMin, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');

        address pair = NoneLibrary.pairFor(factory, token);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountIn);
        IPair(pair).swap(amountOut, 0, amountIn, address(this));

        uint256 realOut = IERC20(IERC25(token).equivalent()).balanceOf(address(this));

        uint256 fee = _mintFee(realOut, IERC25(token).equivalent());
        totalFees[token] = totalFees[token].add(fee);
        TransferHelper.safeTransfer(IERC25(token).equivalent(), to, realOut.sub(fee));
    }

    function swapTokenForExactEquivalent(
        uint256 amountOut,
        uint256 amountInMax,
        address token,
        address to,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) returns (uint256 amountIn) {
        (uint256 reserveEquivalent, uint256 reserveToken) = NoneLibrary.getReserves(factory, token);
        amountIn = NoneLibrary.getAmountIn(amountOut, reserveToken, reserveEquivalent);
        require(amountIn <= amountInMax, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');

        address pair = NoneLibrary.pairFor(factory, token);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountIn);
        IPair(pair).swap(amountOut, 0, amountIn, address(this));

        uint256 realOut = IERC20(IERC25(token).equivalent()).balanceOf(address(this));
        uint256 fee = _mintFee(realOut, IERC25(token).equivalent());
        totalFees[token] = totalFees[token].add(fee);
        TransferHelper.safeTransfer(IERC25(token).equivalent(), to, realOut.sub(fee));
    }

    //  **** BUY Token use Equivalent ****
    function swapExactEquivalentForToken(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address to,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) returns (uint256 amountOut) {
        (uint256 reserveEquivalent, uint256 reserveToken) = NoneLibrary.getReserves(factory, token);

        uint256 fee = amountIn.mul(feeRate).div(1000);
        TransferHelper.safeTransferFrom(IERC25(token).equivalent(), msg.sender, address(this), fee);
        _mintFee(amountIn, IERC25(token).equivalent());
        totalFees[token] = totalFees[token].add(fee);
        uint256 amountInWithFee = amountIn.sub(fee);

        amountOut = NoneLibrary.getAmountOut(amountInWithFee, reserveEquivalent, reserveToken);
        require(amountOut >= amountOutMin, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');

        address pair = NoneLibrary.pairFor(factory, token);
        TransferHelper.safeTransferFrom(IPair(pair).equivalent(), msg.sender, pair, amountInWithFee);
        IPair(pair).swap(0, amountOut, amountInWithFee, to);
    }

    function swapEquivalentForExactToken(
        uint256 amountOut,
        uint256 amountInMax,
        address token,
        address to,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) returns (uint256 amountIn) {
        (uint256 reserveEquivalent, uint256 reserveToken) = NoneLibrary.getReserves(factory, token);
        amountIn = NoneLibrary.getAmountIn(amountOut, reserveEquivalent, reserveToken);
        require(amountIn <= amountInMax, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');

        uint256 fee = amountIn.mul(feeRate).div(1000);
        TransferHelper.safeTransferFrom(IERC25(token).equivalent(), msg.sender, address(this), fee);
        _mintFee(amountIn, IERC25(token).equivalent());
        totalFees[token] = totalFees[token].add(fee);

        address pair = NoneLibrary.pairFor(factory, token);
        TransferHelper.safeTransferFrom(IPair(pair).equivalent(), msg.sender, pair, amountIn);
        IPair(pair).swap(0, amountOut, amountIn, to);
    }

    // **** NoneLibrary FUNCTIONS ****
    function quote(
        uint256 amountEquivalent,
        uint256 reserveEquivalent,
        uint256 reserveToken
    ) public pure override returns (uint256 amountToken) {
        return NoneLibrary.quote(amountEquivalent, reserveEquivalent, reserveToken);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure override returns (uint256 amountOut) {
        return NoneLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure override returns (uint256 amountIn) {
        return NoneLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }
}
