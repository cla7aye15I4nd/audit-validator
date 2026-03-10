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
        tokenA = new MyTokenA(100000000000 * 10 ** 18); //Crear un nuevo token con suministro inicial
        tokenB = new MyTokenB(100000000000 * 10 ** 18); //Crear un nuevo token con suministro inicial
        //        console.log(address(factory));
        //        console.log(msg.sender);

        tokenA.transfer(trader1, 150000e18);
        tokenB.transfer(trader2, 150000e18);

        //Aprobar el contrato para que pueda gastar tokens
        vm.startPrank(trader1); // Cambiar el contexto a trader1
        tokenA.approve(address(factory), 150000 * 10 ** 18); // Aprobar 1000 tokens
        tokenB.approve(address(factory), 150000 * 10 ** 18); // Aprobar 1000 tokens
        vm.stopPrank();

        vm.startPrank(trader2); // Cambiar el contexto a trader1
        tokenB.approve(address(factory), 150000 * 10 ** 18); // Aprobar 1000 tokens
        tokenA.approve(address(factory), 150000 * 10 ** 18); // Aprobar 1000 tokens
        vm.stopPrank();

        vm.startPrank(address(factory)); // Cambiar el contexto a trader1
        tokenB.approve(address(factory), 150000 * 10 ** 18); // Aprobar 1000 tokens
        tokenA.approve(address(factory), 150000 * 10 ** 18); // Aprobar 1000 tokens
        vm.stopPrank();
    }

    //-------------------- ADD ORDER BOOK ------------------------------

    //Verifica que se pueda añadir correctamente un nuevo libro de órdenes y que emita el evento OrderBookCreated con los parámetros esperados.
    function testaddPairSuccess() public {
        vm.prank(owner);
        bytes32 expectedId = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));

        //vm.expectEmit(true, true, true, true);
        //emit OrderBookCreated(expectedId, address(tokenA), address(tokenB), owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        bytes32[] memory keys = factory.getPairIds();
        assertEq(keys.length, 1);

        (address baseToken, address quoteToken,,,,) = factory.getPairById(keys[0]);
        console.log(baseToken);
        console.log(quoteToken);
        assertEq(baseToken, address(tokenB)); //TODO REVISAR PQ LOS INVIERTE
        assertEq(quoteToken, address(tokenA));
    }

    //Verifica que se revierte si el _baseToken es la dirección cero (address(0)).
    function testRevertIfBaseTokenIsZero() public {
        vm.prank(owner);
        vm.expectRevert(OrderBookFactory.OBF__InvalidTokenAddress.selector);
        factory.addPair(address(0), address(tokenB), 5, feeAddress);
    }

    function testRevertIfFeeExceedsMaxFee() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(OrderBookFactory.OBF__FeeExceedsMaximum.selector, 500, 200));
        factory.addPair(address(tokenA), address(tokenB), 500, feeAddress);
        factory.addPair(address(tokenA), address(tokenB), 100, feeAddress);
        bytes32[] memory keys = factory.getPairIds();

        bytes32 pairId = keys[0];
        vm.expectRevert(abi.encodeWithSelector(OrderBookFactory.OBF__FeeExceedsMaximum.selector, 600, 200));
        factory.setPairFee(pairId, 600);
        vm.stopPrank();
    }

    function testRevertPairAlreadyExists() public {
        vm.startPrank(owner);
        bytes32 expectedId = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));

        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);
        vm.expectRevert(OrderBookFactory.OBF__PairAlreadyExists.selector);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);
        vm.expectRevert(OrderBookFactory.OBF__PairAlreadyExists.selector);
        factory.addPair(address(tokenB), address(tokenA), 5, feeAddress);
        vm.stopPrank();
    }

    //Verifica que se revierte si el _quoteToken es la dirección cero (address(0)).
    function testRevertIfQuoteTokenIsZero() public {
        vm.prank(owner);
        vm.expectRevert(OrderBookFactory.OBF__InvalidTokenAddress.selector);
        factory.addPair(address(tokenA), address(0), 5, feeAddress);
    }

    //    //Prueba que se revierte si el propietario es la dirección cero, simulando un cambio inválido de propietario.
    //    function testRevertIfOwnerAddressIsZero() public {
    //        vm.prank(owner);
    //        vm.expectRevert(Ownable.OwnableInvalidOwner.selector);
    //        factory.transferOwnership(address(0));
    //
    //        //vm.prank(owner);
    //        //vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
    //        //factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);
    //    }

    //Verifica que se revierte si los tokens base y de cotización son iguales.
    function testRevertIfTokensAreEqual() public {
        vm.prank(owner);
        vm.expectRevert(OrderBookFactory.OBF__TokensMustBeDifferent.selector);
        factory.addPair(address(tokenA), address(tokenA), 5, feeAddress);
    }

    //Verifica que se revierte si la dirección de la tarifa es la dirección cero.
    function testRevertIfFeeAddressIsZero() public {
        vm.prank(owner);
        vm.expectRevert(OrderBookFactory.OBF__InvalidFeeAddress.selector);
        factory.addPair(address(tokenA), address(tokenB), 5, address(0));
    }

    //Verifica que el orden de los tokens esté correctamente gestionado dentro de la función, asegurando que el token de menor valor de dirección sea el baseToken.
    function testTokenOrderCorrectness() public {
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);
        bytes32[] memory keys = factory.getPairIds();

        (address baseToken, address quoteToken,,,,) = factory.getPairById(keys[0]);
        assertEq(baseToken, address(tokenB)); // addr1 should be baseToken since it's lower in address value
        assertEq(quoteToken, address(tokenA));
    }

    //    //Verifica que se revierte la transacción si alguien que no es el propietario intenta agregar un libro de órdenes.
    //    function testRevertIfaddPairCalledByNonOwner() public {
    //        vm.prank(trader1); // Simula que un usuario que no es el propietario llama a la función
    //        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
    //        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);
    //    }

    //Comprueba que se puedan agregar múltiples libros de órdenes de forma exitosa y que los identificadores sean únicos.
    function testAddMultipleOrderBooks() public {
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);
        vm.prank(owner);
        factory.addPair(trader1, trader2, 10, feeAddress);

        bytes32[] memory keys = factory.getPairIds();
        assertEq(keys.length, 2); // Se deberían agregar 2 libros de órdenes
    }

    //Asegura que se revierte la transacción si se intenta agregar un libro de órdenes que ya existe.
    function testRevertIfAddingDuplicateOrderBook() public {
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress); // Agregar primer libro de órdenes

        vm.expectRevert(); // Esperamos que la siguiente llamada revierta
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress); // Intentar agregar el mismo libro de órdenes
    }

    //Verifica que un nuevo propietario pueda agregar un libro de órdenes después de que se haya cambiado el propietario.
    function testtransferOwnershipAndaddPair() public {
        address newOwner = address(5);

        // Cambiamos el propietario
        vm.prank(owner);
        factory.transferOwnership(newOwner);

        //Aceptar ser owner
        vm.prank(newOwner);
        factory.acceptOwnership();

        vm.prank(newOwner); // Ahora simulamos que el nuevo propietario llama a la función
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        bytes32[] memory keys = factory.getPairIds();
        assertEq(keys.length, 1); // Verificamos que el nuevo libro de órdenes se agregó
    }

    //Comprueba que se puedan agregar libros de órdenes con diferentes valores de tarifas y que estas se almacenen correctamente.
    function testaddPairWithDifferentFeeValues() public {
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress); // Primer libro de órdenes
        vm.prank(owner);
        factory.addPair(trader1, trader2, 15, feeAddress); // Segundo libro de órdenes

        bytes32[] memory keys = factory.getPairIds();
        assertEq(keys.length, 2); // Verificamos que se hayan agregado dos libros de órdenes

        (address _baseToken1, address _quoteToken1, bool _status1, uint256 lastTradePrice1, uint256 fee1,) =
            factory.getPairById(keys[0]);
        console.log(fee1);
        console.log(_baseToken1);
        (address _baseToken2, address _quoteToken2, bool _status2, uint256 lastTradePrice2, uint256 fee2,) =
            factory.getPairById(keys[1]);

        assertEq(fee1, 5); // Verifica que la tarifa del primer libro sea correcta
        assertEq(fee2, 15); // Verifica que la tarifa del segundo libro sea correcta
    }

    //Verifica que el estado predeterminado de un nuevo libro de órdenes sea true al ser creado.
    function testOrderBookStatusDefault() public {
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress); // Agregar libro de órdenes

        bytes32[] memory keys = factory.getPairIds();
        (,, bool status,,,) = factory.getPairById(keys[0]);

        assertTrue(status); // Verifica que el estado predeterminado sea verdadero
    }

    //-------------------- GET KEYS ORDERS ------------------------------

    //Verifica que la función getKeysOrderBooks devuelva un array vacío cuando no se ha creado ningún libro de órdenes.
    function testGetKeysOrderBooksWithNoOrderBooks() public {
        // Llamar a getKeysOrderBooks antes de agregar ningún libro de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que el array esté vacío
        assertEq(keys.length, 0, unicode"El array de claves debería estar vacío");
    }

    //Verifica que la función getKeysOrderBooks devuelva una lista que contenga el identificador de un único libro de órdenes creado.
    function testGetKeysOrderBooksWithSingleOrderBook() public {
        // Agregar un solo libro de órdenes
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber una sola clave en el array");

        // Verificar que el identificador del libro de órdenes es correcto
        bytes32 expectedKey = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
        assertEq(keys[0], expectedKey, unicode"El identificador del libro de órdenes debería coincidir");
    }

    //Verifica que la función getKeysOrderBooks devuelva una lista de múltiples identificadores después de crear varios libros de órdenes.
    function testGetKeysOrderBooksWithMultipleOrderBooks() public {
        // Agregar varios libros de órdenes
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);
        factory.addPair(address(tokenB), trader1, 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay dos claves
        assertEq(keys.length, 2, unicode"Debería haber dos claves en el array");

        // Verificar que los identificadores de los libros de órdenes son correctos
        bytes32 expectedKey1 = keccak256(abi.encodePacked(address(tokenA), address(tokenB))); //TODO REVISAR PQ LOS DEBO INVERTIR
        bytes32 expectedKey2 = keccak256(abi.encodePacked(trader1, address(tokenB)));
        assertEq(keys[0], expectedKey1, unicode"El primer identificador debería coincidir");
        assertEq(keys[1], expectedKey2, unicode"El segundo identificador debería coincidir");
    }

    //Verifica que los identificadores devueltos estén en el mismo orden en que se crearon los libros de órdenes.
    function testGetKeysOrderBooksOrderConsistency() public {
        // Agregar varios libros de órdenes
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);
        factory.addPair(address(tokenB), trader1, 10, feeAddress);
        factory.addPair(trader1, trader2, 15, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que las claves se devuelven en el mismo orden en que se agregaron
        bytes32 expectedKey1 = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
        bytes32 expectedKey2 = keccak256(abi.encodePacked(trader1, address(tokenB)));
        bytes32 expectedKey3 = keccak256(abi.encodePacked(trader1, trader2));

        assertEq(keys.length, 3, unicode"Debería haber tres claves en el array");
        console.logBytes32(expectedKey1);
        console.logBytes32(expectedKey2);
        console.logBytes32(expectedKey3);

        console.logBytes32(keys[0]);
        console.logBytes32(keys[1]);
        console.logBytes32(keys[2]);

        console.logBytes32(keccak256(abi.encodePacked(address(tokenB), address(tokenA))));
        console.logBytes32(keccak256(abi.encodePacked(trader1, address(tokenB))));
        console.logBytes32(keccak256(abi.encodePacked(trader2, trader1)));
        assertEq(keys[0], expectedKey1, unicode"El primer identificador debería coincidir");
        assertEq(keys[1], expectedKey2, unicode"El segundo identificador debería coincidir");
        assertEq(keys[2], expectedKey3, unicode"El tercer identificador debería coincidir");
    }

    //-------------------- GET ORDERS BOOK BY ID ------------------------------

    //Verifica que la función getOrderBookById devuelva valores por defecto (dirección 0x0, false, etc.) cuando se consulta por un libro de órdenes que no existe.
    function testRevertGetOrderBookByIdForNonExistentOrderBook() public {
        // Intentar obtener un libro de órdenes con un ID inexistente
        bytes32 nonExistentId = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);

        // Llamar a la función getOrderBookById
        (address baseToken, address quoteToken, bool status, uint256 lastTradePrice, uint256 fee,) =
            factory.getPairById(nonExistentId);
    }

    //Verifica que la función getOrderBookById devuelva los valores correctos después de crear un nuevo libro de órdenes.
    function testGetOrderBookByIdAfterCreation() public {
        // Crear un libro de órdenes
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber una sola clave en el array");

        // Llamar a la función getOrderBookById
        (address baseToken, address quoteToken, bool status, uint256 lastTradePrice, uint256 fee,) =
            factory.getPairById(keys[0]);

        console.log(baseToken);
        console.log(quoteToken);

        // Verificar que los valores devueltos coincidan con los del libro de órdenes
        //TODO REVISAR PQ LOS INVIERTE
        assertEq(baseToken, address(tokenB), unicode"El baseToken debería coincidir con el libro de órdenes creado");
        assertEq(quoteToken, address(tokenA), unicode"El quoteToken debería coincidir con el libro de órdenes creado");
        assertEq(status, true, unicode"El estado debería ser verdadero");
        assertEq(lastTradePrice, 0, unicode"El último precio de operación debería ser cero");
        assertEq(fee, 5, unicode"La tarifa debería ser la especificada en la creación");
    }

    //Verifica que se puedan consultar varios libros de órdenes creados, y que la función devuelva los datos correctos para cada uno.
    function testGetOrderBookByIdForMultipleOrderBooks() public {
        // Crear múltiples libros de órdenes
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);
        factory.addPair(address(tokenB), trader1, 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 2, unicode"Debería haber dos claves en el array");

        // Generar los IDs esperados
        //bytes32 orderId1 = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
        //bytes32 orderId2 = keccak256(abi.encodePacked(address(tokenB), trader1));

        // Obtener y verificar el primer libro de órdenes
        (address baseToken1, address quoteToken1, bool status1, uint256 lastTradePrice1, uint256 fee1,) =
            factory.getPairById(keys[0]);
        //TODO REVISA PQ CAMBIA
        assertEq(baseToken1, address(tokenB), unicode"El baseToken del primer libro debería coincidir");
        assertEq(quoteToken1, address(tokenA), unicode"El quoteToken del primer libro debería coincidir");
        assertEq(status1, true, unicode"El estado del primer libro debería ser verdadero");
        assertEq(lastTradePrice1, 0, unicode"El último precio del primer libro debería ser cero");
        assertEq(fee1, 5, unicode"La tarifa del primer libro debería ser 5");

        // Obtener y verificar el segundo libro de órdenes
        (address baseToken2, address quoteToken2, bool status2, uint256 lastTradePrice2, uint256 fee2,) =
            factory.getPairById(keys[1]);
        assertEq(baseToken2, trader1, unicode"El baseToken del segundo libro debería coincidir");
        assertEq(quoteToken2, address(tokenB), unicode"El quoteToken del segundo libro debería coincidir");
        assertEq(status2, true, unicode"El estado del segundo libro debería ser verdadero");
        assertEq(lastTradePrice2, 0, unicode"El último precio del segundo libro debería ser cero");
        assertEq(fee2, 10, unicode"La tarifa del segundo libro debería ser 10");
    }

    //-------------------- SET OWNER ------------------------------

    //Verifica que el propietario actual pueda cambiar correctamente la dirección del propietario a una nueva dirección válida.
    function testtransferOwnershipAsOwner() public {
        // El propietario actual intenta cambiar la dirección del propietario
        vm.prank(owner); // Simular que el propietario actual está llamando
        factory.transferOwnership(trader1);

        vm.prank(trader1);
        factory.acceptOwnership();

        // Verificar que el propietario haya sido cambiado correctamente
        assertEq(factory.owner(), trader1, unicode"La nueva dirección del propietario debería ser addr1");
    }

    //Verifica que la función transferOwnership revierta si es llamada por una dirección que no es el propietario actual.
    function testtransferOwnershipRevertsIfCallerIsNotOwner() public {
        // Intentar cambiar el propietario desde una dirección que no es el propietario actual

        // Verificar que la llamada revierte
        vm.startPrank(trader1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, trader1));
        factory.transferOwnership(trader1);
        vm.stopPrank();
    }

    //Verifica que la función transferOwnership revierta si se intenta establecer la dirección del propietario como la dirección cero (address(0)).
    //    function testtransferOwnershipRevertsIfNewOwnerIsZeroAddress() public {
    //        // El propietario intenta establecer la dirección cero como el nuevo propietario
    //        vm.prank(owner); // Simular que el propietario actual está llamando
    //
    //        // Verificar que la llamada revierte debido a que la dirección nueva es 0x0
    //        factory.transferOwnership(address(0));
    //
    //        vm.startPrank(address(0));
    //        //vm.expectRevert(abi.encodeWithSelector(Ownable2Step.OwnableInvalidOwner.selector, address(0)));
    //        factory.acceptOwnership();
    //        vm.stopPrank();
    //    }

    //Después de cambiar la propiedad una vez, verificar que el nuevo propietario pueda cambiar la propiedad nuevamente a otra dirección válida.
    function testtransferOwnershipFromNewOwner() public {
        // El propietario actual (owner) cambia la propiedad a addr1
        vm.prank(owner); // Simular que el propietario actual llama
        factory.transferOwnership(trader1);

        vm.prank(trader1);
        factory.acceptOwnership();

        // Verificar que la propiedad haya sido transferida a addr1
        assertEq(factory.owner(), trader1, unicode"El nuevo propietario debería ser addr1");

        // El nuevo propietario (addr1) cambia la propiedad a addr2
        vm.prank(trader1); // Simular que el nuevo propietario llama
        factory.transferOwnership(owner);

        vm.prank(owner);
        factory.acceptOwnership();

        // Verificar que la propiedad haya sido transferida a addr2
        assertEq(factory.owner(), owner, unicode"El nuevo propietario debería ser addr2");
    }

    //-------------------- SET ORDER BOOK STATUS ------------------------------

    //Verifica que el propietario pueda cambiar el estado de un libro de órdenes existente.
    function testsetPairStatusAsOwner() public {
        // Cambiar el estado del libro de órdenes a inactivo (false)
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        vm.prank(owner); // Simular que el propietario está llamando
        factory.setPairStatus(keys[0], false);

        // Verificar que el estado haya cambiado correctamente
        (,, bool status,,,) = factory.getPairById(keys[0]);
        assertEq(status, false, unicode"El estado del libro de órdenes debería ser inactivo");
    }

    //Verifica que la función setPairStatus revierta si es llamada por una dirección que no es el propietario.
    function testsetPairStatusRevertsIfNotOwner() public {
        // Intentar cambiar el estado desde una dirección no propietaria
        bytes32 orderId1 = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));

        vm.prank(owner); // Simular que una dirección que no es el propietario llama
        // Verificar que la llamada revierte
        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        factory.setPairStatus(orderId1, false);
    }

    //Verifica que la función setPairStatus revierta si se intenta cambiar el estado de un libro de órdenes que no existe.
    function testsetPairStatusRevertsIfOrderBookDoesNotExist() public {
        bytes32 nonExistentOrderBookId = keccak256(abi.encodePacked(address(6), address(7)));

        // Intentar cambiar el estado de un libro de órdenes inexistente
        vm.prank(owner); // Simular que el propietario actual está llamando
        // Verificar que la llamada revierte debido a que el libro no existe
        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        factory.setPairStatus(nonExistentOrderBookId, false);
    }

    //-------------------- SET ORDER BOOK FEE ------------------------------
    //Verifica que el propietario pueda cambiar la tarifa de un libro de órdenes existente.
    function testsetPairFeeAsOwner() public {
        uint256 newFee = 5; // Nueva tarifa del 5%
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Cambiar la tarifa del libro de órdenes
        vm.prank(owner); // Simular que el propietario está llamando
        factory.setPairFee(keys[0], newFee);

        // Verificar que la tarifa haya cambiado correctamente
        (,,,, uint256 fee,) = factory.getPairById(keys[0]);
        assertEq(fee, newFee, unicode"La tarifa del libro de órdenes debería haberse actualizado al 5%");
    }

    //Verifica que la función setPairFee revierta si es llamada por una dirección que no es el propietario.
    function testsetPairFeeRevertsIfNotOwner() public {
        bytes32 orderId1 = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
        uint256 newFee = 5; // Nueva tarifa del 5%

        // Intentar cambiar la tarifa desde una dirección no propietaria
        vm.prank(trader1); // Simular que una dirección no propietaria llama

        // Verificar que la llamada revierte
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, trader1));
        factory.setPairFee(orderId1, newFee);
    }

    //Verifica que la función setPairFee revierta si se intenta cambiar la tarifa de un libro de órdenes que no existe.
    function testsetPairFeeRevertsIfOrderBookDoesNotExist() public {
        uint256 newFee = 5; // Nueva tarifa del 5%
        bytes32 nonExistentOrderBookId = keccak256(abi.encodePacked(address(6), address(7)));

        // Intentar cambiar la tarifa de un libro de órdenes inexistente
        vm.prank(owner); // Simular que el propietario actual está llamando
        // Verificar que la llamada revierte debido a que el libro no existe
        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        factory.setPairFee(nonExistentOrderBookId, newFee);
    }

    //Verifica que se emite correctamente el evento OrderBookFeeChanged después de cambiar la tarifa.
    function testsetPairFeeEmitEvent() public {
        uint256 newFee = 5; // Nueva tarifa del 0.05%
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Esperar a que el evento `OrderBookFeeChanged` sea emitido
        vm.expectEmit(true, true, true, true);
        emit OrderBookFactory.PairFeeChanged(keys[0], newFee);

        // Cambiar la tarifa del libro de órdenes
        vm.prank(owner); // Simular que el propietario está llamando
        factory.setPairFee(keys[0], newFee);
    }

    //-------------------- SET ORDER BOOK FEE ADDRESS ------------------------------

    //Verifica que el propietario pueda cambiar la dirección de la tarifa de un libro de órdenes existente.
    function testsetPairFeeAddressAsOwner() public {
        // Cambiar la dirección de la tarifa del libro de órdenes
        address newFeeAddress = makeAddr("newFeeAddress");

        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        vm.prank(owner); // Simular que el propietario está llamando
        factory.setPairFeeAddress(keys[0], newFeeAddress);

        // Verificar que la dirección de la tarifa haya cambiado correctamente
        //(, , , , ,address feeAddr) = factory.getOrderBookById(keys[0]);
        //assertEq(feeAddr, newFeeAddress, unicode"La dirección de la tarifa debería haberse actualizado correctamente.");
    }

    //Verifica que la función setPairFeeAddress revierta si es llamada por una dirección que no es el propietario.
    function testsetPairFeeAddressRevertsIfNotOwner() public {
        bytes32 nonExistentOrderBookId = keccak256(abi.encodePacked(address(6), address(7)));
        address newFeeAddress = makeAddr("newFeeAddress");
        // Intentar cambiar la dirección de la tarifa desde una dirección no propietaria
        vm.prank(trader1); // Simular que una dirección no propietaria llama
        // Verificar que la llamada revierte
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, trader1));
        factory.setPairFeeAddress(nonExistentOrderBookId, newFeeAddress);
    }

    //Verifica que la función setPairFeeAddress revierta si se intenta cambiar la dirección de la tarifa de un libro de órdenes que no existe.
    function testsetPairFeeAddressRevertsIfOrderBookDoesNotExist() public {
        address newFeeAddress = makeAddr("newFeeAddress");
        bytes32 nonExistentOrderBookId = keccak256(abi.encodePacked(address(7), address(8)));

        // Intentar cambiar la dirección de la tarifa de un libro de órdenes inexistente
        vm.prank(owner); // Simular que el propietario actual está llamando

        // Verificar que la llamada revierte debido a que el libro no existe
        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        factory.setPairFeeAddress(nonExistentOrderBookId, newFeeAddress);
    }

    //Verifica que la función setPairFeeAddress revierta si se intenta establecer una dirección de tarifa inválida (la dirección cero).
    function testsetPairFeeAddressRevertsIfFeeAddressIsZero() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");
        // Intentar cambiar la dirección de la tarifa a la dirección cero
        vm.prank(owner); // Simular que el propietario actual está llamando
        // Verificar que la llamada revierte debido a que la dirección de tarifa es inválida
        vm.expectRevert(OrderBookFactory.OBF__InvalidFeeAddress.selector);
        factory.setPairFeeAddress(keys[0], address(0));
    }

    //Verifica que se emita correctamente el evento OrderBookFeeAddressChanged después de cambiar la dirección de la tarifa.
    function testsetPairFeeAddressEmitEvent() public {
        address newFeeAddress = makeAddr("newFeeAddress");
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Esperar a que el evento `OrderBookFeeAddressChanged` sea emitido
        vm.expectEmit(true, true, true, true);
        emit OrderBookFactory.PairFeeAddressChanged(keys[0], newFeeAddress);

        // Cambiar la dirección de la tarifa del libro de órdenes
        vm.prank(owner); // Simular que el propietario está llamando
        factory.setPairFeeAddress(keys[0], newFeeAddress);
    }

    //-------------------- GET OWNER ------------------------------

    //Verifica que la dirección del propietario sea la dirección inicialmente establecida al desplegar el contrato.
    function testownerInitially() public {
        // Verificar que la dirección del propietario inicial sea la correcta
        assertEq(
            factory.owner(), owner, unicode"La dirección del propietario debería ser la dirección inicial establecida."
        );
    }

    //Verifica que la función owner devuelva la dirección correcta después de que el propietario haya sido cambiado utilizando la función transferOwnership.
    function testownerAfterOwnershipChange() public {
        address newOwner = makeAddr("newOwner");
        // Cambiar la propiedad a una nueva dirección
        vm.prank(owner); // Simular que el propietario actual está llamando
        factory.transferOwnership(newOwner);

        //Aceptar ser owner
        vm.prank(newOwner);
        factory.acceptOwnership();

        // Verificar que la función owner devuelva la nueva dirección de propietario
        assertEq(
            factory.owner(),
            newOwner,
            unicode"La dirección del propietario debería haber cambiado a la nueva dirección."
        );
    }

    //-------------------- ADD NEW ORDER ------------------------------

    //Verifica que una nueva orden de compra se agrega correctamente a un libro de órdenes existente.
    function testAddNewBuyOrder() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Agregar una nueva orden de compra
        uint256 quantity = 10;
        uint256 price = 100 * 1e18;
        bool isBuy = true;

        vm.prank(trader1);
        factory.addNewOrder(keys[0], quantity, price, isBuy, 1);

        // Verificar que la orden de compra se haya agregado correctamente
        //TODO PQ SE INVIERTE EL TOKEN
        (address baseTokenOrder, address quoteTokenOrder,, uint256 lastTradePrice,,) = factory.getPairById(keys[0]);
        assertEq(baseTokenOrder, address(tokenB), "El token base debe coincidir");
        assertEq(quoteTokenOrder, address(tokenA), unicode"El token de cotización debe coincidir");
        assertEq(lastTradePrice, 0, unicode"El último precio negociado debe ser 0 al inicio");
    }

    //Verifica que una nueva orden de venta se agrega correctamente a un libro de órdenes existente.
    function testAddNewSellOrder() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Agregar una nueva orden de venta
        uint256 quantity = 10e18;
        uint256 price = 100e18;
        bool isBuy = false;

        vm.prank(trader2);
        factory.addNewOrder(keys[0], quantity, price, false, 1);

        // Verificar que la orden de venta se haya agregado correctamente
        (address baseTokenOrder, address quoteTokenOrder,, uint256 lastTradePrice,,) = factory.getPairById(keys[0]);
        assertEq(baseTokenOrder, address(tokenB), "El token base debe coincidir");
        assertEq(quoteTokenOrder, address(tokenA), unicode"El token de cotización debe coincidir");
        assertEq(lastTradePrice, 0, unicode"El último precio negociado debe ser 0 al inicio");
    }

    //Verifica que se revierte si se intenta agregar una orden a un libro de órdenes que no existe.
    function testAddOrderToNonExistentOrderBook() public {
        // Intentar agregar una orden a un libro de órdenes inexistente
        bytes32 nonExistentOrderBookId = keccak256(abi.encodePacked(address(100), address(101)));
        uint256 quantity = 10;
        uint256 price = 100;
        bool isBuy = true;

        vm.prank(owner);
        vm.expectRevert(OrderBookFactory.OBF__PairNotEnabled.selector);
        factory.addNewOrder(nonExistentOrderBookId, quantity, price, isBuy, 1);
    }

    //Verifica que no se pueda agregar una orden de compra con cantidad cero.
    function testAddBuyOrderWithZeroQuantity() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Verificar que no se pueda agregar una orden de compra con cantidad cero
        uint256 price = 10;
        bool isBuy = true;
        uint256 quantity = 0;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PairLib.PL__InvalidQuantity.selector, 0));
        //vm.expectRevert(OrderBookFactory.OBF__InvalidQuantityValueZero.selector); // Puedes agregar un revert message si implementas uno en el contrato
        factory.addNewOrder(keys[0], quantity, price, isBuy, 1);
    }

    //Verifica que no se pueda agregar una orden de venta con cantidad cero.
    function testAddSellOrderWithZeroQuantity() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Verificar que no se pueda agregar una orden de venta con cantidad cero
        uint256 price = 15;
        bool isBuy = false;
        uint256 quantity = 0;

        vm.prank(owner);
        //vm.expectRevert(OrderBookFactory.OBF__InvalidQuantityValueZero.selector); // Puedes agregar un revert message si implementas uno en el contrato
        vm.expectRevert(abi.encodeWithSelector(PairLib.PL__InvalidQuantity.selector, 0));
        factory.addNewOrder(keys[0], quantity, price, isBuy, 1);
    }

    /*//Verifica que no se pueda agregar una orden de compra con una dirección de trader inválida (por ejemplo, la dirección cero).
    function testAddBuyOrderWithInvalidTraderAddress() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getKeysOrderBooks();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Verificar que no se pueda agregar una orden con una dirección de trader inválida (dirección cero)
        uint256 quantity = 10;
        uint256 price = 100;
        bool isBuy = true;
        address invalidTrader = address(0);

        vm.prank(invalidTrader);
        //vm.expectRevert(OrderBookFactory.OBF__InvalidQuantityValueZero.selector);  // Puedes agregar un revert message si implementas uno en el contrato
        factory.addNewOrder(keys[0], quantity, price, isBuy, invalidTrader);
    }*/

    //Verifica que no se pueda agregar una orden de venta con una dirección de trader inválida (dirección cero).
    /*function testAddSellOrderWithInvalidTraderAddress() public {
        // Verificar que no se pueda agregar una orden de venta con una dirección de trader inválida (dirección cero)
        uint256 quantity = 500;
        uint256 price = 20;
        bool isBuy = false;
        address invalidTrader = address(0);

        vm.prank(invalidTrader);
        vm.expectRevert("Invalid trader address");  // Puedes agregar un revert message si implementas uno en el contrato
        factory.addNewOrder(orderBookId, quantity, price, isBuy, invalidTrader);
    }

    //Verifica que se pueden agregar múltiples órdenes de compra y venta con el mismo precio en un libro de órdenes.
    function testAddOrderWithSamePrice() public {
        // Verificar que se pueden agregar múltiples órdenes con el mismo precio
        uint256 quantity1 = 1000;
        uint256 quantity2 = 500;
        uint256 price = 10;
        bool isBuy = true;

        vm.prank(trader);
        factory.addNewOrder(orderBookId, quantity1, price, isBuy, trader);

        vm.prank(trader);
        factory.addNewOrder(orderBookId, quantity2, price, isBuy, trader);

        // Verificar si el libro de órdenes tiene ambas órdenes con el mismo precio
        (address baseTokenOrder, address quoteTokenOrder, , uint256 lastTradePrice,) = factory.getOrderBookById(orderBookId);
        assertEq(baseTokenOrder, baseToken, "El token base debe coincidir");
        assertEq(quoteTokenOrder, quoteToken, "El token de cotización debe coincidir");
        assertEq(lastTradePrice, 0, "El último precio negociado debe ser 0 al inicio");
    }

    //Verifica que no se puede agregar una orden a un libro de órdenes que ha sido desactivado (su estado está en false).
    function testAddOrderAfterOrderBookDeactivated() public {
        // Desactivar el libro de órdenes
        vm.prank(owner);
        factory.setPairStatus(orderBookId, false);

        // Intentar agregar una orden después de desactivar el libro de órdenes
        uint256 quantity = 1000;
        uint256 price = 10;
        bool isBuy = true;

        vm.prank(trader);
        vm.expectRevert("Order book is inactive");  // Puedes agregar un revert message si implementas uno en el contrato
        factory.addNewOrder(orderBookId, quantity, price, isBuy, trader);
    }*/

    //-------------------- CANCEL ORDER ------------------------------

    //Verifica que una orden puede ser cancelada exitosamente en un libro de órdenes válido.
    function testCancelOrderSuccessfully() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Agregar una nueva orden de compra
        uint256 quantity = 10;
        uint256 price = 100 * 1e18;
        bool isBuy = true;

        vm.prank(trader1);
        factory.addNewOrder(keys[0], quantity, price, isBuy, 1);
        uint256 nonce = 1;
        bytes32 _orderId = keccak256(abi.encodePacked(trader1, "buy", price, nonce));

        console.logBytes32(keys[0]);
        // Cancelar la orden exitosamente
        vm.prank(trader1);
        factory.cancelOrder(keys[0], _orderId);

        // Verificar que la orden fue cancelada
        //vm.expectRevert(RedBlackTree.RedBlackTree__ValueCannotBeZero.selector);  // Puedes agregar un revert message si implementas uno en el contrato
        //(, , bool status,,) = factory.getOrderBookById(keys[0]);
        //assertFalse(status, unicode"La orden debería estar cancelada");
    }

    function testOneBuy10Sells() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        console.log("T1 BA INICIO", tokenA.balanceOf(address(trader1)));
        console.log("T1 BB INICIO", tokenB.balanceOf(address(trader1)));

        console.log("T2 BA INICIO", tokenA.balanceOf(address(trader2)));
        console.log("T2 BB INICIO", tokenB.balanceOf(address(trader2)));

        console.log("TC BA INICIO", tokenA.balanceOf(address(factory)));
        console.log("TC BB INICIO", tokenB.balanceOf(address(factory)));

        vm.startPrank(trader2);
        // Agregar ventas
        uint256 quantity = 1e18;
        bool isBuy = false;

        for (uint256 i = 1; i <= 10; i++) {
            // Generate a unique order ID
            bytes32 orderId = keccak256(abi.encodePacked(address(this), i));
            // Push the order into the queue
            factory.addNewOrder(keys[0], quantity, 1 * 10 ** 18, isBuy, i);
            //            factory.addNewOrder(keys[0], quantity, 2, isBuy, i + 1, i+1);
            //            factory.addNewOrder(keys[0], quantity, 3, isBuy, i + 2, i+1);
            //            factory.addNewOrder(keys[0], quantity, 4, isBuy, i + 3, i+1);
            //            factory.addNewOrder(keys[0], quantity, 5, isBuy, i + 4, i+1);
            //            factory.addNewOrder(keys[0], quantity, 6, isBuy, i + 5, i+1);
        }

        console.log("T1 BA MEDIO", tokenA.balanceOf(address(trader1)));
        console.log("T1 BB MEDIO", tokenB.balanceOf(address(trader1)));

        console.log("T2 BA MEDIO", tokenA.balanceOf(address(trader2)));
        console.log("T2 BB MEDIO", tokenB.balanceOf(address(trader2)));

        console.log("TC BA MEDIO", tokenA.balanceOf(address(factory)));
        console.log("TC BB MEDIO", tokenB.balanceOf(address(factory)));

        vm.stopPrank();

        vm.startPrank(trader1);
        uint256 startGas = gasleft();
        factory.addNewOrder(keys[0], 10e18, 50 * 10 ** 18, true, 11);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for adding Order: %d", gasUsed);
        vm.stopPrank();

        console.log("T1 BA", tokenA.balanceOf(address(trader1)));
        console.log("T1 BB", tokenB.balanceOf(address(trader1)));

        console.log("T2 BA", tokenA.balanceOf(address(trader2)));
        console.log("T2 BB", tokenB.balanceOf(address(trader2)));

        console.log("TC BA", tokenA.balanceOf(address(factory)));
        console.log("TC BB", tokenB.balanceOf(address(factory)));

        vm.startPrank(trader2);
        factory.withdrawBalanceTrader(keys[0], false);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(trader2)), 10e18, unicode"Trader2 debería tener 10 unidades de token A");
    }

    function testOneBuy100Sells() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        vm.startPrank(trader2);
        // Agregar ventas
        uint256 quantity = 1e18;
        bool isBuy = false;

        for (uint256 i = 1; i <= 50; i++) {
            // Generate a unique order ID
            bytes32 orderId = keccak256(abi.encodePacked(address(this), i));
            // Push the order into the queue
            factory.addNewOrder(keys[0], quantity, 2 * 10 ** 18, isBuy, i + 1);
            factory.addNewOrder(keys[0], quantity, 1 * 10 ** 18, isBuy, i);
            factory.addNewOrder(keys[0], quantity, 3 * 10 ** 18, isBuy, i + 2);
            factory.addNewOrder(keys[0], quantity, 4 * 10 ** 18, isBuy, i + 3);
            factory.addNewOrder(keys[0], quantity, 5 * 10 ** 18, isBuy, i + 4);
            factory.addNewOrder(keys[0], quantity, 6 * 10 ** 18, isBuy, i + 5);
        }

        vm.stopPrank();

        vm.startPrank(trader1);
        uint256 startGas = gasleft();
        factory.addNewOrder(keys[0], 100e18, 50 * 10 ** 18, true, 11);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for adding Order: %d", gasUsed);
        vm.stopPrank();

        //pair.getWithdrawBalance(trader1);
        vm.startPrank(trader2);
        factory.withdrawBalanceTrader(keys[0], false);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(trader2)), 150e18, unicode"Trader2 debería tener 150 unidades de token A");
    }

    function testOneSell10Buys() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        console.log("T1 BA INICIO", tokenA.balanceOf(address(trader1)));
        console.log("T1 BB INICIO", tokenB.balanceOf(address(trader1)));

        console.log("T2 BA INICIO", tokenA.balanceOf(address(trader2)));
        console.log("T2 BB INICIO", tokenB.balanceOf(address(trader2)));

        console.log("TC BA INICIO", tokenA.balanceOf(address(factory)));
        console.log("TC BB INICIO", tokenB.balanceOf(address(factory)));

        vm.startPrank(trader1);
        // Agregar compras
        uint256 quantity = 1;
        bool isBuy = true;

        for (uint256 i = 1; i <= 10; i++) {
            // Generate a unique order ID
            bytes32 orderId = keccak256(abi.encodePacked(address(this), i));
            // Push the order into the queue
            //            factory.addNewOrder(keys[0], quantity, 1, isBuy, i, i+1);
            //            factory.addNewOrder(keys[0], quantity, 5, isBuy, i + 1, i+1);
            //            factory.addNewOrder(keys[0], quantity, 10, isBuy, i + 2, i+1);
            //            factory.addNewOrder(keys[0], quantity, 20, isBuy, i + 3, i+1);
            //            factory.addNewOrder(keys[0], quantity, 30, isBuy, i + 4, i+1);
            factory.addNewOrder(keys[0], quantity, 50 * 1e18, isBuy, i + 5);
        }

        vm.stopPrank();

        console.log("T1 BA MEDIO", tokenA.balanceOf(address(trader1)));
        console.log("T1 BB MEDIO", tokenB.balanceOf(address(trader1)));

        console.log("T2 BA MEDIO", tokenA.balanceOf(address(trader2)));
        console.log("T2 BB MEDIO", tokenB.balanceOf(address(trader2)));

        console.log("TC BA MEDIO", tokenA.balanceOf(address(factory)));
        console.log("TC BB MEDIO", tokenB.balanceOf(address(factory)));

        vm.startPrank(trader2);
        uint256 startGas = gasleft();
        factory.addNewOrder(keys[0], 10, 1 * 1e18, false, 11);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for adding Order: %d", gasUsed);
        vm.stopPrank();

        console.log("T1 BA", tokenA.balanceOf(address(trader1)));
        console.log("T1 BB", tokenB.balanceOf(address(trader1)));

        console.log("T2 BA", tokenA.balanceOf(address(trader2)));
        console.log("T2 BB", tokenB.balanceOf(address(trader2)));

        console.log("TC BA", tokenA.balanceOf(address(factory)));
        console.log("TC BB", tokenB.balanceOf(address(factory)));
        //        assertEq(tokenA.balanceOf(address(trader2)), 10, unicode"Trader2 debería tener 10 unidades de token A");
    }

    function testSupuestamenteCorrecta() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        vm.startPrank(trader2);
        factory.addNewOrder(keys[0], 10, 50 * 1e18, false, 5);
        vm.stopPrank();

        vm.startPrank(trader1);
        factory.addNewOrder(keys[0], 10, 50 * 1e18, true, 11);
        vm.stopPrank();

    }

    function testSupuestamenteCorrecta2() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        console.log("T1 BA INICIO", tokenA.balanceOf(address(trader1)));
        console.log("T1 BB INICIO", tokenB.balanceOf(address(trader1)));

        console.log("T2 BA INICIO", tokenA.balanceOf(address(trader2)));
        console.log("T2 BB INICIO", tokenB.balanceOf(address(trader2)));

        console.log("TC BA INICIO", tokenA.balanceOf(address(factory)));
        console.log("TC BB INICIO", tokenB.balanceOf(address(factory)));

        vm.startPrank(trader1);
        factory.addNewOrder(keys[0], 10, 50 * 1e18, true, 5);
        vm.stopPrank();

        console.log("T1 BA MEDIO", tokenA.balanceOf(address(trader1)));
        console.log("T1 BB MEDIO", tokenB.balanceOf(address(trader1)));

        console.log("T2 BA MEDIO", tokenA.balanceOf(address(trader2)));
        console.log("T2 BB MEDIO", tokenB.balanceOf(address(trader2)));

        console.log("TC BA MEDIO", tokenA.balanceOf(address(factory)));
        console.log("TC BB MEDIO", tokenB.balanceOf(address(factory)));

        vm.startPrank(trader2);
        factory.addNewOrder(keys[0], 10, 50 * 1e18, false, 11);
        vm.stopPrank();

        console.log("T1 BA", tokenA.balanceOf(address(trader1)));
        console.log("T1 BB", tokenB.balanceOf(address(trader1)));

        console.log("T2 BA", tokenA.balanceOf(address(trader2)));
        console.log("T2 BB", tokenB.balanceOf(address(trader2)));

        console.log("TC BA", tokenA.balanceOf(address(factory)));
        console.log("TC BB", tokenB.balanceOf(address(factory)));
        //        assertEq(tokenA.balanceOf(address(trader2)), 10, unicode"Trader2 debería tener 10 unidades de token A");
    }

    /*function testCancelOrderNonExistentOrderBook() public {
        // Intentar cancelar una orden en un libro de órdenes que no existe
        bytes32 nonExistentOrderBookId = keccak256(abi.encodePacked(address(6), address(7)));

        vm.prank(trader);
        vm.expectRevert(OrderBookFactory.OBF__OrderBookIdOutOfRange.selector);
        factory.cancelOrder(nonExistentOrderBookId);
    }

    function testCancelOrderFromNonOwner() public {
        // Intentar cancelar una orden desde una cuenta no autorizada
        address nonOwner = address(6);

        vm.prank(nonOwner);
        vm.expectRevert("Caller is not authorized to cancel this order");
        factory.cancelOrder(orderBookId);
    }

    function testCancelOrderOnInactiveOrderBook() public {
        // Desactivar el libro de órdenes primero
        vm.prank(owner);
        factory.setPairStatus(orderBookId, false);

        // Intentar cancelar una orden en un libro de órdenes desactivado
        vm.prank(trader);
        vm.expectRevert("Order book is inactive");
        factory.cancelOrder(orderBookId);
    }

    function testCancelOrderAfterAlreadyCanceled() public {
        // Cancelar la orden una primera vez
        vm.prank(trader);
        factory.cancelOrder(orderBookId);

        // Intentar cancelar la misma orden de nuevo
        vm.prank(trader);
        vm.expectRevert("Order already canceled");
        factory.cancelOrder(orderBookId);
    }*/

    // -------------------- PRUEBAS VALORES LIMITES --------------------
    // Test: Revertir cuando la cantidad es 0
    function testAddOrderRevertOnZeroQuantity() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Agregar una nueva orden de compra
        uint256 quantity = 0;
        uint256 price = 100;
        bool isBuy = true;

        vm.prank(trader1);
        //vm.expectRevert(OrderBookFactory.OBF__InvalidQuantityValueZero.selector);
        vm.expectRevert(abi.encodeWithSelector(PairLib.PL__InvalidQuantity.selector, 0));
        factory.addNewOrder(keys[0], quantity, price, isBuy, 1);
    }

    // Test: Revertir cuando el id del libro de órdenes no existe
    function testAddOrderRevertOnInvalidOrderBookId() public {
        bytes32 invalidOrderBookKey = keccak256(abi.encodePacked("InvalidOrderBook"));
        // Agregar una nueva orden de compra
        uint256 quantity = 10;
        uint256 price = 100;
        bool isBuy = true;

        vm.prank(trader1);
        vm.expectRevert(OrderBookFactory.OBF__PairNotEnabled.selector);
        factory.addNewOrder(invalidOrderBookKey, quantity, price, isBuy, 1);
    }

    // Test: Agregar orden con cantidad mínima válida
    function testAddOrderWithMinQuantity() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Agregar una nueva orden de compra
        uint256 quantity = 1;
        uint256 price = 100 * 1e18;
        bool isBuy = true;

        vm.prank(trader1);
        factory.addNewOrder(keys[0], quantity, price, isBuy, 1);
    }

    // Test: Revertir cuando el precio es 0 (si el precio 0 es inválido)
    function testAddOrderRevertOnZeroPrice() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Agregar una nueva orden de compra
        uint256 quantity = 1;
        uint256 price = 0;
        bool isBuy = true;

        vm.prank(trader1);
        vm.expectRevert(); // Puedes ajustar el revert específico si tienes uno para este caso.
        factory.addNewOrder(keys[0], quantity, price, isBuy, 1);
    }

    function testPause() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        bytes32[] memory keys = factory.getPairIds();

        bytes32 pairId = keys[0];

        // Test pause functionality
        assertFalse(factory.paused());
        factory.pause();
        assertTrue(factory.paused());
        vm.stopPrank();
        vm.prank(trader2);
        // Attempt to add a new order while paused (should revert)
        vm.expectRevert(Pausable.EnforcedPause.selector);
        factory.addNewOrder(pairId, 100, 1000, true, block.timestamp);
    }

    function testUnpause() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        bytes32[] memory keys = factory.getPairIds();

        bytes32 pairId = keys[0];
        // First pause the contract
        factory.pause();
        assertTrue(factory.paused());

        // Now unpause
        factory.unpause();
        assertFalse(factory.paused());
        vm.stopPrank();
        vm.prank(trader1);
        // Verify that operations can be performed after unpausing
        factory.addNewOrder(pairId, 100, 1000 * 1e18, true, block.timestamp);
    }

    function testGetPairFee() public {
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        bytes32[] memory keys = factory.getPairIds();

        bytes32 pairId = keys[0];
        uint256 fee = factory.getPairFee(pairId);
        assertEq(fee, 5); // Assuming the initial fee was set to 10 in createOrderBook
    }

    function testGetTraderOrdersForPair() public {
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        bytes32[] memory keys = factory.getPairIds();

        bytes32 pairId = keys[0];
        // Add some orders for user1
        vm.startPrank(trader1);
        factory.addNewOrder(pairId, 10, 100 * 1e18, true, block.timestamp);
        factory.addNewOrder(pairId, 20, 110 * 1e18, true, block.timestamp);
        vm.stopPrank();

        bytes32[] memory orders = factory.getTraderOrdersForPair(pairId, trader1);
        assertEq(orders.length, 2);
    }

    function testGetOrderDetailForPair() public {
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        bytes32[] memory keys = factory.getPairIds();

        bytes32 pairId = keys[0];

        // Add an order
        vm.startPrank(trader1);
        factory.addNewOrder(pairId, 10, 100 * 1e18, true, block.timestamp);
        vm.stopPrank();

        bytes32[] memory orders = factory.getTraderOrdersForPair(pairId, trader1);
        require(orders.length > 0, "No orders found");

        OrderBookLib.Order memory order = factory.getOrderDetailForPair(pairId, orders[0]);
        assertEq(order.quantity, 10);
        assertEq(order.price, 100 * 1e18);
        assertTrue(order.isBuy);
    }

    function testGetTop50BuyPricesForPair() public {
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        bytes32[] memory keys = factory.getPairIds();

        bytes32 pairId = keys[0];
        // Add some buy orders
        vm.startPrank(trader1);
        factory.addNewOrder(pairId, 10, 100 * 1e18, true, block.timestamp);
        factory.addNewOrder(pairId, 10, 110 * 1e18, true, block.timestamp);
        factory.addNewOrder(pairId, 10, 120 * 1e18, true, block.timestamp);
        factory.addNewOrder(pairId, 10, 90 * 1e18, true, block.timestamp);
        vm.stopPrank();
        uint256[50] memory topPrices = factory.getTop50BuyPricesForPair(pairId);
        assertEq(topPrices[0], 120 * 1e18);
        assertEq(topPrices[1], 110 * 1e18);
        assertEq(topPrices[2], 100 * 1e18);
    }

    function testGetTop50SellPricesForPair() public {
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        bytes32[] memory keys = factory.getPairIds();

        bytes32 pairId = keys[0];
        // Add some sell orders
        vm.startPrank(trader2);
        factory.addNewOrder(pairId, 10e18, 10e18, false, block.timestamp);
        factory.addNewOrder(pairId, 10e18, 11e18, false, block.timestamp);
        factory.addNewOrder(pairId, 10e18, 12e18, false, block.timestamp);
        factory.addNewOrder(pairId, 10e18, 9e18, false, block.timestamp);
        vm.stopPrank();
        uint256[50] memory topPrices = factory.getTop50SellPricesForPair(pairId);
        assertEq(topPrices[0], 9e18);
        assertEq(topPrices[1], 10e18);
        assertEq(topPrices[2], 11e18);
    }

    function testGetPricePointDataForPair() public {
        vm.prank(owner);
        factory.addPair(address(tokenA), address(tokenB), 5, feeAddress);

        bytes32[] memory keys = factory.getPairIds();

        bytes32 pairId = keys[0];
        // Add some buy orders at the same price
        vm.startPrank(trader1);
        factory.addNewOrder(pairId, 10, 100 * 1e18, true, block.timestamp);
        factory.addNewOrder(pairId, 20, 100 * 1e18, true, block.timestamp + 1);
        vm.stopPrank();
        (uint256 orderCount, uint256 orderValue) = factory.getPricePointDataForPair(pairId, 100 * 1e18, true);
        assertEq(orderCount, 2);
        assertEq(orderValue, 30);
    }

    function testRevertOnNonExistantPair() public {
        vm.startPrank(trader2);
        bytes32 pairId = keccak256(abi.encodePacked("NonExistantPair"));
        bytes32 orderId = keccak256(abi.encodePacked("TestOrder"));

        vm.expectRevert(OrderBookFactory.OBF__PairNotEnabled.selector);
        factory.addNewOrder(pairId, 10, 100, true, block.timestamp);

        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        factory.cancelOrder(pairId, orderId);

        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        factory.getPairFee(pairId);

        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        factory.getTraderOrdersForPair(pairId, trader2);

        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        factory.getOrderDetailForPair(pairId, orderId);

        vm.stopPrank();
    }

    function testAddMatchingOrdersCheckAndWithdraw() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Agregar una nueva orden de compra
        uint256 quantity = 10;
        uint256 price = 100 * 1e18;
        bool isBuy = true;

        vm.prank(trader1);
        factory.addNewOrder(keys[0], quantity, price, isBuy, 1);

        // Add matching sell order
        vm.prank(trader2);
        factory.addNewOrder(keys[0], quantity, price, !isBuy, 2);

        PairLib.TraderBalance memory tb1 = factory.checkBalanceTrader(keys[0], trader1);

        assertEqUint(10, tb1.baseTokenBalance);

        vm.prank(trader1);
        factory.withdrawBalanceTrader(keys[0], true);

        assertEqUint(10, tokenB.balanceOf(trader1));

        // Now sell 5 of the 10 bought

        vm.prank(trader1);
        factory.addNewOrder(keys[0], 5, price, !isBuy, 3);

        // Add matching sell order
        vm.prank(trader2);
        factory.addNewOrder(keys[0], 5, price, isBuy, 4);

        tb1 = factory.checkBalanceTrader(keys[0], trader1);

        assertEqUint(500, tb1.quoteTokenBalance);
        uint256 prevBalanceT1 = tokenA.balanceOf(trader1);

        vm.prank(trader1);
        factory.withdrawBalanceTrader(keys[0], false);

        uint256 finalBalanceT1 = tokenA.balanceOf(trader1);

        assertEqUint(500, finalBalanceT1 - prevBalanceT1);

        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        tb1 = factory.checkBalanceTrader("0x1", trader1);

        vm.prank(trader1);
        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        factory.withdrawBalanceTrader("0x1", false);
    }

    //---------------

