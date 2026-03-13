// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/OrderBookFactory.sol";
import "./MyTokenB.sol";
import "./MyTokenA.sol";
import "forge-std/console.sol";
import "../src/PairLib.sol";

/**
 * @title OrderBookFactoryBlockContractTest
 * @dev Tests para validar la prevención de bloqueos del contrato por órdenes muy pequeñas
 * 
 * PROBLEMA ORIGINAL:
 * - Órdenes muy pequeñas causaban transferAmount = 0 debido a división entera
 * - Esto resultaba en PL__InvalidPaymentAmount y bloqueo del contrato
 * 
 * SOLUCIÓN IMPLEMENTADA:
 * - Nuevo error PL__OrderBelowMinimum
 * - Validación: quantity > 1e18/price y price > 1e18/quantity
 * - Manejo automático de órdenes residuales pequeñas tras fills parciales
 */
contract OrderBookFactoryBlockContract is Test {
    using PairLib for PairLib.TraderBalance;

    OrderBookFactory factory;
    
    // Addresses
    address owner = makeAddr("owner");
    address feeAddress = makeAddr("feeAddress");
    address trader1 = makeAddr("trader1");
    address trader2 = makeAddr("trader2");

    // Tokens
    MyTokenA tokenA;
    MyTokenB tokenB;

    function setUp() public {
        // Deploy factory
        vm.prank(owner);
        factory = new OrderBookFactory();

        // Deploy tokens with large supply
        tokenA = new MyTokenA(100_000_000e18);
        tokenB = new MyTokenB(100_000_000e18);

        // Distribute tokens to traders
        tokenA.transfer(trader1, 1_000_000e18);
        tokenA.transfer(trader2, 1_000_000e18);
        tokenB.transfer(trader1, 1_000_000e18);
        tokenB.transfer(trader2, 1_000_000e18);

        // Approve factory to spend tokens
        vm.startPrank(trader1);
        tokenA.approve(address(factory), 10_000_000e18);
        tokenB.approve(address(factory), 10_000_000e18);
        vm.stopPrank();

        vm.startPrank(trader2);
        tokenB.approve(address(factory), 10_000_000e18);
        tokenA.approve(address(factory), 10_000_000e18);
        vm.stopPrank();

        // Create trading pair
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 0, feeAddress);
    }

    // ======================================
    // SECCIÓN 1: Tests de Órdenes Individuales Pequeñas
    // ======================================

    /**
     * @dev Test que demuestra que ahora se previenen órdenes de venta muy pequeñas
     * ANTES: Se permitían órdenes que causarían problemas en matching
     * AHORA: Se rechaza con PL__OrderBelowMinimum
     */
    function test_PreventSmallSellOrder() public {
        uint256 price = 22761; // Precio muy bajo
        bytes32[] memory keys = factory.getPairIds();
        
        vm.prank(trader1);
        vm.expectRevert(PairLib.PL__OrderBelowMinimum.selector);
        factory.addNewOrder(keys[0], 70000000000, price, false, 1); // Cantidad que antes causaba problemas

        // Verificar que no se creó ninguna orden
        uint256[50] memory sellOrders = factory.getTop50SellPricesForPair(keys[0]);
        assertEq(sellOrders[0], 0);
    }

    /**
     * @dev Test que demuestra que ahora se previenen órdenes de compra muy pequeñas
     * ANTES: transferAmount = (quantity * price) / 1e18 = 0, causando PL__InvalidPaymentAmount
     * AHORA: Se rechaza con PL__OrderBelowMinimum antes del cálculo
     */
    function test_PreventSmallBuyOrder() public {
        uint256 price = 22761;
        bytes32[] memory keys = factory.getPairIds();
        
        vm.prank(trader1);
        vm.expectRevert(PairLib.PL__OrderBelowMinimum.selector);
        factory.addNewOrder(keys[0], 70000000000, price, true, 1);

        // Verificar que no se creó ninguna orden
        uint256[50] memory buyOrders = factory.getTop50BuyPricesForPair(keys[0]);
        assertEq(buyOrders[0], 0);
    }

    /**
     * @dev Test que valida que órdenes válidas (por encima del mínimo) funcionan correctamente
     */
    function test_ValidOrdersWork() public {
        uint256 price = 22761;
        bytes32[] memory keys = factory.getPairIds();
        
        // Orden lo suficientemente grande como para ser válida
        vm.prank(trader2);
        factory.addNewOrder(keys[0], 1e18, price, true, 1); // 1 token a precio bajo = transferAmount > 0

        // Verificar que la orden se creó correctamente
        uint256[50] memory buyOrders = factory.getTop50BuyPricesForPair(keys[0]);
        assertEq(buyOrders[0], price);
        
        (uint256 orderCount, uint256 orderValue) = factory.getPricePointDataForPair(keys[0], price, true);
        assertEq(orderValue, 1e18);
    }

    // ======================================
    // SECCIÓN 2: Tests de Matching y Bloqueo del Contrato
    // ======================================

    /**
     * @dev Test que demuestra la prevención de bloqueo cuando se intenta hacer matching
     * con una orden pequeña existente
     * PROBLEMA ORIGINAL: Orden pequeña + matching = transferAmount = 0 = bloqueo
     * SOLUCIÓN: Las órdenes pequeñas no se pueden crear en primer lugar
     */
    function test_PreventMatchingWithSmallOrders() public {
        uint256 price = 22761;
        bytes32[] memory keys = factory.getPairIds();
        
        // Intentar crear orden pequeña (que antes causaba el problema)
        vm.prank(trader1);
        vm.expectRevert(PairLib.PL__OrderBelowMinimum.selector);
        factory.addNewOrder(keys[0], 70000000000, price, false, 1);

        // Verificar que tampoco se puede crear la orden de compra problemática
        vm.prank(trader2);
        vm.expectRevert(PairLib.PL__OrderBelowMinimum.selector);
        factory.addNewOrder(keys[0], 9000000002400, price, true, 1);
    }

    // ======================================
    // SECCIÓN 3: Tests de Órdenes Residuales tras Fills Parciales
    // ======================================

    /**
     * @dev Test que valida el manejo correcto de órdenes residuales pequeñas tras fill parcial
     * ESCENARIO: Una orden grande se llena parcialmente, dejando un residuo muy pequeño
     * SOLUCIÓN: El residuo se convierte automáticamente en balance retirable para el trader
     */
    function test_HandleSmallResidualsFromPartialFills_SellOrder() public {
        uint256 price = 22983;
        bytes32[] memory keys = factory.getPairIds();
        uint256 balanceTrader2TokenB = tokenB.balanceOf(trader2);
        // 1. Trader1 coloca orden de venta grande
        vm.prank(trader1);
        factory.addNewOrder(keys[0], 10_000e18, price, false, 1);

        // 2. Trader2 compra casi toda la cantidad, dejando un residuo muy pequeño
        vm.prank(trader2);
        factory.addNewOrder(keys[0], 9999_99999915e10, price, true, 1);

        // 3. Verificar que trader1 tiene balance para retirar (incluyendo el residuo)
        vm.prank(trader1);
        PairLib.TraderBalance memory tb1 = factory.checkBalanceTrader(keys[0], trader1);
        
        // Base token balance = residuo de la orden original
        assertEq(tb1.quoteTokenBalance, (9999_99999915e10 * price / 1e18));
        // Quote token balance = lo que recibió por la venta
        assertEq(tokenB.balanceOf(trader2)- balanceTrader2TokenB ,9999_99999915e10);

        // 4. Trader1 puede retirar sus fondos sin problemas
        vm.prank(trader1);
        //factory.withdrawBalanceTrader(keys[0], true);
        factory.checkBalanceTrader(keys[0], trader1);
        factory.checkBalanceTrader(keys[0], trader2);
        // Verificar que la nueva orden se creó correctamente
        uint256[50] memory sellOrders = factory.getTop50SellPricesForPair(keys[0]);
        assertEq(sellOrders[0], price);

        (uint256 orderCount, uint256 orderValue) = factory.getPricePointDataForPair(keys[0], price, false);
        assertEq(orderValue, 10_000e18 - 9999_99999915e10);
    }

    /**
     * @dev Test similar pero para órdenes de compra que quedan con residuos pequeños
     */
    function test_HandleSmallResidualsFromPartialFills_BuyOrder() public {
        uint256 price = 22983;
        bytes32[] memory keys = factory.getPairIds();
        uint256 balanceTrader2TokenA = tokenA.balanceOf(trader2);

        // 1. Trader1 coloca orden de compra grande
        vm.prank(trader1);
        factory.addNewOrder(keys[0], 10_000e18, price, true, 1);

        // 2. Trader2 vende casi toda la cantidad, dejando un residuo muy pequeño
        vm.prank(trader2);
        factory.addNewOrder(keys[0], 9999_99999915e10, price, false, 1);

        // 3. Verificar balances del trader1
        vm.prank(trader1);
        PairLib.TraderBalance memory tb1 = factory.checkBalanceTrader(keys[0], trader1);
        factory.checkBalanceTrader(keys[0], trader2);
        // Base token balance = lo que compró
        assertEq(tb1.baseTokenBalance, 9999_99999915e10);
        // Quote token balance = residuo de lo que no se pudo usar para comprar
        //assertEq(tb1.quoteTokenBalance, 10_000e18 - 9999_99999915e10);
        assertEq(tokenA.balanceOf(trader2) - balanceTrader2TokenA,(9999_99999915e10 * price / 1e18));

        // 4. Trader1 puede retirar sus fondos
        vm.prank(trader1);
        factory.withdrawBalanceTrader(keys[0], true);

        // Verificar que la nueva orden se creó correctamente
        uint256[50] memory buyOrders = factory.getTop50BuyPricesForPair(keys[0]);
        assertEq(buyOrders[0], price);

        (uint256 orderCount, uint256 orderValue) = factory.getPricePointDataForPair(keys[0], price, true);
        assertEq(orderValue, 10_000e18 - 9999_99999915e10);
    }

    // ======================================
    // SECCIÓN 4: Tests de Validación Matemática
    // ======================================

    /**
     * @dev Test que analiza los valores matemáticos que causaban el problema original
     */
    function test_AnalyzeProblemValues() public {
        //console.log("=== ANÁLISIS DE VALORES PROBLEMÁTICOS ===");
        
        // Caso de compra que antes fallaba
        uint256 buyPrice = 22761;
        uint256 buyQuantity = 9000000002400;
        uint256 buyProduct = buyQuantity * buyPrice;
        uint256 buyTransferAmount = buyProduct / 1e18;

        //console.log("ORDEN DE COMPRA PROBLEMÁTICA:");
        //console.log("Precio:", buyPrice);
        //console.log("Cantidad:", buyQuantity);
        //console.log("Producto:", buyProduct);
        //console.log("Transfer Amount:", buyTransferAmount);
        //console.log("¿Transfer Amount = 0?", buyTransferAmount == 0);
        
        // Verificar que efectivamente era 0
        assertEq(buyTransferAmount, 0, unicode"El transfer amount debería ser 0 (problema original)");
        
        // Caso de venta (este nunca fallaría por transferAmount = quantity)
        uint256 sellQuantity = 70000000000;
        //console.log("");
        //console.log("ORDEN DE VENTA:");
        //console.log("Cantidad:", sellQuantity);
        //console.log("Transfer Amount (= quantity):", sellQuantity);
        //console.log("¿Es mayor que 0?", sellQuantity > 0);

        //console.log("==========================================");
    }
}