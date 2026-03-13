// SPDX-License-Identifier: GNU GPLv3
pragma solidity >=0.8.0 <0.9.0;

interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}
interface IERC20Metadata is IBEP20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}
library Address {
    function sendValue(
        address payable recipient,
        uint256 amount
    ) internal returns (bool) {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        (bool success, ) = recipient.call{value: amount}("");
        return success; // always proceeds
    }
}
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */

library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}
interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}

interface IUniswapV2Pair {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function Trade0CumulativeLast() external view returns (uint256);

    function Trade1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function _burn(
        address to
    ) external returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

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
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

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

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);

    function getAmountsIn(
        uint256 amountOut,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract Trader is Context, IBEP20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    address DEAD = 0x000000000000000000000000000000000000dEaD; // dead address
    address ZERO = 0x0000000000000000000000000000000000000000; // zero address
    address TEMPORARY_LIQUIDITY_OWNER =
        0x0e65120907dA1469F93ca9B382EaDEffa595ed0f; // temporary liquidity owner
    address ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // PCS V2 Router
    address PINK_LOCK = 0x407993575c91ce7643a4d4cCACc9A98c36eE1BBE; // PinkLock
    address FEE_RECEIVER = 0x4Bc1AaF139b3d36Dd64d8f063C81054A9E8D5fb0; // Fee receiver
    uint256 FEE_MULTIPLIER = 10000; // 100%

    // Trader token contract

    // Name: Trader
    // Symbol: TDE
    // Total Supply: 1,000,000 TDE
    // Decimals: 9

    // TDE initial distribution
    string constant _name = "Trader";
    string constant _symbol = "TDE";
    uint8 constant _decimals = 9;
    uint256 decimalMultiplier = 10 ** _decimals;
    uint256 _totalSupply = 1000000 * decimalMultiplier;

    // wallets
    address[] private initialAddresses = [
        // team 20%
        0xAB577bf27Ea501B0113348045A40E8450E5b0B77,
        0x4D53c8Cb64a44fC2200D3163062D74e8188635B5,
        0xCdC6e480D027ccdC8BaDE183da24Ad5E638aA689,
        0xa501Cc21F5168def6Bb545753Db49dfa94e799dD,
        0x2A58D994F34a45474240ea7678209CE2D1Dec589,
        // future listing 20%
        0x4cfE317De785d21fFEa7f40A11229d182beC0396,
        0x57cbb8c9b02c922d87Ed8330D6DA0B3a9d76EcF2,
        0x0C1B009Fcf041393944E9235692b580fd097A7d7,
        0x3E5f421B27F80E2A26c9470e21bdBEB5c254573F,
        0xB96EBF5579Caf2736a487334b96f2727A674421f,
        // airdrop 10%
        0x2C2Bb5002c9386D0375c6982588B4AEaCdb3A833,
        0xAaF10217232cD48C98648E0a156c735Ac4421C7a,
        0x452aA59343fF2E6D5dbAB672f3e41F7Db62Ff32A,
        // ITrade
        0x64B6fF18411a5691897EbaAD9f562c7022F7A887,
        0x3833D10ee11D133c422a8592fa9d8704f4EAabd7,
        0x9887ecFb7E0Ff7aB79d0ef9c15eD3DDc23E76370,
        0xc02b86132288f8CC905e944fBaba21372930f77E,
        0x399d4AD344551A416CECBB73cc89528219AcaDB6,
        // Burn
        DEAD,
        // Liquidity
        TEMPORARY_LIQUIDITY_OWNER
    ];
    // amounts
    uint256[] private initialAmounts = [
        // team 20%
        39500 * decimalMultiplier,
        39500 * decimalMultiplier,
        41000 * decimalMultiplier,
        40000 * decimalMultiplier,
        40000 * decimalMultiplier,
        // future listing 20%
        40000 * decimalMultiplier,
        40000 * decimalMultiplier,
        40000 * decimalMultiplier,
        40000 * decimalMultiplier,
        40000 * decimalMultiplier,
        // airdrop 10%
        40000 * decimalMultiplier,
        40000 * decimalMultiplier,
        20000 * decimalMultiplier,
        // ITrade
        100000 * decimalMultiplier,
        45000 * decimalMultiplier,
        45000 * decimalMultiplier,
        45000 * decimalMultiplier,
        46000 * decimalMultiplier,
        // Burn
        40000 * decimalMultiplier,
        // Liquidity
        179000 * decimalMultiplier
    ];

    // TDE will have 3 stages in the launch
    // 1. Owners : 2 wallets will have the right to buy TDE during 30 minutes
    // 2. Partners : 20 wallets will have the right to buy TDE during 1h and 30 minutes
    // 3. Concil : 6 wallet will have the right to buy TDE during 1h

    uint256 public startTime;
    uint256 public stageOneDuration = 20 minutes;
    uint256 public stageTwoDuration = 90 minutes;
    uint256 public stageThreeDuration = 30 minutes;

    // 1. Owners
    address[] private owners = [
        0xb322b1CAfA76521f5C1a76751aBf4F39704Ecea5,
        0xB04dB0547223723845EEf4aDc6826263cD4CC69B,
        address(this),
        address(owner())
    ];
    address[] private partners = [
        0xc0Bb6f5d30B67Eddc4c03D6a22E1F021Be988057,
        0x081e2ffeb23c93a4db27FCD935d2C7057A2f05Ab,
        0xeF307A980B27Bac9F829C3a61feCF8eed2F220B4,
        0xb8759Dd256056d744d4a65c22c14a390F7aD064b,
        0x0280E29D9987597102626602d2a42066f08E384e,
        0xad9A5A4965a03B3DF4C9d80935962275f9a59b7c,
        0x0EfA7753Bf383E6733301Fad7bE75Df0e3604B60,
        0x5c8833773E1f73F76F939fc0815Ad4dfd74B4DE9,
        0xEf77e2Ed8C147eA62303957792Fd8FDc5cc21165,
        0x280Ceb09F83372cF3fE8d0572815bAc6DF4bD53B,
        0xBb5E5d9a01509D06a56FFeCCB80dA7d16F2Af740,
        0x8db3bc5940Ab96DCFCf9e771d1FFf4a761779Eb0,
        0xc1acE4F238e8bcEF759Db354d2Ad9120AFDccFc2,
        0x5839a53cf9cb9090aF597A53c18521eFBFb2B557,
        0xceBe188225F1e123b6989133367bBfd34639f8A4,
        0x573e641Fae8D3c6be7fB0D251f7f3CfD83c064fA,
        0xD2030499E63ca37792aA5c842DaF38ebe7E58863,
        0x1084C43C042C0D41dd5Bc271E9DaAe65E66F37a4,
        0x0395DA133C13De07c8722b35d92d6d027B1c5Ee0,
        0x00a185209Ddcd1619b86c0C42d0ee025f0E51956,
        address(this),
        address(owner())
    ];
    address[] private concil = [
        0xc0Bb6f5d30B67Eddc4c03D6a22E1F021Be988057,
        0x4ef22Fc892147d20a39F2C81A31a4E1d5b29236f,
        0x5a7C81DdDb58fC997117416d85A65839f5D603EF,
        0x480e7C31C275D06ee9026Ca9C8a240f5e6a74777,
        0xf317939153B079b3e78E4419d914adaA8C9e1e2E,
        0xcc0c36a8844b1F1E7eb9c011F62338C3e4259C25,
        address(this),
        address(owner())
    ];

    // STANDARD FEES
    uint256 public standardBuyFee = 1000;
    uint256 public standardSellFee = 1000;
    uint256 public standardTransferFee = 1000;

    // WHALE FEES
    uint256 public whaleSellFee = 2000;
    uint256 public whaleTransferFee = 2000;

    // WHALE TRANSACTION
    uint256 public whaleTx = 2500;
    uint256 public whaleTransactionAmount = whaleTx * decimalMultiplier;

    // REQUIRED TOKENS TO SWAP
    uint256 amountToSwap = 500;
    uint256 swapTokensAtAmount = amountToSwap * decimalMultiplier;

    IUniswapV2Router02 public uniswapV2Router;

    address public uniswapV2Pair;

    bool public tradingOpen = true;
    bool inSwap;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isBlacklisted;
    mapping(address => uint256) _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }
    receive() external payable {}
    constructor() {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(ROUTER);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;

        _approve(address(this), ROUTER, type(uint256).max);
        _approve(address(this), FEE_RECEIVER, type(uint256).max);
        transferOwnership(TEMPORARY_LIQUIDITY_OWNER);

        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[owner()] = true;

        _isExcludedFromFees[0x64B6fF18411a5691897EbaAD9f562c7022F7A887] = true;
        _isExcludedFromFees[0x3833D10ee11D133c422a8592fa9d8704f4EAabd7] = true;
        _isExcludedFromFees[0x9887ecFb7E0Ff7aB79d0ef9c15eD3DDc23E76370] = true;
        _isExcludedFromFees[0xc02b86132288f8CC905e944fBaba21372930f77E] = true;
        _isExcludedFromFees[0x399d4AD344551A416CECBB73cc89528219AcaDB6] = true;

        DistributeInitialAmounts();
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] - subtractedValue
        );
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function DistributeInitialAmounts() private {
        startTime = block.timestamp;
        tradingOpen = true;

        uint256[] memory amounts = initialAmounts;
        address[] memory addresses = initialAddresses;

        require(
            addresses.length == amounts.length,
            "ERC20: addresses and tokens length mismatch"
        );
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount = totalAmount.add(amounts[i]);
        }
        require(
            totalAmount == _totalSupply,
            "ERC20: total amount does not match total supply"
        );
        for (uint256 i = 0; i < addresses.length; i++) {
            _balances[addresses[i]] = amounts[i];
            emit Transfer(address(this), addresses[i], amounts[i]);
        }
    }

    function tradingStatus(bool _status) public onlyOwner {
        tradingOpen = _status;
    }

    function swapTokensForBNB(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            FEE_RECEIVER,
            block.timestamp
        );
    }
    function swapAndLiquify() private swapping {
        // all BNB from the swap will be allocated to the FEE_RECEIVER wallet

        uint256 contractTokenBalance = balanceOf(address(this));
        if (contractTokenBalance >= swapTokensAtAmount) {
            // only swap for amounts greater than 500 TDE
            swapTokensForBNB(swapTokensAtAmount);
        }

        uint256 contractBNBBalance = address(this).balance;
        if (contractBNBBalance > 0) {
            // send all BNB to the FEE_RECEIVER wallet
            payable(FEE_RECEIVER).transfer(contractBNBBalance);
        }
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(tradingOpen, "Trading is not open");
        require(!_isBlacklisted[sender], "Blacklisted SENDER");
        require(!_isBlacklisted[recipient], "Blacklisted RECIPIENT");
        require(amount > 0, "Transfer amount must be greater than zero");
        // TRADING STATUS

        if (isExcludedFromFees(sender) || isExcludedFromFees(recipient)) {
            _balances[sender] = _balances[sender].sub(
                amount,
                "ERC20: transfer amount exceeds balance"
            );
            _balances[recipient] = _balances[recipient].add(amount);
            emit Transfer(sender, recipient, amount);
        } else {
            // WHITELISTING
            if (stageOneActive()) {
                require(
                    isStageOneParticipant(recipient),
                    "Not in stage one whitelist"
                );
            } else if (stageTwoActive()) {
                require(
                    isStageTwoParticipant(recipient),
                    "Not in stage two whitelist"
                );
            } else if (stageThreeActive()) {
                require(
                    isStageThreeParticipant(recipient),
                    "Not in stage three whitelist"
                );
            } else {
                require(
                    isWhiteListStageFinished(),
                    "Whitelist stage not finished"
                );
            }

            // FEES

            if (isBuy(sender, recipient)) {
                uint256 buyFee = amount.mul(standardBuyFee).div(FEE_MULTIPLIER);
                uint256 amountToHolder = amount.sub(
                    buyFee,
                    "Buy fee exceeds amount"
                );
                _balances[sender] = _balances[sender].sub(
                    amount,
                    "ERC20: transfer amount exceeds balance"
                );
                _balances[recipient] = _balances[recipient].add(amountToHolder);
                _balances[address(this)] = _balances[address(this)].add(buyFee);

                emit Transfer(sender, recipient, amountToHolder);
                emit Transfer(sender, address(this), buyFee);
            }

            if (isSell(sender, recipient)) {
                if (shouldChargeWhaleFee(amount)) {
                    uint256 sellFee = amount.mul(whaleSellFee).div(
                        FEE_MULTIPLIER
                    );
                    uint256 amountToPair = amount.sub(
                        sellFee,
                        "Sell fee exceeds amount"
                    );
                    _balances[sender] = _balances[sender].sub(
                        amount,
                        "ERC20: transfer amount exceeds balance"
                    );
                    _balances[recipient] = _balances[recipient].add(
                        amountToPair
                    );
                    _balances[address(this)] = _balances[address(this)].add(
                        sellFee
                    );

                    emit Transfer(sender, recipient, amountToPair);
                    emit Transfer(sender, address(this), sellFee);
                } else {
                    uint256 sellFee = amount.mul(standardSellFee).div(
                        FEE_MULTIPLIER
                    );
                    uint256 amountToPair = amount.sub(
                        sellFee,
                        "Sell fee exceeds amount"
                    );
                    _balances[sender] = _balances[sender].sub(
                        amount,
                        "ERC20: transfer amount exceeds balance"
                    );
                    _balances[recipient] = _balances[recipient].add(
                        amountToPair
                    );
                    _balances[address(this)] = _balances[address(this)].add(
                        sellFee
                    );

                    emit Transfer(sender, recipient, amountToPair);
                    emit Transfer(sender, address(this), sellFee);
                }
            }

            if (isTransfer(sender, recipient)) {
                if (shouldChargeWhaleFee(amount)) {
                    uint256 transferFee = amount.mul(whaleTransferFee).div(
                        FEE_MULTIPLIER
                    );
                    uint256 amountToRecipient = amount.sub(transferFee);
                    _balances[sender] = _balances[sender].sub(
                        amount,
                        "ERC20: transfer amount exceeds balance"
                    );
                    _balances[recipient] = _balances[recipient].add(
                        amountToRecipient
                    );
                    _balances[address(this)] = _balances[address(this)].add(
                        transferFee
                    );

                    emit Transfer(sender, recipient, amountToRecipient);
                    emit Transfer(sender, address(this), transferFee);
                } else {
                    uint256 transferFee = amount.mul(standardTransferFee).div(
                        FEE_MULTIPLIER
                    );
                    uint256 amountToRecipient = amount.sub(transferFee);
                    _balances[sender] = _balances[sender].sub(
                        amount,
                        "ERC20: transfer amount exceeds balance"
                    );
                    _balances[recipient] = _balances[recipient].add(
                        amountToRecipient
                    );
                    _balances[address(this)] = _balances[address(this)].add(
                        transferFee
                    );

                    emit Transfer(sender, recipient, amountToRecipient);
                    emit Transfer(sender, address(this), transferFee);
                }
            }
        }

        // SWAP AND LIQUIFY

        if (!inSwap && sender != uniswapV2Pair) {
            swapAndLiquify();
        }
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function isBuy(
        address sender,
        address recipient
    ) private view returns (bool) {
        return sender == uniswapV2Pair && recipient != uniswapV2Pair;
    }

    function isSell(
        address sender,
        address recipient
    ) private view returns (bool) {
        return sender != uniswapV2Pair && recipient == uniswapV2Pair;
    }

    function isTransfer(
        address sender,
        address recipient
    ) private view returns (bool) {
        return sender != uniswapV2Pair && recipient != uniswapV2Pair;
    }

    function shouldChargeWhaleFee(uint256 amount) private view returns (bool) {
        return amount > whaleTransactionAmount;
    }

    function stageOneActive() public view returns (bool) {
        return
            block.timestamp >= startTime &&
            block.timestamp <= startTime + stageOneDuration;
    }
    function stageTwoActive() public view returns (bool) {
        return
            block.timestamp >= startTime + stageOneDuration &&
            block.timestamp <= startTime + stageOneDuration + stageTwoDuration;
    }

    function stageThreeActive() public view returns (bool) {
        return
            block.timestamp >=
            startTime + stageOneDuration + stageTwoDuration &&
            block.timestamp <=
            startTime +
                stageOneDuration +
                stageTwoDuration +
                stageThreeDuration;
    }

    function isStageOneParticipant(address _holder) public view returns (bool) {
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == _holder) {
                return true;
            }
        }
        return false;
    }

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
        uint256 contractBNBBalance = address(this).balance;
        payable(FEE_RECEIVER).transfer(contractBNBBalance);
    }

    function recoverTokens(address _tokenAddress) external onlyOwner {
        IBEP20(_tokenAddress).transfer(
            owner(),
            IBEP20(_tokenAddress).balanceOf(address(this))
        );
    }

    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
    }

    function processSwapAndLiquify() external onlyOwner {
        swapAndLiquify();
    }
}