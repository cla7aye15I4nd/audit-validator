// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

import '../interfaces/IFactory.sol';
import '../interfaces/IERC25.sol';
import './Pair.sol';
import '../libraries/Ownable.sol';

contract Factory is IFactory, Ownable {
    address public override feeTo;
    address public override feeToSetter;
    address public override router;

    mapping(address => address) public override getPair;
    address[] public override allPairs;

    event PairCreated(address indexed equivalent, address indexed token, address pair, uint256);

    constructor(address _feeToSetter, address _feeTo) Ownable(msg.sender) {
        feeToSetter = _feeToSetter;
        feeTo = _feeTo;
    }

    function setRouter(address _router) external override onlyOwner {
        router = _router;
    }

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    function createPair(address token) external override returns (address pair) {
        address equivalent = IERC25(token).equivalent();
        require(token != equivalent, 'Factory: IDENTICAL_ADDRESSES');
        require(token != address(0), 'Factory: ZERO_ADDRESS');
        require(getPair[token] == address(0), 'Factory: PAIR_EXISTS'); // single check is sufficient

        Pair newPair = new Pair();
        Pair(newPair).initialize(equivalent, token);
        pair = address(newPair);
        getPair[token] = pair;
        allPairs.push(pair);
        emit PairCreated(equivalent, token, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, 'Factory: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, 'Factory: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
