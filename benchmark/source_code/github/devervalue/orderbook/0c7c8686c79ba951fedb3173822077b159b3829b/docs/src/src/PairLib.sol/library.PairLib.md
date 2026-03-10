# PairLib
[Git Source](https://github.com/artechsoft/orderbook/blob/bbd55f017f77567506e5700d9133d68be9d96234/src/PairLib.sol)

This library provides functionality for creating, canceling, and matching orders in a decentralized exchange

*This library uses OpenZeppelin's SafeERC20 for secure token transfers*


## State Variables
### PRECISION
*Precision factor for price calculations*


```solidity
uint256 private constant PRECISION = 1e18;
```


### MAX_NUMBER_ORDERS_FILLED
*Maximum number of orders that can be filled in a single transaction*


```solidity
uint256 private constant MAX_NUMBER_ORDERS_FILLED = 1500;
```


### ORDER_CREATED
*Constant representing the status of a newly created order*


```solidity
uint256 private constant ORDER_CREATED = 1;
```


### ORDER_PARTIALLY_FILLED
*Constant representing the status of a partially filled order*


```solidity
uint256 private constant ORDER_PARTIALLY_FILLED = 2;
```


## Functions
### changePairFee

Changes the fee for a trading pair

*This function can only be called internally, typically by the contract owner*


```solidity
function changePairFee(Pair storage pair, uint256 newFee) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`newFee`|`uint256`|The new fee to be set (in basis points)|


### withdrawBalance

Allows a trader to withdraw their balance from a trading pair

*This function updates the trader's balance and transfers tokens to their address*


```solidity
function withdrawBalance(Pair storage pair, address traderAddress) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct containing trader balances|
|`traderAddress`|`address`|The address of the trader withdrawing their balance|


### addBuyOrder

Adds a new buy order to the order book

*This function checks if the pair is enabled before creating the order*


```solidity
function addBuyOrder(Pair storage pair, uint256 _price, uint256 _quantity, uint256 timestamp) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`_price`|`uint256`|The price at which the buy order is placed|
|`_quantity`|`uint256`|The quantity of base tokens to buy|
|`timestamp`|`uint256`|The timestamp of the order creation|


### addSellOrder

Adds a new sell order to the order book

*This function checks if the pair is enabled before creating the order*


```solidity
function addSellOrder(Pair storage pair, uint256 _price, uint256 _quantity, uint256 timestamp) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`_price`|`uint256`|The price at which the sell order is placed|
|`_quantity`|`uint256`|The quantity of base tokens to sell|
|`timestamp`|`uint256`|The timestamp of the order creation|


### cancelOrder

Cancels an existing order in the order book

*This function can only be called by the original order creator*


```solidity
function cancelOrder(Pair storage pair, bytes32 _orderId) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`_orderId`|`bytes32`|The unique identifier of the order to be canceled|


### removeFromTraderOrders

Removes an order from a trader's order registry

*This function uses an efficient O(1) removal technique*


```solidity
function removeFromTraderOrders(Pair storage pair, bytes32 _orderId, address traderAddress) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`_orderId`|`bytes32`|The unique identifier of the order to be removed|
|`traderAddress`|`address`|The address of the trader whose order is being removed|


### addOrder

Adds a new order to the order book

*This function handles the creation and insertion of a new order into the book*


```solidity
function addOrder(Pair storage pair, OrderBookLib.Order memory newOrder) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`newOrder`|`OrderBookLib.Order`|The new order to be added to the book|


### removeOrder

Removes an order from the order book and related data structures

*This function handles the complete removal of an order, including from the order book, trader's registry, and order details*


```solidity
function removeOrder(Pair storage pair, OrderBookLib.Order memory order) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`order`|`OrderBookLib.Order`|The order to be removed|


### fillOrder

Fills a matched order completely

*This function handles the token transfers, fee calculation, and order updates when a match is found*


```solidity
function fillOrder(Pair storage pair, OrderBookLib.Order storage matchedOrder, OrderBookLib.Order memory takerOrder)
    private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`matchedOrder`|`OrderBookLib.Order`|The storage reference to the existing order that is being filled|
|`takerOrder`|`OrderBookLib.Order`|The memory reference to the new order that is filling the matched order|


### partiallyFillOrder

Update the token balances of the maker based on the order type

Partially fills a matched order

*The fee is calculated in basis points (1/100 of a percent)*

*For buy orders, update quote token balance; for sell orders, update base token balance*

*This function handles the token transfers, fee calculation, and order updates when a partial match is found*


```solidity
function partiallyFillOrder(
    Pair storage pair,
    OrderBookLib.Order storage matchedOrder,
    OrderBookLib.Order memory takerOrder
) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`matchedOrder`|`OrderBookLib.Order`|The storage reference to the existing order that is being partially filled|
|`takerOrder`|`OrderBookLib.Order`|The memory reference to the new order that is partially filling the matched order|


### matchOrder

Update the token balances of the maker based on the order type

Matches a new order against existing orders in the order book

*The calculation depends on whether the taker order is a buy or sell order*

*The fee is calculated in basis points (1/100 of a percent)*

*For buy orders, update quote token balance; for sell orders, update base token balance*

*This updates the volume at the price point in the order book*

*This function attempts to fill the new order by matching it against existing orders*


```solidity
function matchOrder(Pair storage pair, uint256 orderCount, OrderBookLib.Order memory newOrder)
    private
    returns (uint256, uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`orderCount`|`uint256`|The current count of orders processed in this matching session|
|`newOrder`|`OrderBookLib.Order`|The new order to be matched against existing orders|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The remaining quantity of the new order after matching|
|`<none>`|`uint256`|uint256 The updated count of orders processed in this matching session|


### createOrder

Creates a new order in the order book

*We use the appropriate order book (sell for buy orders, buy for sell orders)*

*This function handles both the creation of new orders and matching against existing orders*


```solidity
function createOrder(Pair storage pair, bool isBuy, uint256 _price, uint256 _quantity, uint256 timestamp) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`isBuy`|`bool`|Boolean indicating whether this is a buy order (true) or sell order (false)|
|`_price`|`uint256`|The price at which the order is placed|
|`_quantity`|`uint256`|The quantity of tokens to be traded|
|`timestamp`|`uint256`|The timestamp of the order creation|


### getTraderBalances

Retrieves the balance of a trader for a specific trading pair

*This function returns the current balance of base and quote tokens for a given trader*


```solidity
function getTraderBalances(Pair storage pair, address _trader) internal view returns (TraderBalance memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct containing trader balances|
|`_trader`|`address`|The address of the trader whose balance is being queried|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`TraderBalance`|TraderBalance A struct containing the trader's base and quote token balances|


### getTraderOrders

Retrieves all order IDs for a specific trader

*This function returns an array of order IDs associated with the given trader's address*


```solidity
function getTraderOrders(Pair storage pair, address _trader) internal view returns (bytes32[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`_trader`|`address`|The address of the trader whose orders are being retrieved|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32[]`|bytes32[] memory An array of order IDs belonging to the trader|


### getOrderDetail

Retrieves the details of a specific order

*This function returns the full Order struct for a given order ID*

**Note:**
throws: PL__OrderIdDoesNotExist if the order ID does not exist


```solidity
function getOrderDetail(Pair storage pair, bytes32 orderId) internal view returns (OrderBookLib.Order storage);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`orderId`|`bytes32`|The unique identifier of the order|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`OrderBookLib.Order`|OrderBookLib.Order storage The order details|


### getLowestBuyPrice

Gets the lowest buy price in the order book

*This function returns the lowest price at which there is a buy order*


```solidity
function getLowestBuyPrice(Pair storage pair) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The lowest buy price, or 0 if there are no buy orders|


### getLowestSellPrice

Gets the lowest sell price in the order book

*This function returns the lowest price at which there is a sell order*


```solidity
function getLowestSellPrice(Pair storage pair) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The lowest sell price, or 0 if there are no sell orders|


### getHighestBuyPrice

Gets the highest buy price in the order book

*This function returns the highest price at which there is a buy order*


```solidity
function getHighestBuyPrice(Pair storage pair) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The highest buy price, or 0 if there are no buy orders|


### getNextBuyOrderId

Retrieves the ID of the next buy order at a specific price

*This function is used to traverse the order book for buy orders*


```solidity
function getNextBuyOrderId(Pair storage pair, uint256 price) internal view returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`price`|`uint256`|The price point to check for the next buy order|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|bytes32 The ID of the next buy order at the specified price, or 0 if none exists|


### getTop50BuyPrices

Retrieves the top 50 buy prices in the order book

*This function returns an array of the 50 highest buy prices*


```solidity
function getTop50BuyPrices(Pair storage pair) internal view returns (uint256[50] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|

**Returns**

|Name|Type| Description                                                                              |
|----|----|------------------------------------------------------------------------------------------|
|`<none>`|`uint256[50]`| uint256[50] memory An array containing the top 50 buy prices, sorted in descending order |


### getTop50SellPrices

Retrieves the top 50 sell prices in the order book

*This function returns an array of the 50 lowest sell prices*


```solidity
function getTop50SellPrices(Pair storage pair) internal view returns (uint256[50] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|

**Returns**

|Name|Type| Description                                                                              |
|----|----|------------------------------------------------------------------------------------------|
|`<none>`|`uint256[50]`| uint256[50] memory An array containing the top 50 sell prices, sorted in ascending order |


### getPrice

Retrieves the PricePoint data for a specific price in either the buy or sell order book

*This function returns detailed information about orders at a specific price point*


```solidity
function getPrice(Pair storage pair, uint256 price, bool isBuy)
    internal
    view
    returns (OrderBookLib.PricePoint storage);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`price`|`uint256`|The price point to query|
|`isBuy`|`bool`|A boolean indicating whether to query the buy (true) or sell (false) order book|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`OrderBookLib.PricePoint`|OrderBookLib.PricePoint storage The PricePoint data for the specified price|


### orderExists

Checks if an order with the given ID exists in the order book

*This function is used internally to verify the existence of an order*


```solidity
function orderExists(Pair storage pair, bytes32 _orderId) private view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pair`|`Pair`|The storage reference to the Pair struct|
|`_orderId`|`bytes32`|The ID of the order to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if the order exists, false otherwise|


## Events
### OrderCreated
Emitted when a new order is created


```solidity
event OrderCreated(bytes32 indexed id, address indexed baseToken, address indexed quoteToken, address trader);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`bytes32`|The unique identifier of the created order|
|`baseToken`|`address`|The address of the base token in the trading pair|
|`quoteToken`|`address`|The address of the quote token in the trading pair|
|`trader`|`address`|The address of the trader who created the order|

### OrderCanceled
Emitted when an existing order is canceled


```solidity
event OrderCanceled(bytes32 indexed id, address indexed baseToken, address indexed quoteToken, address trader);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`bytes32`|The unique identifier of the canceled order|
|`baseToken`|`address`|The address of the base token in the trading pair|
|`quoteToken`|`address`|The address of the quote token in the trading pair|
|`trader`|`address`|The address of the trader who canceled the order|

### OrderFilled
Emitted when an order is completely filled (executed)


```solidity
event OrderFilled(bytes32 indexed id, address indexed baseToken, address indexed quoteToken, address trader);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`bytes32`|The unique identifier of the filled order|
|`baseToken`|`address`|The address of the base token in the trading pair|
|`quoteToken`|`address`|The address of the quote token in the trading pair|
|`trader`|`address`|The address of the trader whose order was filled|

### OrderPartiallyFilled
Emitted when an order is partially filled (partially executed)


```solidity
event OrderPartiallyFilled(bytes32 indexed id, address indexed baseToken, address indexed quoteToken, address trader);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`bytes32`|The unique identifier of the partially filled order|
|`baseToken`|`address`|The address of the base token in the trading pair|
|`quoteToken`|`address`|The address of the quote token in the trading pair|
|`trader`|`address`|The address of the trader whose order was partially filled|

### PairFeeChanged
Emitted when the fee for a trading pair is changed


```solidity
event PairFeeChanged(address indexed baseToken, address indexed quoteToken, uint256 newFee);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`baseToken`|`address`|The address of the base token in the trading pair|
|`quoteToken`|`address`|The address of the quote token in the trading pair|
|`newFee`|`uint256`|The new fee value for the trading pair|

## Errors
### PL__OrderDoesNotBelongToCurrentTrader
Thrown when an order doesn't belong to the current trader


```solidity
error PL__OrderDoesNotBelongToCurrentTrader();
```

### PL__OrderIdDoesNotExist
Thrown when an order ID does not exist


```solidity
error PL__OrderIdDoesNotExist();
```

### PL__OrderIdAlreadyExists
Thrown when an order ID already exists


```solidity
error PL__OrderIdAlreadyExists();
```

### PL__InvalidPrice
Thrown when an invalid price is provided


```solidity
error PL__InvalidPrice(uint256 price);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The invalid price|

### PL__InvalidQuantity
Thrown when an invalid quantity is provided


```solidity
error PL__InvalidQuantity(uint256 quantity);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`quantity`|`uint256`|The invalid quantity|

### PL__PairDisabled
Thrown when attempting to interact with a disabled pair


```solidity
error PL__PairDisabled();
```

## Structs
### TraderOrderRegistry
This structure maintains an efficient record of all orders belonging to a specific trader

*Structure to keep track of a trader's orders*


```solidity
struct TraderOrderRegistry {
    bytes32[] orderIds;
    mapping(bytes32 => uint256) index;
}
```

### TraderBalance
*Struct representing a trader's balance in a trading pair*


```solidity
struct TraderBalance {
    uint256 baseTokenBalance;
    uint256 quoteTokenBalance;
}
```

### Pair
This structure encapsulates all data and functionality related to a specific trading pair

*Main structure representing a trading pair*


```solidity
struct Pair {
    uint256 lastTradePrice;
    uint256 fee;
    address baseToken;
    address quoteToken;
    address feeAddress;
    bool enabled;
    OrderBookLib.Book buyOrders;
    OrderBookLib.Book sellOrders;
    mapping(address => TraderOrderRegistry) traderOrderRegistry;
    mapping(bytes32 => OrderBookLib.Order) orders;
    mapping(address => TraderBalance) traderBalances;
}
```

