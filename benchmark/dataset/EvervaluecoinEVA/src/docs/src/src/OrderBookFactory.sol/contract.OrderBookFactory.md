# OrderBookFactory
[Git Source](https://github.com/artechsoft/orderbook/blob/bbd55f017f77567506e5700d9133d68be9d96234/src/OrderBookFactory.sol)

**Inherits:**
ReentrancyGuard, Pausable, Ownable2Step

**Author:**
Diego Leal / Angel García / Artech Software

This contract manages the creation and administration of order books for trading pairs

*This contract inherits from ReentrancyGuard, Pausable, and Ownable for added security and control*


## State Variables
### MAX_FEE
*Utilizes PairLib for managing trading pairs*

*Utilizes OrderBookLib for managing individual orders*

*Utilizes OrderBookLib for managing price points*

*Maximum fee in basis points (2%)
This constant limits the maximum fee that can be set for a trading pair*


```solidity
uint256 private constant MAX_FEE = 200;
```


### pairIds
*Array to store all pair IDs
This allows for easy iteration over all trading pairs*


```solidity
bytes32[] public pairIds;
```


### pairs
*Mapping from pair ID to Pair struct
Stores all information related to a specific trading pair*


```solidity
mapping(bytes32 => PairLib.Pair) pairs;
```


## Functions
### onlyEnabledPair

Modifier to restrict operations to enabled pairs only

*This modifier checks if the specified pair is enabled before executing the function*


```solidity
modifier onlyEnabledPair(bytes32 _pairId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the pair to check|


### constructor

Contract constructor

*Initializes the contract and sets the deployer as the owner*


```solidity
constructor() Ownable(msg.sender);
```

### addPair

Adds a new order book to the mapping

*Creates a new trading pair and its associated order book with specified parameters*

**Note:**
security: This function is only callable by the contract owner and when the contract is not paused


```solidity
function addPair(address quoteToken, address baseToken, uint256 initialFee, address feeAddress)
    external
    onlyOwner
    whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`quoteToken`|`address`|The address of the quote token in the trading pair|
|`baseToken`|`address`|The address of the base token in the trading pair|
|`initialFee`|`uint256`|The initial fee percentage (in basis points) for transactions in this order book|
|`feeAddress`|`address`|The address that will receive the collected fees|


### getPairIds

Retrieves all pair IDs

*This function allows external contracts or users to get a list of all trading pair identifiers*


```solidity
function getPairIds() external view returns (bytes32[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32[]`|An array of bytes32 containing all pair IDs|


### getPairById

Retrieves detailed information about a specific trading pair

*This function provides comprehensive data about a pair, including its current status and fee information*


```solidity
function getPairById(bytes32 _pairId)
    external
    view
    returns (
        address baseToken,
        address quoteToken,
        bool status,
        uint256 lastTradePrice,
        uint256 fee,
        address feeAddress
    );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the pair to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`baseToken`|`address`|The address of the base token in the pair|
|`quoteToken`|`address`|The address of the quote token in the pair|
|`status`|`bool`|Whether the pair is currently enabled or disabled|
|`lastTradePrice`|`uint256`|The price of the last executed trade for this pair|
|`fee`|`uint256`|The current fee percentage for trades in this pair|
|`feeAddress`|`address`|The address currently set to receive fees from this pair's trades|


### setPairStatus

Changes the enabled status of a trading pair

*This function allows the owner to enable or disable trading for a specific pair*


```solidity
function setPairStatus(bytes32 _pairId, bool _enabled) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the pair to modify|
|`_enabled`|`bool`|The new status to set (true to enable, false to disable)|


### setPairFee

Updates the fee for a specific trading pair

*This function allows the owner to change the fee percentage for a pair*


```solidity
function setPairFee(bytes32 _pairId, uint256 newFee) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the pair to modify|
|`newFee`|`uint256`|The new fee percentage to set (in basis points)|


### setPairFeeAddress

Sets a new fee recipient address for a specific order book

*This function allows the owner to change the address that receives fees for a particular trading pair*


```solidity
function setPairFeeAddress(bytes32 _pairId, address newFeeAddress) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the pair to modify|
|`newFeeAddress`|`address`|The new address that will receive the fees|


### addNewOrder

Adds a new order to the order book

*This function allows users to place new buy or sell orders*


```solidity
function addNewOrder(bytes32 _pairId, uint256 _quantity, uint256 _price, bool _isBuy, uint256 _timestamp)
    external
    onlyEnabledPair(_pairId)
    nonReentrant
    whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the trading pair|
|`_quantity`|`uint256`|The amount of tokens to buy or sell|
|`_price`|`uint256`|The price at which to place the order|
|`_isBuy`|`bool`|A boolean indicating whether this is a buy (true) or sell (false) order|
|`_timestamp`|`uint256`|The timestamp of when the order was created|


### cancelOrder

Cancels an existing order

*This function allows users to cancel their own orders*


```solidity
function cancelOrder(bytes32 _pairId, bytes32 _orderId) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the trading pair|
|`_orderId`|`bytes32`|The unique identifier of the order to be cancelled|


### pause

Pauses all operations in the contract

*Only the owner can call this function. It uses OpenZeppelin's Pausable functionality.*


```solidity
function pause() external onlyOwner;
```

### unpause

Resumes all operations in the contract

*Only the owner can call this function. It uses OpenZeppelin's Pausable functionality.*


```solidity
function unpause() external onlyOwner;
```

### getPairFee

Retrieves the fee percentage for a specific trading pair

*This function returns the current fee in basis points*


```solidity
function getPairFee(bytes32 _pairId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the trading pair|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The fee percentage in basis points (e.g., 100 means 1%)|


### getTraderOrdersForPair

Retrieves all order IDs for a specific trader in a given pair

*This function allows querying all orders placed by a trader in a specific order book*


```solidity
function getTraderOrdersForPair(bytes32 _pairId, address _trader) external view returns (bytes32[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the trading pair|
|`_trader`|`address`|The address of the trader whose orders are being queried|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32[]`|An array of bytes32 representing the order IDs|


### getOrderDetailForPair

Retrieves detailed information about a specific order

*This function returns the full Order struct for a given order ID*


```solidity
function getOrderDetailForPair(bytes32 _pairId, bytes32 _orderId) external view returns (OrderBookLib.Order memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the trading pair|
|`_orderId`|`bytes32`|The unique identifier of the order|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`OrderBookLib.Order`|An OrderBookLib.Order struct containing all details of the order|


### getTop50BuyPricesForPair

Retrieves the top 50 buy prices for a specific pair

*This function returns the highest 50 prices in the buy order book*


```solidity
function getTop50BuyPricesForPair(bytes32 pairId) external view returns (uint256[50] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pairId`|`bytes32`|The unique identifier of the trading pair|

**Returns**

|Name|Type| Description                                                   |
|----|----|---------------------------------------------------------------|
|`<none>`|`uint256[50]`| An array of 50 uint256 values representing the top buy prices |


### getTop50SellPricesForPair

Retrieves the top 50 sell prices for a specific pair

*This function returns the lowest 50 prices in the sell order book*


```solidity
function getTop50SellPricesForPair(bytes32 pairId) external view returns (uint256[50] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pairId`|`bytes32`|The unique identifier of the trading pair|

**Returns**

|Name|Type| Description                                                    |
|----|----|----------------------------------------------------------------|
|`<none>`|`uint256[50]`| An array of 50 uint256 values representing the top sell prices |


### getPricePointDataForPair

Retrieves data for a specific price point in the order book

*This function returns the number of orders and total value at a given price*


```solidity
function getPricePointDataForPair(bytes32 _pairId, uint256 price, bool isBuy)
    external
    view
    returns (uint256 orderCount, uint256 orderValue);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the trading pair|
|`price`|`uint256`|The price point to query|
|`isBuy`|`bool`|Whether to query the buy (true) or sell (false) side of the order book|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orderCount`|`uint256`|The number of orders at the specified price|
|`orderValue`|`uint256`|The total value of all orders at the specified price|


### checkBalanceTrader

Retrieves the balance of a trader for a specific trading pair

*This function allows querying the current balance of a trader in both base and quote tokens*

**Note:**
security: This function is view-only and does not modify state


```solidity
function checkBalanceTrader(bytes32 _pairId, address _trader) external view returns (PairLib.TraderBalance memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the trading pair|
|`_trader`|`address`|The address of the trader whose balance is being queried|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`PairLib.TraderBalance`|PairLib.TraderBalance A struct containing the trader's balance information|


### withdrawBalanceTrader

Allows a trader to withdraw their balance from a specific trading pair

*This function enables traders to withdraw their available balance (both base and quote tokens)*

**Notes:**
- security: This function is external and can be called by any address

- security: Implements a nonReentrant guard to prevent reentrancy attacks


```solidity
function withdrawBalanceTrader(bytes32 _pairId) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the trading pair from which to withdraw|


### pairExists

Checks if a trading pair exists

*A pair is considered to exist if its baseToken is not the zero address*


```solidity
function pairExists(bytes32 _pairId) private view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pairId`|`bytes32`|The unique identifier of the trading pair to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if the pair exists, false otherwise|


## Events
### OrderBookCreated
Emitted when a new order book is created


```solidity
event OrderBookCreated(bytes32 indexed id, address indexed baseToken, address indexed quoteToken, address owner);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`bytes32`|The unique identifier of the new order book|
|`baseToken`|`address`|The address of the base token in the trading pair|
|`quoteToken`|`address`|The address of the quote token in the trading pair|
|`owner`|`address`|The address of the owner who created the order book|

### PairStatusChanged
Emitted when the status of an order book is changed


```solidity
event PairStatusChanged(bytes32 indexed id, bool enabled);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`bytes32`|The unique identifier of the affected order book|
|`enabled`|`bool`|The new status of the order book (true if enabled, false if disabled)|

### PairFeeChanged
Emitted when the fee for an order book is updated


```solidity
event PairFeeChanged(bytes32 indexed id, uint256 newFee);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`bytes32`|The unique identifier of the affected order book|
|`newFee`|`uint256`|The new fee value set for the order book|

### PairFeeAddressChanged
Emitted when the fee recipient address for an order book is changed


```solidity
event PairFeeAddressChanged(bytes32 indexed id, address newFeeAddress);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`bytes32`|The unique identifier of the affected order book|
|`newFeeAddress`|`address`|The new address that will receive the fees for this order book|

### ContractPauseStatusChanged
Emitted when the pause status of the entire contract is changed


```solidity
event ContractPauseStatusChanged(bool isPaused);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`isPaused`|`bool`|The new pause status of the contract (true if paused, false if unpaused)|

## Errors
### OBF__InvalidTokenAddress
Thrown when an invalid token address (zero address) is provided


```solidity
error OBF__InvalidTokenAddress();
```

### OBF__InvalidFeeAddress
Thrown when an invalid fee address (zero address) is provided


```solidity
error OBF__InvalidFeeAddress();
```

### OBF__TokensMustBeDifferent
Thrown when attempting to create a pair with the same token for both base and quote


```solidity
error OBF__TokensMustBeDifferent();
```

### OBF__PairDoesNotExist
Thrown when trying to perform an operation on a non-existent pair


```solidity
error OBF__PairDoesNotExist();
```

### OBF__InvalidQuantityValueZero
Thrown when attempting to place an order with zero quantity


```solidity
error OBF__InvalidQuantityValueZero();
```

### OBF__PairNotEnabled
Thrown when trying to interact with a pair that is not enabled


```solidity
error OBF__PairNotEnabled();
```

### OBF__PairAlreadyExists
Thrown when attempting to create a pair that already exists


```solidity
error OBF__PairAlreadyExists();
```

### OBF__FeeExceedsMaximum
Thrown when the proposed fee exceeds the maximum allowed fee


```solidity
error OBF__FeeExceedsMaximum(uint256 fee, uint256 maxFee);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fee`|`uint256`|The proposed fee that caused the error|
|`maxFee`|`uint256`|The maximum allowed fee|

