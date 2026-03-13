// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./RedBlackTreeImpl.sol";

abstract contract RedBlackTreeHelper is Test {
    RedBlackTreeImpl public tree;

    uint256 internal price = 10;
    uint256 internal numOrders = 0;
    uint256 internal halfwayPrice = 0;
}

/// @title EmptyTreeTest
/// @notice Test contract for performance testing of an empty Red-Black Tree
/// @dev Inherits from RedBlackTreeHelper to utilize common setup and utilities
contract EmptyTreeTest is RedBlackTreeHelper {
    //---------  SET UP

    /// @notice Set up the test environment
    /// @dev Initializes a new RedBlackTreeImpl instance for each test
    function setUp() public {
        tree = new RedBlackTreeImpl();
    }

    //---------   Tree Tests

    /// @notice Test the gas cost of inserting a node into an empty Red-Black Tree
    /// @dev This function measures the gas used to insert a single node into an empty tree
    function testInsertion() public {
        uint256 startGas = gasleft();
        tree.insert(price);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for inserting node on empty tree: %d", gasUsed);
    }

    /// @notice Test the gas cost of attempting to remove a non-existent node from an empty Red-Black Tree
    /// @dev This function measures the gas used when trying to remove a node that doesn't exist,
    ///      expecting a revert with the RedBlackTree__KeyDoesNotExist error
    function testRemove() public {
        uint256 startGas = gasleft();
        vm.expectRevert(RedBlackTreeLib.RBT__NodeDoesNotExist.selector);
        tree.remove( price);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for removing node on empty tree: %d", gasUsed);
    }
}

/// @title SmallTreeTest
/// @notice Test contract for performance testing of a small Red-Black Tree
/// @dev Inherits from RedBlackTreeHelper to utilize common setup and utilities
contract SmallTreeTest is RedBlackTreeHelper {
    //---------  SET UP

    /// @notice Set up the test environment with a small tree
    /// @dev Initializes a new RedBlackTreeImpl instance and inserts 10 orders
    function setUp() public virtual {
        tree = new RedBlackTreeImpl();
        numOrders = 10;
        halfwayPrice = numOrders;

        bytes32[] memory orderIds = new bytes32[](numOrders);

        /// @dev Insert 10 orders with increasing prices
        for (uint256 i = 1; i <= numOrders; i++) {
            bytes32 orderId = keccak256(abi.encodePacked(address(this), i * 2));
            orderIds[i - 1] = orderId;
            tree.insert( i * 2);
        }
    }

    //---------   Tree Tests

    /// @notice Test the gas cost of inserting a node in the middle of the Red-Black Tree
    /// @dev This function measures the gas used to insert a single node at the halfway price point
    /// @custom:gas-test Insertion performance for middle node
    function testInsertionMiddle() public {
        uint256 startGas = gasleft();
        tree.insert(halfwayPrice);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for inserting node in the middle of tree: %d", gasUsed);
    }

    /// @notice Test the gas cost of inserting a node at the beginning of the Red-Black Tree
    /// @dev This function measures the gas used to insert a single node with the lowest price
    /// @custom:gas-test Insertion performance for the first node
    function testInsertionFirst() public {
        uint256 startGas = gasleft();
        tree.insert(1);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for inserting first node on tree: %d", gasUsed);
    }

    /// @notice Test the gas cost of inserting a node at the end of the Red-Black Tree
    /// @dev This function measures the gas used to insert a single node with the highest price
    /// @custom:gas-test Insertion performance for the last node
    function testInsertionLast() public {
        uint256 startGas = gasleft();
        tree.insert( numOrders * 10);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for inserting last node on tree: %d", gasUsed);
    }

    /// @notice Test the gas cost of removing a node from the middle of the Red-Black Tree
    /// @dev This function inserts a node at the halfway price, then measures the gas used to remove it
    /// @custom:gas-test Removal performance for a middle node
    function testRemove() public {
        tree.insert(halfwayPrice);
        uint256 startGas = gasleft();
        tree.remove( halfwayPrice);
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for removing node on tree: %d", gasUsed);
    }

    /// @notice Test the gas cost of removing the first node from the Red-Black Tree
    /// @dev This function inserts a node with the lowest price, then measures the gas used to remove it
    /// @custom:gas-test Removal performance for the first node
    function testRemoveFirst() public {
        tree.insert( 1);
        uint256 startGas = gasleft();
        tree.remove(tree.first());
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for removing first node on tree: %d", gasUsed);
    }

    /// @notice Test the gas cost of removing the last node from the Red-Black Tree
    /// @dev This function inserts a node with the highest price, then measures the gas used to remove it
    /// @custom:gas-test Removal performance for the last node
    function testRemoveLast() public {
        tree.insert(numOrders * 10);
        uint256 startGas = gasleft();
        tree.remove(tree.last());
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for removing node on tree: %d", gasUsed);
    }

    /// @notice Test the gas cost of retrieving the first node in the Red-Black Tree
    /// @dev This function measures the gas used to call the `first()` function on the tree
    /// @custom:gas-test Performance test for retrieving the first node
    function testFirst() public {
        uint256 startGas = gasleft();
        tree.first();
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used to get first node on  tree: %d", gasUsed);
    }

    /// @notice Test the gas cost of retrieving the last node in the Red-Black Tree
    /// @dev This function measures the gas used to call the `last()` function on the tree
    /// @custom:gas-test Performance test for retrieving the last node
    function testLast() public {
        uint256 startGas = gasleft();
        tree.last();
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used to get last node on  tree: %d", gasUsed);
    }

    /// @notice Test the gas cost of popping half of the nodes from the left side of the Red-Black Tree
    /// @dev This function measures the gas used to pop nodes with prices less than the halfway price
    /// @custom:gas-test Performance test for popping multiple nodes from the left side
    function testRemoveHalfLeft() public {
        uint256 startGas = gasleft();
        uint256 count = 0;
        while (tree.first() != 0 && tree.first() < halfwayPrice) {
            tree.remove(tree.first());
            ++count;
        }
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used to pop half from the left of tree: %d . Popped orders: %d", gasUsed, count);
    }

    /// @notice Test the gas cost of popping half of the nodes from the right side of the Red-Black Tree
    /// @dev This function measures the gas used to pop nodes with prices greater than the halfway price
    /// @custom:gas-test Performance test for popping multiple nodes from the right side
    function testRemoveHalfRight() public {
        uint256 startGas = gasleft();
        uint256 count = 0;
        while (tree.last() != 0 && tree.last() > halfwayPrice) {
            tree.remove(tree.last());
            ++count;
        }
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used to pop half from the right of tree: %d  . Popped orders: %d", gasUsed, count);
    }
}

/// @title LargeTreeTest
/// @notice Test contract for performance testing of a large Red-Black Tree
/// @dev Inherits from SmallTreeTest and overrides setUp to create a larger tree
contract LargeTreeTest is SmallTreeTest {
    //---------  SET UP

    /// @notice Set up the test environment with a large Red-Black Tree
    /// @dev Overrides the setUp function from SmallTreeTest to create a tree with 100 nodes
    function setUp() public override {
        tree = new RedBlackTreeImpl();
        numOrders = 100;
        halfwayPrice = numOrders;

        bytes32[] memory orderIds = new bytes32[](numOrders);

        /// @dev Insert 100 orders with increasing prices
        for (uint256 i = 1; i <= numOrders; i++) {
            bytes32 orderId = keccak256(abi.encodePacked(address(this), i * 2));
            orderIds[i - 1] = orderId;
            tree.insert( i * 2);
        }
    }
}
