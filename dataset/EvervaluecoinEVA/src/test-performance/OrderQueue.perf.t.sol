// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./OrderQueueImpl.sol";
import "../src/QueueLib.sol";
import "../src/QueueLib.sol";

/// @title QueueHelper
/// @notice Abstract contract providing helper variables for queue testing
/// @dev This contract is used as a base for various queue test contracts
abstract contract QueueHelper {
    /// @notice Instance of the OrderQueueImpl contract
    OrderQueueImpl public queue;

    /// @notice Total number of orders in the queue
    uint256 internal numOrders;

    /// @notice Index representing the halfway point in the queue
    uint256 internal halfPoint;

    /// @notice Order ID at the halfway point in the queue
    bytes32 internal halfPointOrderId;
}

/// @title EmptyQueueTest
/// @notice Test contract for empty queue scenarios
/// @dev Inherits from Test and QueueHelper to utilize testing utilities and queue helper functions
contract EmptyQueueTest is Test, QueueHelper {
    /// @notice Set up the test environment
    /// @dev Initializes the queue and sets initial values for numOrders and halfPoint
    function setUp() public {
        queue = new OrderQueueImpl();
        numOrders = 0;
        halfPoint = 0;
    }

    //---------   Queue Tests

    /// @notice Test the performance of the isEmpty() function on an empty queue
    /// @dev Measures the gas cost of calling isEmpty() on an empty queue
    function testIsEmpty() public {
        uint256 startGas = gasleft();
        bool isEmpty = queue.isEmpty();
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for isEmpty on empty queue: %d", gasUsed);
    }

    /// @notice Test the performance of the orderExists() function on an empty queue
    /// @dev Measures the gas cost of calling orderExists() for a non-existent order in an empty queue
    function testOrderExists() public {
        bytes32 orderId = keccak256(abi.encodePacked(address(this), uint256(1)));
        uint256 startGas = gasleft();
        bool exists = queue.orderExists(orderId);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for orderExists on empty queue: %d", gasUsed);
    }

    /// @notice Test the performance of pushing an order to an empty queue
    /// @dev Measures the gas cost of calling push() to add a new order to an empty queue
    function testPush() public {
        uint256 orderNumber = numOrders + 1;
        bytes32 orderId = keccak256(abi.encodePacked(address(this), orderNumber));
        uint256 startGas = gasleft();
        uint256 price = 1;
        uint256 quantity = 100;
        queue.push( orderId);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for pushing order on empty queue: %d", gasUsed);
    }

    /// @notice Test the performance of popping an order from a queue with one element
    /// @dev This function first pushes an order to the queue and then measures the gas cost of popping it
    function testPop() public {
        // Now, test pop
        uint256 startGas = gasleft();
        vm.expectRevert(QueueLib.OrderQueue__CantRemoveFromAnEmptyQueue.selector);
        queue.pop();
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for trying to pop an order from queue with one element: %d", gasUsed);
    }

    /// @notice Test the performance of removing an order from an empty queue
    /// @dev This function attempts to remove a non-existent order from an empty queue and measures the gas cost
    /// @custom:gas-test This function measures gas usage for the removeOrder operation
    function testRemoveOrder() public {
        // First, push an order
        uint256 orderNumber = numOrders + 1;
        bytes32 orderId = keccak256(abi.encodePacked(address(this), orderNumber));

        // Now, test removeOrder
        uint256 startGas = gasleft();
        vm.expectRevert(QueueLib.OrderQueue__CantRemoveFromAnEmptyQueue.selector);
        queue.removeOrder(orderId);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for trying to remove an order from queue with one element: %d", gasUsed);
    }
}

