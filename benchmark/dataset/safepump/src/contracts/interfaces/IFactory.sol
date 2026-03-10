// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

interface IFactory {
    event PairCreated(address indexed token, address pair, uint256);

    function router() external view returns (address);

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(address token) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address token) external returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
    
    function setRouter(address) external;
}
