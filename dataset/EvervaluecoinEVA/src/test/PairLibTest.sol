// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/QueueLib.sol";
import "../src/RedBlackTreeLib.sol";
import "forge-std/console.sol";
import "./MyTokenA.sol";
import "./MyTokenB.sol";

import "./PairLibImpl.sol";
import "../src/PairLib.sol";

contract PairLibTest is Test {
    PairLibImpl pair;

    // Tokens
    ERC20 tokenA;
    ERC20 tokenB;

    // Addresses
    address trader1;
    address trader2;
    address trader3;

    // Constants
    uint256 constant INITIAL_SUPPLY = 100000000000000000000 * 1e18;
    uint256 constant INITIAL_TRANSFER = 1000000000000000000000000000000;
    uint256 constant APPROVAL_AMOUNT = 100000000000000000000 * 1e18;

    // Test data
    uint256 price;
    uint256 quantity;
    uint256 nonce;
    uint256 expired;

    function setUp() public virtual {
        tokenA = new MyTokenA(INITIAL_SUPPLY);
        tokenB = new MyTokenB(INITIAL_SUPPLY);

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

    function assertEqualArrays(uint256[50] memory actual, uint256[50] memory expected) internal {
        for (uint256 i = 0; i < 50; i++) {
            assertEq(actual[i], expected[i], string(abi.encodePacked("Array mismatch at index ", i)));
        }
    }

    //-------------------- ADD BUY ORDER TESTS ------------------------------
    function testAddBuyOrder_WithoutSellOrders() public {
        uint256 balanceContractInitial = tokenB.balanceOf(address(pair));

        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader1, nonce);

        uint256 balanceContract = tokenB.balanceOf(address(pair));
        assertEq(balanceContract - balanceContractInitial, 1000, "Contract balance should increase by 1000");
        assertEq(pair.getFirstBuyOrders(), 100 * 10 ** 18, "Buy order should be stored at correct price");
    }

    function testAddBuyOrder_WithMatchingSellOrder() public {
        vm.prank(trader1);
        pair.addSellBaseToken(price, quantity, trader2, nonce);

        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader1, nonce);

        vm.expectRevert(PairLib.PL__BalanceNotEnoughForWithdraw.selector);
        pair.withdrawBalance(trader1, true);
        pair.withdrawBalance(trader1, false);

        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be completely matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be completely executed");
        assertEq(tokenB.balanceOf(trader1), 1000, "Trader1 should receive 1000 tokenB");
        assertEq(tokenA.balanceOf(trader2), 10, "Trader2 should receive 10 tokenA");
    }

    function testAddBuyOrder_WithMultipleMatchingSellOrders() public {
        vm.startPrank(trader1);
        pair.addSellBaseToken(price, 5, trader2, nonce);
        pair.addSellBaseToken(price, 5, trader2, nonce + 1);
        pair.addSellBaseToken(price, 5, trader2, nonce + 2);
        vm.stopPrank();

        vm.prank(trader2);
        pair.addBuyBaseToken(price, 15, trader1, nonce);

        pair.getTraderBalances(trader1);
        pair.getTraderBalances(trader2);
        pair.withdrawBalance(trader1, false);

        assertEq(pair.getFirstSellOrders(), 0, "All sell orders should be completely matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be completely executed");
        assertEq(tokenB.balanceOf(trader1), 1500, "Trader1 should receive 1500 tokenB");
        assertEq(tokenA.balanceOf(trader2), 15, "Trader2 should receive 15 tokenA");
    }

    function testAddBuyOrder_WithHigherPriceThanSellOrder() public {
        vm.prank(trader1);
        pair.addSellBaseToken(90 * 10 ** 18, quantity, trader2, nonce);

        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader1, nonce);

        pair.withdrawBalance(trader1, false);

        assertEq(pair.lastTradePrice(), 90 * 10 ** 18, "Last trade price should be 90");
        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be completely matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be completely executed");
        assertEq(tokenB.balanceOf(trader1), 900, "Trader1 should receive 900 tokenB");
        assertEq(tokenA.balanceOf(trader2), 10, "Trader2 should receive 10 tokenA");
    }

    function testAddBuyOrder_WithLowerPriceThanSellOrder() public {
        vm.prank(trader1);
        pair.addSellBaseToken(110 * 10 ** 18, quantity, trader2, nonce);

        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader1, nonce);

        //pair.withdrawBalance(trader1, false);

        assertEq(pair.getFirstSellOrders(), 110 * 10 ** 18, "Sell order should not be matched");
        assertEq(pair.getFirstBuyOrders(), 100 * 10 ** 18, "Buy order should be stored");
    }

    function testAddBuyOrder_WithPartialQuantity() public {
        vm.prank(trader1);
        pair.addSellBaseToken(price, 5, trader2, nonce);

        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader1, nonce);

        pair.withdrawBalance(trader1, false);

        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be completely matched");
        assertEq(pair.getFirstBuyOrders(), 100 * 10 ** 18, "Remaining buy order quantity should be stored");
        assertEq(tokenB.balanceOf(trader1), 500, "Trader1 should receive 500 tokenB");
        assertEq(tokenA.balanceOf(trader2), 5, "Trader2 should receive 5 tokenA");
    }

    function testAddBuyOrder_WithExcessQuantity() public {
        vm.prank(trader1);
        pair.addSellBaseToken(price, 15, trader2, nonce);

        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader1, nonce);

        pair.withdrawBalance(trader1, false);

        assertEq(pair.getFirstSellOrders(), price, "Remaining sell order should be stored at the same price");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be completely executed");
    }

    function testAddBuyOrder_WithMultipleSellOrdersAtDifferentPrices() public {
        vm.startPrank(trader1);
        pair.addSellBaseToken(90 * 1e18, 5, trader2, nonce);
        pair.addSellBaseToken(price, 5, trader2, nonce + 1);
        vm.stopPrank();

        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader1, nonce);

        pair.withdrawBalance(trader1, false);

        assertEq(pair.getFirstSellOrders(), 0, "All sell orders should be matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be completely executed");
    }

    function testAddBuyOrder_WithMultipleSellOrdersAtDifferentPricesRevertInvalidPaymentAmount() public {
        vm.startPrank(trader1);
        pair.addSellBaseToken(90e18, 10, trader2, nonce);
        pair.addSellBaseToken(price, 10, trader2, nonce + 1);
        vm.stopPrank();

        vm.prank(trader2);
        vm.expectRevert(PairLib.PL__OrderBelowMinimum.selector);
        pair.addBuyBaseToken(100, 8, trader1, nonce);

        pair.getTraderBalances(trader1);
        assertEq(pair.getFirstSellOrders(), 90e18, "All sell orders should be matched");

        //pair.withdrawBalance(trader1, false);
    }


    function testAddBuyOrderPartial_WithMultipleSellOrdersAtDifferentPricesRevertInvalidPaymentAmount() public {
        vm.startPrank(trader1);
        pair.addSellBaseToken(100*1e18, 10, trader2, nonce + 1);
        vm.stopPrank();

        vm.prank(trader2);
        pair.addBuyBaseToken(100*1e18, 5, trader1, nonce + 2);

        pair.withdrawBalance(trader1, false);
    }
    // -------------------- ADD SELL ORDER TESTS ------------------------------

    function testAddSellOrder_WithoutBuyOrders() public {
        assertEq(pair.getLastBuyOrders(), 0, "Buy orders tree should be empty initially");

        uint256 price = 100e18;
        uint256 quantity = 10;

        vm.prank(trader1);
        pair.addSellBaseToken(price, quantity, trader2, nonce);

        assertEq(pair.getFirstSellOrders(), price, "Sell order should be added correctly");
    }

    function testAddSellOrder_WithMatchingBuyOrder() public {
        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader1, nonce);

        vm.prank(trader1);
        pair.addSellBaseToken(price, quantity, trader2, nonce);

        pair.withdrawBalance(trader2, true);

        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be fully matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be fully executed");
        assertEq(tokenB.balanceOf(trader1), 990, "Trader1's tokenB balance should be correct");
        assertEq(tokenA.balanceOf(trader2), 10, "Trader2's tokenA balance should be correct");
    }

    function testAddSellOrder_WithMultipleMatchingBuyOrders() public {
        vm.startPrank(trader2);
        pair.addBuyBaseToken(price, 5, trader1, nonce);
        pair.addBuyBaseToken(price, 5, trader1, nonce + 1);
        pair.addBuyBaseToken(price, 5, trader1, nonce + 2);
        vm.stopPrank();

        vm.prank(trader1);
        pair.addSellBaseToken(price, 15, trader2, nonce);

        pair.withdrawBalance(trader2, true);

        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be fully matched");
        assertEq(pair.getFirstBuyOrders(), 0, "All buy orders should be fully executed");
        assertEq(tokenB.balanceOf(trader1), 1485, "Trader1's tokenB balance should be correct");
        assertEq(tokenA.balanceOf(trader2), 15, "Trader2's tokenA balance should be correct");
    }

    function testAddSellOrder_WithLowerPriceMatchingBuyOrder() public {
        vm.prank(trader2);
        pair.addBuyBaseToken(110 * 1e18, quantity, trader1, nonce);

        uint256 lowerPrice = 100 * 1e18;
        vm.prank(trader1);
        pair.addSellBaseToken(lowerPrice, quantity, trader2, nonce);

        pair.withdrawBalance(trader2, true);

        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be fully executed");
        assertEq(pair.getFirstSellOrders(), 0, "No pending sell orders should remain");
    }

    function testAddSellOrder_WithHigherPriceNoMatching() public {
        vm.prank(trader2);
        pair.addBuyBaseToken(90 * 1e18, quantity, trader1, nonce);

        uint256 higherPrice = 100 * 1e18;
        vm.prank(trader1);
        pair.addSellBaseToken(higherPrice, quantity, trader2, nonce);

        pair.getTraderBalances(trader2);
        pair.getTraderBalances(trader1);
        //pair.withdrawBalance(trader2, true);

        assertEq(pair.getFirstBuyOrders(), 90 * 1e18, "Buy order should remain unmatched");
        assertEq(pair.getFirstSellOrders(), higherPrice, "Sell order should be added without execution");
    }

    function testAddSellOrder_WithPartialQuantity() public {
        vm.prank(trader2);
        pair.addBuyBaseToken(price, 10, trader2, nonce);

        vm.prank(trader1);
        pair.addSellBaseToken(price, 5, trader1, nonce);

        pair.withdrawBalance(trader2, true);

        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be completely matched");
        assertEq(pair.getFirstBuyOrders(), 100 * 10 ** 18, "Remaining buy order quantity should be stored");
        assertEq(tokenB.balanceOf(trader1), 495, "Trader1 should receive 500 tokenB");
        assertEq(tokenA.balanceOf(trader2), 5, "Trader2 should receive 5 tokenA");
    }

    function testAddSellOrder_WithPartialMatching() public {
        vm.prank(trader2);
        pair.addBuyBaseToken(price, 5, trader1, nonce);

        vm.prank(trader1);
        pair.addSellBaseToken(price, 10, trader2, nonce);

        pair.withdrawBalance(trader2, true);

        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be fully executed");
        assertEq(pair.getFirstSellOrders(), price, "Remaining sell order should be added");
        assertEq(tokenB.balanceOf(trader1), 495, "Trader1's tokenB balance should be correct");
        assertEq(tokenA.balanceOf(trader2), 5, "Trader2's tokenA balance should be correct");
        assertEq(tokenA.balanceOf(address(pair)), 5, "Contract's tokenA balance should be correct");
    }

    //-------------------- CANCEL ORDER ------------------------------

    function testCancelBuyOrder() public {
        uint256 initial_balance = tokenB.balanceOf(trader2);
        vm.prank(trader2);
        pair.addBuyBaseToken(price, 5, trader2, nonce);

        bytes32 _orderId = keccak256(abi.encodePacked(trader2, "buy", price, nonce));

        vm.prank(trader2);
        pair.getCancelOrder(_orderId);
        uint256 final_balance = tokenB.balanceOf(trader2);

        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should have been removed");
        assertEq(final_balance, initial_balance, "Token balance should remain unchanged after cancellation");
    }

    function testCancelSellOrder() public {
        uint256 initial_balance = tokenA.balanceOf(trader1);
        vm.prank(trader1);
        pair.addSellBaseToken(price, 10, trader1, nonce);

        bytes32 _orderId = keccak256(abi.encodePacked(trader1, "sell", price, nonce));

        vm.prank(trader1);
        pair.getCancelOrder(_orderId);
        uint256 final_balance = tokenA.balanceOf(trader1);

        assertEq(pair.getFirstSellOrders(), 0, "Sell order should have been removed");
        assertEq(final_balance, initial_balance, "Token balance should remain unchanged after cancellation");
    }

    function testCancelNonExistentOrder() public {
        bytes32 _orderId = keccak256(abi.encodePacked(trader1, "buy", price, nonce));

        vm.expectRevert(PairLib.PL__OrderIdDoesNotExist.selector);
        pair.getCancelOrder(_orderId);
    }

    function testCancelOrderAmongMultipleOrders() public {
        vm.startPrank(trader2);
        pair.addBuyBaseToken(price, 10, trader2, nonce);
        pair.addBuyBaseToken(price, 5, trader2, nonce + 1);
        vm.stopPrank();

        bytes32 _orderId1 = keccak256(abi.encodePacked(trader2, "buy", price, nonce));
        bytes32 _orderId2 = keccak256(abi.encodePacked(trader2, "buy", price, nonce + 1));

        assertEq(pair.getFirstOrderBuyByPrice(price), _orderId1, "First order should be orderId1");

        vm.prank(trader2);
        pair.getCancelOrder(_orderId1);

        assertEq(
            pair.getFirstOrderBuyByPrice(price),
            _orderId2,
            "Second order should move to the first position after cancellation"
        );
    }

    function testCancelOrderNotOwner() public {
        bytes32 orderId = keccak256(abi.encodePacked(trader2, "buy", price, nonce));

        vm.prank(trader2);
        pair.addBuyBaseToken(price, 10, trader2, nonce);

        vm.prank(trader1);
        vm.expectRevert(PairLib.PL__OrderDoesNotBelongToCurrentTrader.selector);
        pair.getCancelOrder(orderId);

        // Add an assertion to verify the order still exists
        assertEq(
            pair.getFirstOrderBuyByPrice(price), orderId, "Order should still exist after failed cancellation attempt"
        );
    }

    function testCancelQuoteBuyOrder() public {
        uint256 _price = 22983;
        uint256 initial_balance = tokenB.balanceOf(trader2);
        vm.prank(trader2);
        pair.addBuyBaseToken(_price, 10_000e18, trader2, nonce);

        vm.prank(trader1);
        pair.addSellBaseToken(_price, 9999_99999915e10, trader1, nonce);

        bytes32 _orderId = keccak256(abi.encodePacked(trader2, "buy", _price, nonce));

        pair.getOrderById(_orderId);

        vm.prank(trader2);
        pair.getCancelOrder(_orderId);

        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should have been removed");
    }

    //-------------------- GET TRADER ORDERS ------------------------------

    function testGetTraderOrdersWithMultipleOrders() public {
        bytes32 orderId1 = keccak256(abi.encodePacked(trader2, "buy", price, nonce));
        bytes32 orderId2 = keccak256(abi.encodePacked(trader2, "buy", price, nonce + 1));

        vm.startPrank(trader2);
        pair.addBuyBaseToken(price, 1, trader2, nonce);
        pair.addBuyBaseToken(price, 2, trader2, nonce + 1);
        vm.stopPrank();

        bytes32[] memory orders = pair.getTraderOrders(trader2);

        assertEq(orders.length, 2, "Should return two orders");
        assertEq(orders[0], orderId1, "First order should match");
        assertEq(orders[1], orderId2, "Second order should match");
    }

    function testGetTraderOrdersWithNoOrders() public {
        bytes32[] memory orders = pair.getTraderOrders(trader2);
        assertEq(orders.length, 0, "Should return an empty array for trader with no orders");
    }

    function testGetTraderOrdersWithSingleOrder() public {
        bytes32 orderId = keccak256(abi.encodePacked(trader2, "buy", price, nonce));
        vm.prank(trader2);
        pair.addBuyBaseToken(price, 1, trader2, nonce);

        bytes32[] memory orders = pair.getTraderOrders(trader2);

        assertEq(orders.length, 1, "Should return a single order");
        assertEq(orders[0], orderId, "Returned order should match");
    }

    function testGetTraderOrdersForNonExistentTrader() public {
        bytes32[] memory orders = pair.getTraderOrders(address(0x1234));
        assertEq(orders.length, 0, "Should return an empty array for non-existent trader");
    }

    function testImmutabilityOfReturnedTraderOrdersArray() public {
        bytes32 orderId = keccak256(abi.encodePacked(trader2, "buy", price, nonce));
        vm.prank(trader2);
        pair.addBuyBaseToken(price, 1, trader2, nonce);

        bytes32[] memory orders = pair.getTraderOrders(trader2);
        bytes32 originalOrderId = orders[0];

        // Attempt to modify the returned array
        orders[0] = keccak256(abi.encodePacked(trader2, "sell", price + 100, nonce + 1));

        bytes32[] memory ordersAfterModification = pair.getTraderOrders(trader2);

        assertEq(ordersAfterModification[0], originalOrderId, "Modifying returned array should not affect storage");
    }

    //-------------------- GET ORDER BY ID ------------------------------
    function testGetExistingBuyOrderById() public {
        bytes32 orderId = keccak256(abi.encodePacked(trader2, "buy", price, nonce));

        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader2, nonce);

        OrderBookLib.Order memory result = pair.getOrderById(orderId);

        assertEq(result.price, price, "Order price should match");
        assertEq(result.quantity, quantity, "Order quantity should match");
    }

    function testGetExistingSellOrderById() public {
        bytes32 orderId = keccak256(abi.encodePacked(trader1, "sell", price, nonce));

        vm.prank(trader1);
        pair.addSellBaseToken(price, 10, trader1, nonce);

        OrderBookLib.Order memory result = pair.getOrderById(orderId);

        assertEq(result.price, price, "Order price should match");
        assertEq(result.quantity, 10, "Order quantity should match");
    }

    function testGetNonExistentOrderById() public {
        bytes32 orderId = keccak256(abi.encodePacked(trader1, "buy", price, nonce));

        vm.expectRevert(PairLib.PL__OrderIdDoesNotExist.selector);
        pair.getOrderById(orderId);
    }

    function testGetOrderWithInvalidId() public {
        bytes32 invalidOrderId = keccak256(abi.encodePacked(trader1, "invalid", price, nonce));

        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader1, nonce);

        vm.expectRevert();
        pair.getOrderById(invalidOrderId);
    }

    function testGetOrderForTraderWithoutOrders() public {
        bytes32 orderId = keccak256(abi.encodePacked(trader2, "buy", price, quantity));

        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader1, nonce);

        vm.expectRevert();
        pair.getOrderById(orderId);
    }

    function testMatchingSellBeforeBuyOrder() public {
        vm.startPrank(trader1);
        pair.addSellBaseToken(10 * 10 ** 18, 50, trader1, nonce);
        vm.stopPrank();

        vm.prank(trader2);
        pair.addBuyBaseToken(10 * 10 ** 18, 50, trader2, nonce);

        pair.withdrawBalance(trader1, false);

        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be fully matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be fully executed");
        assertEq(tokenB.balanceOf(trader1), 500, "Trader1 should receive 500 tokenB");
        assertEq(tokenA.balanceOf(trader2), 50, "Trader2 should receive 50 tokenA");
    }

    function testMatchingBuyBeforeSellOrder() public {
        vm.prank(trader2);
        pair.addBuyBaseToken(10 * 10 ** 18, 50, trader2, nonce);

        vm.startPrank(trader1);
        pair.addSellBaseToken(10 * 10 ** 18, 50, trader1, nonce);
        vm.stopPrank();

        pair.withdrawBalance(trader2, true);

        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be fully matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be fully executed");
        assertEq(tokenB.balanceOf(trader1), 495, "Trader1 should receive 500 tokenB");
        assertEq(tokenA.balanceOf(trader2), 50, "Trader2 should receive 50 tokenA");
    }

    function testMatchingOrdersWithSmallPrice() public {
        vm.startPrank(trader1);
        pair.addSellBaseToken(0.1 * 10 ** 18, 50, trader1, nonce);
        vm.stopPrank();

        vm.prank(trader2);
        pair.addBuyBaseToken(0.1 * 10 ** 18, 50, trader2, nonce);

        pair.withdrawBalance(trader1, false);

        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be fully matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be fully executed");
        assertEq(tokenB.balanceOf(trader1), 5, "Trader1 should receive 5 tokenB");
        assertEq(tokenA.balanceOf(trader2), 50, "Trader2 should receive 50 tokenA");
    }

    function testMatchingOrdersWithSmallPriceReverseOrder() public {
        vm.prank(trader2);
        pair.addBuyBaseToken(0.1 * 10 ** 18, 50, trader2, nonce);

        vm.startPrank(trader1);
        pair.addSellBaseToken(0.1 * 10 ** 18, 50, trader1, nonce);
        vm.stopPrank();

        pair.withdrawBalance(trader2, true);

        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be fully matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be fully executed");
        assertEq(tokenB.balanceOf(trader1), 4, "Trader1 should receive 5 tokenB");
        assertEq(tokenA.balanceOf(trader2), 50, "Trader2 should receive 50 tokenA");
    }

    function testEmptyOrderBook() public {
        uint256[50] memory topBuyPrices = pair.getTop50BuyPrices();
        uint256[50] memory topSellPrices = pair.getTop50SellPrices();

        assertEqualArrays(topBuyPrices, [uint256(0), 0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);
        assertEqualArrays(topSellPrices, [uint256(0), 0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);
    }

    function testOnePrice() public {
        vm.prank(trader2);
        pair.createOrder(true, 100 * 1e18, 10);
        vm.prank(trader1);
        pair.createOrder(false, 110 * 1e18, 10);

        uint256[50] memory topBuyPrices = pair.getTop50BuyPrices();
        uint256[50] memory topSellPrices = pair.getTop50SellPrices();

        assertEqualArrays(topBuyPrices, [uint256(100) * 1e18, 0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);
        assertEqualArrays(topSellPrices, [uint256(110) * 1e18, 0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);
    }

    function testTwoPrices() public {
        vm.startPrank(trader2);
        pair.createOrder(true, 100 * 1e18, 10);
        pair.createOrder(true, 90 * 1e18, 10);
        vm.stopPrank();
        vm.startPrank(trader1);
        pair.createOrder(false, 110 * 1e18, 10);
        pair.createOrder(false, 120 * 1e18, 10);
        vm.stopPrank();

        uint256[50] memory topBuyPrices = pair.getTop50BuyPrices();
        uint256[50] memory topSellPrices = pair.getTop50SellPrices();

        assertEqualArrays(topBuyPrices, [uint256(100) * 1e18, 90 * 1e18, 0 * 1e18,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);
        assertEqualArrays(topSellPrices, [uint256(110) * 1e18, 120 * 1e18, 0 * 1e18,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);
    }


    function testBuyOrdersDescendingOrder() public {
        vm.startPrank(trader2);
        pair.createOrder(true, 100 * 1e18, 10);
        pair.createOrder(true, 90 * 1e18, 10);
        pair.createOrder(true, 95 * 1e18, 10);
        vm.stopPrank();

        uint256[50] memory topBuyPrices = pair.getTop50BuyPrices();

        assertTrue(topBuyPrices[0] > topBuyPrices[1]);
        assertTrue(topBuyPrices[1] > topBuyPrices[2]);
    }

    function testSellOrdersAscendingOrder() public {
        vm.startPrank(trader1);
        pair.createOrder(false, 110e18, 10e18);
        pair.createOrder(false, 120e18, 10e18);
        pair.createOrder(false, 115e18, 10e18);
        vm.stopPrank();

        uint256[50] memory topSellPrices = pair.getTop50SellPrices();

        assertTrue(topSellPrices[0] < topSellPrices[1]);
        assertTrue(topSellPrices[1] < topSellPrices[2]);
    }

    function testLargeNumberOfOrders() public {
        uint256[50] memory buyPrices;
        uint256[50] memory sellPrices;
        for (uint256 i = 1; i <= 100; i++) {
            vm.prank(trader2);
            pair.createOrder(true, (i * 10) * 1e18, 10);

            vm.prank(trader1);
            pair.createOrder(false, (1000 + i * 10) * 1e18, 10);
        }

        // Llenar arrays esperados correctamente
        for (uint256 i = 0; i < 50; i++) {
            // Para compras: los 50 precios más altos (del 100 al 51)
            buyPrices[i] = ((100 - i) * 10) * 1e18;
            // Para ventas: los 50 precios más bajos (del 1 al 50)
            sellPrices[i] = (1000 + (i + 1) * 10) * 1e18;
        }

        uint256[50] memory topBuyPrices = pair.getTop50BuyPrices();
        uint256[50] memory topSellPrices = pair.getTop50SellPrices();

        assertEqualArrays(topBuyPrices, buyPrices);
        assertEqualArrays(topSellPrices, sellPrices);
    }

    function testEdgeCases() public {
        vm.startPrank(trader2);
        vm.expectRevert(stdError.arithmeticError);
        pair.createOrder(true, type(uint256).max, 10e12);
        vm.expectRevert(stdError.arithmeticError);
        pair.createOrder(true, type(uint256).max - 1, 10e12);
        vm.stopPrank();
        vm.startPrank(trader1);
        pair.createOrder(false, 1e10, 10e12);
        pair.createOrder(false, 2e10, 10e12);
        vm.stopPrank();

        uint256[50] memory topBuyPrices = pair.getTop50BuyPrices();
        uint256[50] memory topSellPrices = pair.getTop50SellPrices();
    }

    function testDuplicatePrices() public {
        vm.startPrank(trader2);
        pair.createOrder(true, 100 * 1e18, 10);
        pair.createOrder(true, 100 * 1e18, 20);
        pair.createOrder(true, 90 * 1e18, 30);
        vm.stopPrank();
        vm.startPrank(trader1);
        pair.createOrder(false, 110 * 1e18, 10);
        pair.createOrder(false, 110 * 1e18, 20);
        pair.createOrder(false, 120 * 1e18, 30);
        vm.stopPrank();

        uint256[50] memory topBuyPrices = pair.getTop50BuyPrices();
        uint256[50] memory topSellPrices = pair.getTop50SellPrices();

        assertEqualArrays(topBuyPrices, [uint256(100 * 1e18), 90 * 1e18, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);
        assertEqualArrays(topSellPrices, [uint256(110 * 1e18), 120 * 1e18, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);
    }

    function testUpdatedOrderBook() public {
        vm.startPrank(trader2);
        pair.createOrder(true, 100 * 1e18, 10);
        pair.createOrder(true, 90 * 1e18, 10);
        vm.stopPrank();
        vm.startPrank(trader1);
        pair.createOrder(false, 110 * 1e18, 10);
        pair.createOrder(false, 120 * 1e18, 10);
        vm.stopPrank();

        uint256[50] memory topBuyPrices = pair.getTop50BuyPrices();
        uint256[50] memory topSellPrices = pair.getTop50SellPrices();

        assertEqualArrays(topBuyPrices, [uint256(100) * 1e18, 90 * 1e18, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);
        assertEqualArrays(topSellPrices, [uint256(110) * 1e18, 120 * 1e18, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);

        vm.prank(trader2);
        pair.createOrder(true, 95 * 1e18, 10);
        vm.prank(trader1);
        pair.createOrder(false, 115 * 1e18, 10);

        topBuyPrices = pair.getTop50BuyPrices();
        topSellPrices = pair.getTop50SellPrices();

        assertEqualArrays(topBuyPrices, [uint256(100) * 1e18, 95 * 1e18, 90 * 1e18,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);
        assertEqualArrays(topSellPrices, [uint256(110) * 1e18, 115 * 1e18, 120 * 1e18,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0]);
    }

    function testGetPrice() public {
        // 1. Empty order book
        (uint256 emptyValue, uint256 emptyCount) = pair.getPrice(100 * 1e18, true);
        assertEq(emptyValue, 0);
        assertEq(emptyCount, 0);

        // Add some orders to the book
        addMockOrders();

        // 2. Price point exists with orders (buy order)
        (uint256 buyValue, uint256 buyCount) = pair.getPrice(95 * 1e18, true);
        assertEq(buyValue, 100);
        assertEq(buyCount, 1);

        // 3. Price point does not exist
        (uint256 nonExistentValue, uint256 nonExistentCount) = pair.getPrice(99 * 1e18, true);
        assertEq(nonExistentValue, 0);
        assertEq(nonExistentCount, 0);

        // 4. Price point is the first (highest for buy)
        (uint256 highestBuyValue, uint256 highestBuyCount) = pair.getPrice(100 * 1e18, true);
        assertEq(highestBuyValue, 201);
        assertEq(highestBuyCount, 2);

        // 5. Price point is in the middle of the order book
        (uint256 middleSellValue, uint256 middleSellCount) = pair.getPrice(105 * 1e18, false);
        assertEq(middleSellValue, 150);
        assertEq(middleSellCount, 1);

        // 6. Price point is the last (lowest for sell)
        (uint256 lowestSellValue, uint256 lowestSellCount) = pair.getPrice(102 * 1e18, false);
        assertEq(lowestSellValue, 100);
        assertEq(lowestSellCount, 1);

        // 7. Querying for buy orders
        (uint256 buyOrderValue, uint256 buyOrderCount) = pair.getPrice(95 * 1e18, true);
        assertEq(buyOrderValue, 100);
        assertEq(buyOrderCount, 1);

        // 8. Querying for sell orders
        (uint256 sellOrderValue, uint256 sellOrderCount) = pair.getPrice(110 * 1e18, false);
        assertEq(sellOrderValue, 201);
        assertEq(sellOrderCount, 2);
    }

    function addMockOrders() internal {
        // Add buy orders
        vm.startPrank(trader2);
        pair.createOrder(true, 100 * 1e18, 100);
        pair.createOrder(true, 100 * 1e18, 101);
        pair.createOrder(true, 95 * 1e18, 100);
        pair.createOrder(true, 90 * 1e18, 150);
        vm.stopPrank();

        // Add sell orders
        vm.startPrank(trader1);
        pair.createOrder(false, 102 * 1e18, 100);
        pair.createOrder(false, 105 * 1e18, 150);
        pair.createOrder(false, 110 * 1e18, 100);
        pair.createOrder(false, 110 * 1e18, 101);
        vm.stopPrank();
    }

    function testDisabledPair() public {
        pair.disable();
        vm.expectRevert(PairLib.PL__PairDisabled.selector);
        pair.createOrder(true, 100, 100);
        vm.expectRevert(PairLib.PL__PairDisabled.selector);
        pair.createOrder(false, 102, 100);
    }

    function testInvalidQuantity() public {
        vm.expectRevert(abi.encodeWithSelector(PairLib.PL__InvalidQuantity.selector, 0));
        pair.createOrder(true, 100 * 1e18, 0);
    }

    function testInvalidPaymentAmount() public {
        vm.expectRevert(abi.encodeWithSelector(PairLib.PL__OrderBelowMinimum.selector));
        pair.createOrder(true, 1, 10);
    }

    function testDuplicateId() public {
        vm.prank(trader2);
        pair.createOrder(true, 100 * 1e18, 5);
        vm.prank(trader2);
        vm.expectRevert(PairLib.PL__OrderIdAlreadyExists.selector);
        pair.createOrder(true, 100 * 1e18, 5);
    }

    //-------------------- ADD WITHDRAW BALANCE ------------------------------
    function testWithDrawBalance_WithMatchingSellOrder() public {
        vm.prank(trader1);
        pair.addSellBaseToken(price, quantity, trader1, nonce);

        vm.prank(trader2);
        pair.addBuyBaseToken(price, quantity, trader2, nonce);

        pair.withdrawBalance(trader1, false);

        PairLib.TraderBalance memory traderBalance = pair.getTraderBalances(trader1);

        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be completely matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be completely executed");
        assertEq(tokenB.balanceOf(trader1), 1000, "Trader1 should receive 1000 tokenB");
        assertEq(tokenA.balanceOf(trader2), 10, "Trader2 should receive 10 tokenA");
        assertEq(traderBalance.quoteTokenBalance, 0, "Trader1 should get 0 tokenB");
        assertEq(traderBalance.baseTokenBalance, 0, "Trader1 should get 0 tokenA");
    }

    function testWithDrawFeeBalance_WithMatchingSellOrder() public {
        vm.prank(trader1);
        pair.addSellBaseToken(price, 10 * 1e8, trader1, nonce);

        vm.prank(trader2);
        pair.addBuyBaseToken(price, 10 * 1e8, trader2, nonce);

        vm.prank(address(this));
        (uint256 feeBase, uint256 feeQuote)= pair.getFeeBalances();
//        vm.prank(address(this));
        vm.expectRevert(PairLib.PL__BalanceFeeNotEnoughForWithdraw.selector);
        pair.withdrawFeeBalance(false);

        pair.withdrawFeeBalance(true);

        pair.withdrawBalance(trader1,false);

        PairLib.TraderBalance memory traderBalance = pair.getTraderBalances(trader1);
//
        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be completely matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be completely executed");
        assertEq(tokenB.balanceOf(trader1), 10 * 1e8 * price / 1e18, "Trader1 should receive 1000 tokenB");
        assertEq(tokenA.balanceOf(trader2), 990000000, "Trader2 should receive 10 tokenA");
        assertEq(traderBalance.quoteTokenBalance, 0, "Trader1 should get 0 tokenB");
        assertEq(traderBalance.baseTokenBalance, 0, "Trader1 should get 0 tokenA");
    }

    function testWithDrawFeeBalance_WithMatchingBuyOrder() public {
        vm.prank(trader2);
        pair.addBuyBaseToken(price, 10 * 1e8, trader2, nonce);

        vm.prank(trader1);
        pair.addSellBaseToken(price, 10 * 1e8, trader1, nonce);

        vm.prank(address(this));
        (uint256 feeBase, uint256 feeQuote)= pair.getFeeBalances();

        vm.expectRevert(PairLib.PL__BalanceFeeNotEnoughForWithdraw.selector);
        pair.withdrawFeeBalance(true);

        pair.withdrawFeeBalance(false);

        vm.prank(trader2);
        pair.withdrawBalance(trader2,true);

        PairLib.TraderBalance memory traderBalance = pair.getTraderBalances(trader1);
//
        assertEq(pair.getFirstSellOrders(), 0, "Sell order should be completely matched");
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should be completely executed");
        assertEq(tokenB.balanceOf(trader1), 99000000000, "Trader1 should receive 1000 tokenB");
        assertEq(tokenA.balanceOf(trader2), 10 * 1e8, "Trader2 should receive 10 tokenA");
        assertEq(traderBalance.quoteTokenBalance, 0, "Trader1 should get 0 tokenB");
        assertEq(traderBalance.baseTokenBalance, 0, "Trader1 should get 0 tokenA");
    }

    //------------------------- Test partial fill rounding error -----
    function testTakerSendAmountIsZero() public {
        vm.startPrank(trader2);
        pair.addBuyBaseToken(0.2 * 10 ** 18, 50, trader2, nonce);
        pair.addBuyBaseToken(0.2 * 10 ** 18, 40, trader2, nonce + 1);
        pair.addBuyBaseToken(0.2 * 10 ** 18, 20, trader2, nonce + 2);
        vm.stopPrank();

        uint256 trader1BaseInitialBalance = tokenA.balanceOf(trader1);
        vm.prank(trader1);
        pair.addSellBaseToken(0.2 * 10 ** 18, 94, trader1, nonce + 3);

        uint256 sentAmount =  trader1BaseInitialBalance - tokenA.balanceOf(trader1);

        assertEq(sentAmount, 94, "Should have only sent 90 tokenA");
        assertEq(tokenB.balanceOf(trader1), 18, "Should have received 18 tokenB");
    }

    function testFillSmallBuyOrder() public {
        uint256 _price = 22983;

        vm.prank(trader2);
        pair.addBuyBaseToken(_price, 10_000e18, trader2, nonce);

        vm.prank(trader1);
        pair.addSellBaseToken(_price, 9999_99999915e10, trader1, nonce);

        vm.prank(trader1);
        pair.addSellBaseToken(_price, 9999_99999915e10, trader1, nonce);

        vm.prank(trader1);
        pair.getTraderBalances(trader1);
        assertEq(pair.getFirstBuyOrders(), 0, "Buy order should have been removed");
    }

}
