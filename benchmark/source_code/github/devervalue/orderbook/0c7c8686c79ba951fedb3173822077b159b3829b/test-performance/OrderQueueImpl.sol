// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/QueueLib.sol";
import "forge-std/console.sol";

/**
 * @title OrderQueueImpl
 * @dev Implementation of an order queue using the OrderQueue library.
 * @notice This contract provides an interface to interact with an order queue.
 */
contract OrderQueueImpl {
    using QueueLib for OrderQueue.Queue;
    using QueueLib for OrderQueue.OrderBookNode;

    /// @dev The internal queue structure
    OrderQueue.Queue private queue;

    /**
     * @dev Constructor for OrderQueueImpl
     * @notice Initializes an empty order queue
     */
    constructor() {}

    /**
     * @notice Retrieves the ID of the first order in the queue
     * @dev This function returns the ID of the order at the front of the queue
     * @return _first The bytes32 ID of the first order in the queue
     */
    function queueFirst() public view returns (bytes32 _first) {
        _first = queue.first;
    }

    /**
     * @notice Retrieves the ID of the last order in the queue
     * @dev This function returns the ID of the order at the end of the queue
     * @return _last The bytes32 ID of the last order in the queue
     */
    function queueLast() public view returns (bytes32 _last) {
        _last = queue.last;
    }

    /**
     * @notice Checks if a specific order exists in the queue
     * @dev This function verifies the existence of an order using its ID
     * @param _orderId The bytes32 ID of the order to check
     * @return _exists A boolean indicating whether the order exists (true) or not (false)
     */
    function orderExists(bytes32 _orderId) public view returns (bool _exists) {
        _exists = queue.orderExists(_orderId);
    }

    /**
     * @notice Checks if the order queue is empty
     * @dev This function returns true if there are no orders in the queue, false otherwise
     * @return _empty A boolean indicating whether the queue is empty (true) or not (false)
     */
    function isEmpty() public view returns (bool _empty) {
        _empty = queue.isEmpty();
    }

    /**
     * @notice Adds a new order to the queue
     * @dev Pushes a new order with the given parameters to the end of the queue
     * @param _orderId A unique identifier for the order
     */
    function push(
        bytes32 _orderId
    ) public {
        queue.push(_orderId);
    }

    /**
     * @notice Removes and returns the first order from the queue
     * @dev This function pops the first order from the queue and returns it
     */
    function pop() public {
        queue.removeOrder(queue.first);
    }

    /**
     * @notice Removes a specific order from the queue
     * @dev This function removes an order with the given ID from the queue, if it exists
     * @param _orderId The bytes32 ID of the order to be removed
     */
    function removeOrder(bytes32 _orderId) public {
        queue.removeOrder(_orderId);
    }
}
