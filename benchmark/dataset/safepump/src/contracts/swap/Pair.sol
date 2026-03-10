// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

import '../interfaces/IFactory.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IERC25.sol';
import '../libraries/SafeMath.sol';
import '../libraries/UQ112x112.sol';
import '../libraries/TransferHelper.sol';
import '../libraries/NoneLibrary.sol';
import '../libraries/Math.sol';

contract Pair is IERC20 {
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    // ERC20 part
    string public constant override name = 'LPT';
    uint8 public constant override decimals = 18;
    uint256 public override totalSupply;
    string public override symbol = 'LPT';

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    // Pair part
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    address public factory;
    address public equivalent;
    address public token;

    uint112 public reserveEquivalent;
    uint112 public reserveToken;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event
    uint256 public totalTax;

    mapping(address => uint256) public costOf;
    mapping(address => uint256) public taxOf;

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Pair: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves()
        public
        view
        returns (
            uint112 _reserveEquivalent,
            uint112 _reserveToken,
            uint32 _blockTimestampLast
        )
    {
        _reserveEquivalent = reserveEquivalent;
        _reserveToken = reserveToken;
        _blockTimestampLast = blockTimestampLast;
    }

    event Mint(address indexed sender, uint256 amountEquivalent, uint256 amountToken);
    event Burn(address indexed sender, uint256 amountEquivalent, uint256 amountToken, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amountEquivalentIn,
        uint256 amountTokenIn,
        uint256 amountEquivalentOut,
        uint256 amountTokenOut,
        address indexed to
    );
    event Sync(uint112 reserveEquivalent, uint112 reserveToken);

    // ERC20 part
    function _mint(address to, uint256 value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balanceOf[from] = balanceOf[from].sub(value, 'ERC20: burn amount exceeds balance');
        totalSupply = totalSupply.sub(value, 'ERC20: burn amount exceeds balance');
        emit Transfer(from, address(0), value);
    }

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) private {
        balanceOf[from] = balanceOf[from].sub(value, 'ERC20: transfer amount exceeds balance');
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {
        if (allowance[from][msg.sender] != uint256(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(
                value,
                'ERC20: transfer amount exceeds allowance'
            );
        }
        _transfer(from, to, value);
        return true;
    }

    // Pair part
    constructor() {
        factory = msg.sender;
    }

    function initialize(address _equivalent, address _token) external {
        require(msg.sender == factory, 'Pair: FORBIDDEN'); // sufficient check
        equivalent = _equivalent;
        token = _token;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint256 balanceEquivalent,
        uint256 balanceToken,
        uint112 _reserveEquivalent,
        uint112 _reserveToken
    ) private {
        require(balanceEquivalent <= uint112(-1) && balanceToken <= uint112(-1), 'Pair: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserveEquivalent != 0 && _reserveToken != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(UQ112x112.encode(_reserveEquivalent).uqdiv(_reserveToken)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(_reserveToken).uqdiv(_reserveEquivalent)) * timeElapsed;
        }

        reserveEquivalent = uint112(balanceEquivalent);
        reserveToken = uint112(balanceToken);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserveEquivalent, reserveToken);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint256 liquidity) {
        require(msg.sender == IFactory(factory).router(), 'Pair: FORBIDDEN');

        (uint112 _reserveEquivalent, uint112 _reserveToken, ) = getReserves(); // gas savings
        uint256 balanceEquivalent = IERC20(equivalent).balanceOf(address(this));
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        uint256 amountEquivalent = balanceEquivalent.sub(
            _reserveEquivalent,
            'Pair: _reserveEquivalent exceeds balanceEquivalent'
        );
        uint256 amountToken = balanceToken.sub(_reserveToken, 'Pair: _reserveToken exceeds balanceToken');

        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amountEquivalent.mul(amountToken)).sub(
                MINIMUM_LIQUIDITY,
                'Pair: MINIMUM_LIQUIDITY not enough'
            );
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(
                amountEquivalent.mul(_totalSupply) / _reserveEquivalent,
                amountToken.mul(_totalSupply) / _reserveToken
            );
        }

        require(liquidity > 0, 'Pair: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        uint256 cost = IERC25(token).costOf(tx.origin, amountToken);
        costOf[tx.origin] = costOf[tx.origin].add(cost);

        _update(balanceEquivalent, balanceToken, _reserveEquivalent, _reserveToken);
        emit Mint(msg.sender, amountEquivalent, amountToken);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint256 _amountEquivalent, uint256 _amountToken) {
        require(msg.sender == IFactory(factory).router(), 'Pair: FORBIDDEN'); // sufficient check
        (uint112 _reserveEquivalent, uint112 _reserveToken, ) = getReserves(); // gas savings
        uint256 balanceEquivalent = IERC20(equivalent).balanceOf(address(this));
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee

        uint256 amountEquivalent = liquidity.mul(balanceEquivalent) / _totalSupply; // using balances ensures pro-rata distribution
        uint256 amountToken = liquidity.mul(balanceToken) / _totalSupply; // using balances ensures pro-rata distribution
        require(amountEquivalent > 0 && amountToken > 0, 'Pair: INSUFFICIENT_LIQUIDITY_BURNED');

        _burn(address(this), liquidity);

        _amountEquivalent = amountEquivalent;
        uint256 cost = costOf[tx.origin].mul(liquidity).div(liquidity.add(IERC20(address(this)).balanceOf(tx.origin)));
        uint256 _cost = cost.div(1e18);
        uint256 tax = NoneLibrary.getTax(token, _cost, _amountEquivalent);

        if (tax > 0) {
            totalTax = totalTax.add(tax);
            _amountEquivalent = _amountEquivalent.sub(tax, 'Pair: tax amount exceeds amount');
            TransferHelper.safeTransfer(equivalent, IFactory(factory).feeToSetter(), tax);
            taxOf[tx.origin] += tax;
        }

        // To avoid stack too deep errors
        _amountToken = amountToken;
        uint256 _amountEquivalent2 = _amountEquivalent;
        address _to = to;
        TransferHelper.safeTransfer(equivalent, _to, _amountEquivalent2);
        TransferHelper.safeTransfer(token, _to, amountToken);
        balanceEquivalent = IERC20(equivalent).balanceOf(address(this));
        balanceToken = IERC20(token).balanceOf(address(this));

        // when a user call remove liquidity, he will send liquidity to the pair first
        costOf[tx.origin] = costOf[tx.origin].sub(cost, 'Pair: cost exceeds original cost');
        IERC25(token).updateCost(tx.origin, amountEquivalent.mul(1e18));

        // To avoid stack too deep errors
        uint112 reserveEquivalent2 = _reserveEquivalent;
        uint112 reserveToken2 = _reserveToken;
        _update(balanceEquivalent, balanceToken, reserveEquivalent2, reserveToken2);
        emit Burn(msg.sender, _amountEquivalent2, amountToken, _to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(
        uint256 amountEquivalentOut,
        uint256 amountTokenOut,
        uint256 amountIn,
        address to
    ) external lock {
        require(msg.sender == IFactory(factory).router(), 'Pair: FORBIDDEN');
        require(amountEquivalentOut > 0 || amountTokenOut > 0, 'Pair: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserveEquivalent, uint112 _reserveToken, ) = getReserves(); // gas savings
        require(
            amountEquivalentOut < _reserveEquivalent && amountTokenOut < _reserveToken,
            'Pair: INSUFFICIENT_LIQUIDITY'
        );

        uint256 balanceEquivalent;
        uint256 balanceToken;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _tokenEquivalent = equivalent;
            address _token = token;
            require(to != _tokenEquivalent && to != _token, 'Pair: INVALID_TO');

            uint256 cost;

            if (amountTokenOut > 0) {
                TransferHelper.safeTransfer(_token, to, amountTokenOut); // optimistically transfer tokens
                cost = amountIn.mul(1e18);
                IERC25(token).updateCost(tx.origin, cost);
            }

            if (amountEquivalentOut > 0) {
                cost = IERC25(token).costOf(tx.origin, amountIn);
                uint256 _cost = cost.div(1e18);
                uint256 _amountEquivalentOut1 = amountEquivalentOut; // stack too deep error
                uint256 tax = NoneLibrary.getTax(token, _cost, _amountEquivalentOut1);
                if (tax > 0) {
                    totalTax = totalTax.add(tax);
                    TransferHelper.safeTransfer(_tokenEquivalent, IFactory(factory).feeToSetter(), tax);
                    taxOf[tx.origin] += tax;
                }

                uint256 _amountEquivalentOut = _amountEquivalentOut1.sub(tax, 'Pair: tax exceeds amountEquivalentOut');
                TransferHelper.safeTransfer(_tokenEquivalent, to, _amountEquivalentOut); // optimistically transfer tokens
            }

            balanceEquivalent = IERC20(_tokenEquivalent).balanceOf(address(this));
            balanceToken = IERC20(_token).balanceOf(address(this));
        }

        uint256 amountEquivalentIn = balanceEquivalent > _reserveEquivalent - amountEquivalentOut
            ? balanceEquivalent - (_reserveEquivalent - amountEquivalentOut)
            : 0;
        uint256 amountTokenIn = balanceToken > _reserveToken - amountTokenOut
            ? balanceToken - (_reserveToken - amountTokenOut)
            : 0;
        require(amountEquivalentIn > 0 || amountTokenIn > 0, 'Pair: INSUFFICIENT_INPUT_AMOUNT');

        _update(balanceEquivalent, balanceToken, _reserveEquivalent, _reserveToken);
        emit Swap(msg.sender, amountEquivalentIn, amountTokenIn, amountEquivalentOut, amountTokenOut, to);
    }

    // force reserves to match balances
    function sync() external lock {
        _update(
            IERC20(equivalent).balanceOf(address(this)),
            IERC20(token).balanceOf(address(this)),
            reserveEquivalent,
            reserveToken
        );
    }
}
