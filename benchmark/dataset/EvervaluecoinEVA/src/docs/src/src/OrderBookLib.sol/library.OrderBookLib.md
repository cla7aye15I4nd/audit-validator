# OrderBookLib
[Git Source](https://github.com/artechsoft/orderbook/blob/bbd55f017f77567506e5700d9133d68be9d96234/src/OrderBookLib.sol)

*This library uses a Red-Black Tree for efficient price level management and a Queue for order management within each price level*


## Functions
### insert

Inserts a new order into the order book


```solidity
function insert(Book storage b, bytes32 _orderId, uint256 _price, uint256 _quantity) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`b`|`Book`|The order book to insert into|
|`_orderId`|`bytes32`|The unique identifier of the order|
|`_price`|`uint256`|The price of the order|
|`_quantity`|`uint256`|The quantity of the order|


### remove

Removes an order from the order book


```solidity
function remove(Book storage b, Order memory _order) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`b`|`Book`|The order book to remove from|
|`_order`|`Order`|The order to be removed|


### update

Updates the quantity of an order at a specific price point


```solidity
function update(Book storage b, uint256 _pricePoint, uint256 _quantity) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`b`|`Book`|The order book to update|
|`_pricePoint`|`uint256`|The price point of the order to update|
|`_quantity`|`uint256`|The quantity to subtract from the order value|


### getLowestPrice

Gets the lowest price in the order book


```solidity
function getLowestPrice(Book storage b) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`b`|`Book`|The order book to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The lowest price in the order book|


### getHighestPrice

Gets the highest price in the order book


```solidity
function getHighestPrice(Book storage b) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`b`|`Book`|The order book to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The highest price in the order book|


### get3Prices

Gets the three highest or lowest prices in the order book


```solidity
function get3Prices(Book storage b, bool highest) internal view returns (uint256[50] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`b`|`Book`|The order book to query|
|`highest`|`bool`|If true, get the highest prices; if false, get the lowest prices|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256[50]`|An array of the three prices|


### getNextOrderIdAtPrice

Gets the ID of the next order at a specific price


```solidity
function getNextOrderIdAtPrice(Book storage b, uint256 _price) internal view returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`b`|`Book`|The order book to query|
|`_price`|`uint256`|The price point to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The ID of the next order at the specified price|


### getPricePointData

Gets the data for a specific price point


```solidity
function getPricePointData(Book storage b, uint256 _pricePoint) internal view returns (PricePoint storage);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`b`|`Book`|The order book to query|
|`_pricePoint`|`uint256`|The price point to get data for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`PricePoint`|The PricePoint struct for the specified price|


## Structs
### PricePoint
*Struct to represent a price point in the order book*


```solidity
struct PricePoint {
    uint256 orderCount;
    uint256 orderValue;
    QueueLib.Queue q;
}
```

### Order
*Struct to represent an individual order*


```solidity
struct Order {
    bytes32 id;
    uint256 price;
    uint256 quantity;
    uint256 availableQuantity;
    uint256 createdAt;
    uint256 status;
    address traderAddress;
    bool isBuy;
}
```

### Book
*Struct to represent the entire order book*


```solidity
struct Book {
    RedBlackTreeLib.Tree tree;
    mapping(uint256 => PricePoint) prices;
}
```