//    function testPauseUnpause() public {
//        vm.prank(owner);
//        factory.pause();
//
//        // Verificar que las operaciones están pausadas
//        vm.expectRevert();
//        factory.addNewOrder(pair, 100, 1e18, true, block.timestamp);
//
//        vm.prank(owner);
//        factory.unpause();
//
//        // Verificar que las operaciones funcionan nuevamente
//        factory.addNewOrder(pairId, 100, 1e18, true, block.timestamp);
//    }

    function testWithdrawFeeBalanceOwner() public {
        // Configurar fees acumulados
        // Testear retiro exitoso
        // Testear retiro cuando balance es 0
    }

    function testAddMatchingOrdersCheckAndWithdrawFee() public {
        vm.startPrank(owner);
        factory.addPair(address(tokenA), address(tokenB), 10, feeAddress);
        vm.stopPrank();

        // Obtener las claves de los libros de órdenes
        bytes32[] memory keys = factory.getPairIds();

        // Verificar que hay exactamente una clave
        assertEq(keys.length, 1, unicode"Debería haber dos claves en el array");

        // Agregar una nueva orden de compra
        uint256 quantity = 10;
        uint256 price = 100 * 1e18;
        bool isBuy = true;

        vm.prank(trader1);
        factory.addNewOrder(keys[0], quantity, price, isBuy, 1);

        // Add matching sell order
        vm.prank(trader2);
        factory.addNewOrder(keys[0], quantity, price, !isBuy, 2);

        PairLib.TraderBalance memory tb1 = factory.checkBalanceTrader(keys[0], trader1);

        assertEqUint(10, tb1.baseTokenBalance);

        vm.prank(trader1);
        factory.withdrawBalanceTrader(keys[0], true);

        assertEqUint(10, tokenB.balanceOf(trader1));

        // Now sell 5 of the 10 bought

        vm.prank(trader1);
        factory.addNewOrder(keys[0], 5, price, !isBuy, 3);

        // Add matching sell order
        vm.prank(trader2);
        factory.addNewOrder(keys[0], 5, price, isBuy, 4);

        tb1 = factory.checkBalanceTrader(keys[0], trader1);

        assertEqUint(500, tb1.quoteTokenBalance);
        uint256 prevBalanceT1 = tokenA.balanceOf(trader1);

        vm.prank(trader1);
        factory.withdrawBalanceTrader(keys[0], false);

        uint256 finalBalanceT1 = tokenA.balanceOf(trader1);

        assertEqUint(500, finalBalanceT1 - prevBalanceT1);

        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        tb1 = factory.checkBalanceTrader("0x1", trader1);

        vm.prank(trader1);
        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        factory.withdrawBalanceTrader("0x1", false);

        uint256 balanceFeeAddressTokenA = tokenA.balanceOf(feeAddress);
        uint256 balanceFeeAddressTokenB = tokenB.balanceOf(feeAddress);

        uint256 tbFeeBase;
        uint256 tbFeeQuote;

        vm.prank(trader2);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, trader2));
        (tbFeeBase, tbFeeQuote )= factory.checkBalanceFeeTrader("0x1");

        vm.prank(owner);
        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        (tbFeeBase, tbFeeQuote )= factory.checkBalanceFeeTrader("0x1");

        vm.prank(owner);
        (tbFeeBase, tbFeeQuote )= factory.checkBalanceFeeTrader(keys[0]);

        vm.prank(owner);
        vm.expectRevert(OrderBookFactory.OBF__PairDoesNotExist.selector);
        factory.withdrawFeeBalanceOwner("0x1", false);

        vm.prank(trader2);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, trader2));
        factory.withdrawFeeBalanceOwner(keys[0], false);

        vm.prank(owner);
        factory.withdrawFeeBalanceOwner(keys[0], false);

        uint256 balanceFeeAddressAfterWithdrawTokenA = tokenA.balanceOf(feeAddress);
        uint256 balanceFeeAddressAfterWithdrawTokenB = tokenB.balanceOf(feeAddress);

        assert(balanceFeeAddressAfterWithdrawTokenA > balanceFeeAddressTokenA);
    }

//    function testGetPairFee() public {
//        vm.prank(owner);
//        factory.addPair(address(tokenA), address(tokenB), 150, feeAddress);
//
//        bytes32[] memory keys = factory.getPairIds();
//        uint256 fee = factory.getPairFee(keys[0]);
//        assertEq(fee, 150);
//    }
}
