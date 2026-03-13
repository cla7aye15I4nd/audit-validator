// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../src/QueueLib.sol";
import "../src/RedBlackTreeLib.sol";
import "./MyTokenA.sol";
import "./MyTokenC.sol";
import "./PairLibImpl.sol";

import "./PairLibTest.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract PairLibTest2 is PairLibTest {
    function setUp() public override {
        tokenA = new MyTokenA(INITIAL_SUPPLY);
        tokenB = new MyTokenC(INITIAL_SUPPLY);

        pair = new PairLibImpl(address(tokenA), address(tokenB));

        trader1 = makeAddr("trader1");
        trader2 = makeAddr("trader2");
        trader3 = makeAddr("trader3");

        tokenA.transfer(trader1, INITIAL_TRANSFER);
        tokenB.transfer(trader2, INITIAL_TRANSFER);

        price = 100 * 1e18;
        quantity = 10;
        nonce = 1;
        expired = block.timestamp + 1 days;

        vm.startPrank(trader1);
        tokenA.approve(address(pair), APPROVAL_AMOUNT);
        vm.stopPrank();

        vm.startPrank(trader2);
        tokenB.approve(address(pair), APPROVAL_AMOUNT);
        vm.stopPrank();
    }
}
