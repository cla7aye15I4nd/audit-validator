package orderbook

import "github.com/holiman/uint256"

// Order book configuration
const (
	// OrderQueueSize defines the maximum number of requests that can be queued
	OrderQueueSize = 1000
	
	// OrderMinPrice is the minimum allowed price for orders
	OrderMinPrice = 0
	
	// ScalingExp is the decimal scaling exponent (18 decimals)
	ScalingExp = 18
	
	// NativeToken represents the native token identifier
	NativeToken = "1"
)

// Binary operation constants
const (
	// MaxUint256BitShift is used to calculate MaxUint256 (1 << 256)
	MaxUint256BitShift = 256
)

// MaxUint256 represents the maximum value for uint256 (2^256 - 1)
var MaxUint256 = new(uint256.Int).Sub(
	new(uint256.Int).Lsh(uint256.NewInt(1), MaxUint256BitShift),
	uint256.NewInt(1),
)

// Goroutine management comments (to be addressed in future refactoring)
// TODO-Orderbook: terminate goroutines properly
// TODO-Orderbook: use shutdown to terminate symbol engine gracefully
// TODO-Orderbook: error handling for GetMarketFees
// TODO-Orderbook: Separate asset locking logics from processOrderWithoutStopOrder
// TODO-Orderbook: remove locking logic if not needed
// TODO-Orderbook: remove unlock logic if not needed