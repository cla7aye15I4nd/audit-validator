// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

import '../interfaces/IERC20.sol';
import '../libraries/SafeMath.sol';
import '../libraries/Ownable.sol';
import './ERC20.sol';

contract ERC25 is ERC20, Ownable {
    using SafeMath for uint256;

    address public equivalent;
    uint256 public initPrice;
    uint8 public taxRate;
    address public pair;

    mapping(address => uint256) private _costs;

    event TransferCost(address indexed from, address indexed to, uint256 cost);

    // _initPrice is the price of ERC25 token to anchor token in 1 ETH, 1 ETH =0.003 USDT(decimal is 8), then initPrice is 300000.
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _equivalent,
        uint256 _initPrice,
        uint8 _taxRate
    ) Ownable(msg.sender) ERC20(_name, _symbol, _decimals) {
        require(_equivalent != address(0), 'ERC25: _equivalent is zero address');
        equivalent = _equivalent;
        initPrice = _initPrice;
        taxRate = _taxRate;
    }

    function initCost(address account) internal returns (bool) {
        uint256 balance = balanceOf(account);
        if (_costs[account] == 0 && balance > 0) {
            _costs[account] = balance.mul(initPrice);
        }

        return true;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        transferCost(msg.sender, recipient, amount);
        super.transfer(recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        transferCost(sender, recipient, amount);
        super.transferFrom(sender, recipient, amount);
        return true;
    }

    function costOf(address account, uint256 amount) public view returns (uint256) {
        uint256 balance = balanceOf(account);
        if (balance == 0) return 0;
        uint256 cost = _costs[account];
        return amount.mul(cost).div(balance);
    }

    function transferCost(
        address sender,
        address recipient,
        uint256 amount
    ) private returns (bool) {
        uint256 cost = costOf(sender, amount);
        _transferCost(sender, recipient, cost);
        return true;
    }

    function _transferCost(
        address sender,
        address recipient,
        uint256 cost
    ) internal returns (bool) {
        _costs[sender] = _costs[sender].sub(cost, 'ERC25: cost amount exceeds sender cost');
        if (sender == pair) return true; // pair updates cost only in updateCost, not here
        _costs[recipient] = _costs[recipient].add(cost);

        emit TransferCost(sender, recipient, cost);
        return true;
    }

    function setTaxRate(uint8 _taxRate) public onlyOwner returns (bool) {
        taxRate = _taxRate;
        return true;
    }

    // if the user get token, then add cost. otherwise then sub the cost
    function updateCost(address _account, uint256 _cost) external onlyPair returns (bool) {
        _costs[_account] = _costs[_account].add(_cost);
        return true;
    }

    function setPair(address _pair) public onlyOwner returns (bool) {
        pair = _pair;
        return true;
    }

    modifier onlyPair() {
        require(msg.sender == pair, 'ERC25: PAIR ONLY!');
        _;
    }
}
