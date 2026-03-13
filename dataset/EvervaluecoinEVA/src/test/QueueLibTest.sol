// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/QueueLib.sol";
import "forge-std/console.sol";

contract QueueLibTest is Test {
    using QueueLib for QueueLib.Queue;

    QueueLib.Queue private queue;

    address private trader1 = makeAddr("trader1");
    address private trader2 = makeAddr("trader2");
    address private trader3 = makeAddr("trader3");

    bytes32 private orderId1 = keccak256(abi.encodePacked(trader1, "buy", "100", block.timestamp));
    bytes32 private orderId2 = keccak256(abi.encodePacked(trader2, "sell", "200", block.timestamp));
    bytes32 private orderId3 = keccak256(abi.encodePacked(trader3, "buy", "300", block.timestamp));

    // Initialization
    function testInitialQueueIsEmpty() public view {
        assertTrue(queue.isEmpty(), "Queue should be empty initially");
    }

    // Item Existence
    function testItemExistsAfterAdding() public {
        queue.push(orderId1);
        assertTrue(queue.itemExists(orderId1), "Order should exist after being added");
    }

    function testItemDoesNotExistIfNotAdded() public view {
        assertFalse(queue.itemExists(orderId1), "Order should not exist if it has not been added");
    }

    function testItemDoesNotExistAfterRemoving() public {
        queue.push(orderId1);
        queue.remove(orderId1);
        assertFalse(queue.itemExists(orderId1), "Order should not exist after being removed");
    }

    // Queue Emptiness
    function testQueueNotEmptyAfterAddingElement() public {
        queue.push(orderId1);
        assertFalse(queue.isEmpty(), "Queue should not be empty after adding an element");
    }

    function testQueueEmptyAfterRemovingAllElements() public {
        queue.push(orderId1);
        queue.remove(queue.first);
        assertTrue(queue.isEmpty(), "Queue should be empty after removing all elements");
    }

    function testQueueNotEmptyAfterRemovingFirstElement() public {
        queue.push(orderId1);
        queue.push(orderId2);
        queue.remove(orderId1);
        assertFalse(queue.isEmpty(), "Queue should not be empty after removing the first element");
        assertEq(queue.first, orderId2, "First element should be orderId2 after removing orderId1");
    }

    function testQueueEmptinessAfterRemovingVariousElements() public {
        queue.push(orderId1);
        queue.push(orderId2);
        queue.push(orderId3);

        queue.remove(orderId2);
        assertFalse(queue.isEmpty(), "Queue should not be empty after removing middle element");

        queue.remove(orderId3);
        assertFalse(queue.isEmpty(), "Queue should not be empty after removing last element");

        queue.remove(orderId1);
        assertTrue(queue.isEmpty(), "Queue should be empty after removing all elements");
    }

    // Push Operations
    function testPushToEmptyQueue() public {
        queue.push(orderId1);
        assertFalse(queue.isEmpty(), "Queue should not be empty after pushing an element");
        assertTrue(queue.itemExists(orderId1), "orderId1 should exist in the queue");
        assertEq(queue.first, orderId1, "First element should be orderId1");
        assertEq(queue.last, orderId1, "Last element should be orderId1");
    }

    function testPushSecondOrder() public {
        queue.push(orderId1);
        queue.push(orderId2);
        assertFalse(queue.isEmpty(), "Queue should not be empty after pushing elements");
        assertTrue(queue.itemExists(orderId1), "orderId1 should exist in the queue");
        assertTrue(queue.itemExists(orderId2), "orderId2 should exist in the queue");
        assertEq(queue.first, orderId1, "First element should be orderId1");
        assertEq(queue.last, orderId2, "Last element should be orderId2");
    }

    function testPushMultipleOrders() public {
        queue.push(orderId1);
        queue.push(orderId2);
        queue.push(orderId3);

        assertEq(queue.first, orderId1, "First element should be orderId1");
        assertEq(queue.last, orderId3, "Last element should be orderId3");

        assertEq(queue.items[orderId1].next, orderId2, "Next of orderId1 should be orderId2");
        assertEq(queue.items[orderId2].next, orderId3, "Next of orderId2 should be orderId3");
        assertEq(queue.items[orderId2].prev, orderId1, "Prev of orderId2 should be orderId1");
        assertEq(queue.items[orderId3].prev, orderId2, "Prev of orderId3 should be orderId2");
    }

    function testQueueStateAfterPush() public {
        assertEq(queue.first, 0, "Initial first pointer should be zero");
        assertEq(queue.last, 0, "Initial last pointer should be zero");

        queue.push(orderId1);
        queue.push(orderId2);

        assertEq(queue.first, orderId1, "First order ID should be updated to orderId1");
        assertEq(queue.last, orderId2, "Last order ID should be updated to orderId2");
        assertEq(queue.items[orderId1].next, orderId2, "Next pointer of orderId1 should point to orderId2");
        assertEq(queue.items[orderId2].prev, orderId1, "Prev pointer of orderId2 should point to orderId1");
    }

    // Remove Operations
    function testRemoveMiddleOrder() public {
        queue.push(orderId1);
        queue.push(orderId2);
        queue.push(orderId3);

        queue.remove(orderId2);
        assertFalse(queue.itemExists(orderId2), "orderId2 should not exist after removal");
        assertEq(queue.items[orderId1].next, orderId3, "Next of orderId1 should be orderId3 after removing orderId2");
        assertEq(queue.items[orderId3].prev, orderId1, "Prev of orderId3 should be orderId1 after removing orderId2");
    }

    function testRemoveFirstOrder() public {
        queue.push(orderId1);
        queue.push(orderId2);

        queue.remove(orderId1);
        assertFalse(queue.itemExists(orderId1), "orderId1 should not exist after removal");
        assertEq(queue.first, orderId2, "First element should be orderId2 after removing orderId1");
    }

    function testRemoveLastOrder() public {
        queue.push(orderId1);
        queue.push(orderId2);
        queue.push(orderId3);

        queue.remove(orderId3);
        assertFalse(queue.itemExists(orderId3), "orderId3 should not exist after removal");
        assertEq(queue.last, orderId2, "Last element should be orderId2 after removing orderId3");
    }

    function testRemoveFromEmptyQueueReverts() public {
        vm.expectRevert(QueueLib.QL__EmptyQueue.selector);
        queue.remove(orderId1);
    }

    function testMultipleRemovals() public {
        queue.push(orderId1);
        queue.push(orderId2);
        queue.push(orderId3);

        queue.remove(orderId2);
        queue.remove(orderId1);

        assertEq(queue.first, orderId3, "First should be orderId3 after removing orderId1 and orderId2");
        assertEq(queue.last, orderId3, "Last should be orderId3 after removing orderId1 and orderId2");
        assertEq(queue.items[orderId3].next, 0, "Next pointer of the last node should be 0");
        assertEq(queue.items[orderId3].prev, 0, "Prev pointer of the last node should be 0");
    }

    // Edge Cases
    function testPushInvalidItem() public {
        vm.expectRevert(QueueLib.QL__ItemAlreadyExists.selector);
        queue.push(bytes32(0));

        bytes32 validId = bytes32(uint256(1));
        queue.push(validId);

        vm.expectRevert(QueueLib.QL__ItemAlreadyExists.selector);
        queue.push(validId);
    }

    function testRemoveNonExistentItem() public {
        bytes32 validId = bytes32(uint256(1));
        queue.push(validId);

        vm.expectRevert(QueueLib.QL__ItemDoesNotExist.selector);
        queue.remove(bytes32(uint256(2)));
    }
}
