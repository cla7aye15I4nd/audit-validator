# QueueLib
[Git Source](https://github.com/artechsoft/orderbook/blob/bbd55f017f77567506e5700d9133d68be9d96234/src/QueueLib.sol)


## Functions
### itemExists

Check if an item exists in the queue.


```solidity
function itemExists(Queue storage q, bytes32 _itemId) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`q`|`Queue`|The queue to check.|
|`_itemId`|`bytes32`|The ID of the item to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if the item exists, false otherwise.|


### isEmpty

Check if the queue is empty.


```solidity
function isEmpty(Queue storage q) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`q`|`Queue`|The queue to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if the queue is empty, false otherwise.|


### push

Push a new item to the end of the queue.


```solidity
function push(Queue storage q, bytes32 _itemId) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`q`|`Queue`|The queue to push to.|
|`_itemId`|`bytes32`|The ID of the item to push.|


### remove

Remove an item from the queue.


```solidity
function remove(Queue storage q, bytes32 _itemId) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`q`|`Queue`|The queue to remove from.|
|`_itemId`|`bytes32`|The ID of the item to remove.|


## Errors
### QL__EmptyQueue

```solidity
error QL__EmptyQueue();
```

### QL__ItemAlreadyExists

```solidity
error QL__ItemAlreadyExists();
```

### QL__ItemDoesNotExist

```solidity
error QL__ItemDoesNotExist();
```

## Structs
### Item
Structure of an order within the node.


```solidity
struct Item {
    bytes32 id;
    bytes32 next;
    bytes32 prev;
}
```

### Queue
Structure of the queue itself.


```solidity
struct Queue {
    bytes32 first;
    bytes32 last;
    mapping(bytes32 => Item) items;
}
```