/// @title SmallQueueTest
/// @notice Test contract for small queue scenarios
/// @dev Inherits from Test and QueueHelper to utilize testing utilities and queue helper functions
contract SmallQueueTest is Test, QueueHelper {
    //---------  SET UP

    /// @notice Set up the test environment for a small queue
    /// @dev Initializes the queue with 10 orders and sets up related variables
    function setUp() public virtual {
        // Initialize the queue
        queue = new OrderQueueImpl();
        // Set the number of orders and halfway point
        numOrders = 10;
        halfPoint = 5;
        // Create an array to store order IDs
        bytes32[] memory orderIds = new bytes32[](numOrders);

        // Push 10 orders into the queue
        for (uint256 i = 0; i < numOrders; i++) {
            // Generate a unique order ID
            bytes32 orderId = keccak256(abi.encodePacked(address(this), i));
            orderIds[i] = orderId;
            if (i == halfPoint) halfPointOrderId = orderId;
            // Push the order into the queue
            queue.push( orderId);
        }
    }

    //---------   Queue Tests

    /// @notice Test the performance of the isEmpty() function on a small queue
    /// @dev Measures the gas cost of calling isEmpty() on a queue with 10 elements
    /// @custom:gas-test This function measures gas usage for the isEmpty operation
    function testIsEmpty() public {
        uint256 startGas = gasleft();
        bool isEmpty = queue.isEmpty();
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for isEmpty on queue: %d", gasUsed);
    }

    /// @notice Test the performance of the orderExists() function on a small queue
    /// @dev Measures the gas cost of calling orderExists() for an order at the halfway point of a queue with 10 elements
    /// @custom:gas-test This function measures gas usage for the orderExists operation
    function testOrderExists() public {
        uint256 startGas = gasleft();
        bool exists = queue.orderExists(halfPointOrderId);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for orderExists on queue: %d", gasUsed);
    }

    /// @notice Test the performance of pushing an order to a small queue
    /// @dev Measures the gas cost of calling push() to add a new order to a queue with 10 existing elements
    /// @custom:gas-test This function measures gas usage for the push operation on a small queue
    function testPush() public {
        uint256 orderNumber = numOrders + 1;
        bytes32 orderId = keccak256(abi.encodePacked(address(this), orderNumber));
        uint256 startGas = gasleft();
        uint256 quantity = 100;
        queue.push(orderId);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for pushing order on queue: %d", gasUsed);
    }

    /// @notice Test the performance of popping an order from a small queue
    /// @dev Measures the gas cost of calling pop() to remove an order from a queue with 10 existing elements
    /// @custom:gas-test This function measures gas usage for the pop operation on a small queue
    function testPop() public {
        uint256 startGas = gasleft();
        queue.pop();
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for popping an order from queue: %d", gasUsed);
    }

    /// @notice Test the performance of removing an order from a small queue
    /// @dev Measures the gas cost of calling removeOrder() to remove a specific order from a queue with 10 existing elements
    /// @custom:gas-test This function measures gas usage for the removeOrder operation on a small queue
    function testRemoveOrder() public {
        uint256 startGas = gasleft();
        queue.removeOrder(halfPointOrderId);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for removing order from queue: %d", gasUsed);
    }

    /// @notice Test the performance of popping half of the orders from a small queue
    /// @dev Measures the gas cost of calling pop() multiple times to remove half of the orders from a queue with 10 existing elements
    /// @custom:gas-test This function measures cumulative gas usage for multiple pop operations on a small queue
    function testPopHalf() public {
        uint256 startGas = gasleft();
        for (uint256 i = 0; i < halfPoint; i++) {
            queue.pop();
        }
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for popping half of the queue: %d", gasUsed);
    }
}

/// @title LargeQueueTest
/// @notice Test contract for large queue scenarios
/// @dev Inherits from SmallQueueTest to reuse test functions while overriding the setUp function for a larger queue
/// @custom:gas-test This contract contains gas usage tests for operations on a large queue
contract LargeQueueTest is SmallQueueTest {
    //---------  SET UP

    /// @notice Set up the test environment for a large queue
    /// @dev Initializes the queue with 100 orders and sets up related variables
    function setUp() public override {
        // Initialize the queue
        queue = new OrderQueueImpl();
        // Set the number of orders and halfway point
        numOrders = 1000;
        halfPoint = 500;
        // Create an array to store order IDs
        bytes32[] memory orderIds = new bytes32[](numOrders);

        // Push 100 orders into the queue
        for (uint256 i = 0; i < numOrders; i++) {
            // Generate a unique order ID
            bytes32 orderId = keccak256(abi.encodePacked(address(this), i));
            orderIds[i] = orderId;
            if (i == halfPoint) halfPointOrderId = orderId;
            // Push the order into the queue
            queue.push(orderId);
        }
    }
}
