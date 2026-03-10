package interfaces

import (
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
)

// OrderMatcher defines the interface for order matching algorithms
type OrderMatcher interface {
	// MatchOrder matches a new order against the orderbook
	// Returns trades executed and any remaining order quantity
	MatchOrder(order *types.Order, orderBook OrderBook) (*MatchResult, error)
	
	// GetAlgorithm returns the name of the matching algorithm
	GetAlgorithm() string
}

// MatchResult represents the result of order matching
type MatchResult struct {
	// Trades executed during matching
	Trades []*types.Trade

	// Remaining order after matching (nil if fully filled)
	RemainingOrder *types.Order

	// Total quantity filled
	FilledQuantity *types.Quantity

	// Filled orders with TPSL that need TPSL creation
	// These are saved before being removed from orderbook
	FilledOrdersWithTPSL []*types.Order

	// Rejected order with reason (nil if not rejected)
	FailedOrders []types.FailedOrder
}

// OrderQueue defines the interface for order priority queues
type OrderQueue interface {
	// Push adds an order to the queue
	Push(order *types.Order)

	// Pop removes and returns the top order
	Pop() *types.Order

	// Peek returns the top order without removing it
	Peek() *types.Order

	// Update updates an order in the queue (for partial fills)
	Update(order *types.Order)

	// Remove removes a specific order by ID
	Remove(orderID types.OrderID) bool

	// Len returns the number of orders in the queue
	Len() int

	// IsEmpty returns true if the queue is empty
	IsEmpty() bool

	// Clear removes all orders from the queue
	Clear()

	// GetOrders returns all orders in the queue
	GetOrders() []*types.Order
}

// OrderBook defines the interface for orderbook management
type OrderBook interface {
	// AddOrder adds an order to the orderbook
	AddOrder(order *types.Order) error
	
	// RemoveOrder removes an order from the orderbook
	RemoveOrder(orderID types.OrderID) error
	
	// UpdateOrder updates an order in the orderbook (for partial fills)
	UpdateOrder(order *types.Order) error
	
	// GetOrder returns an order by ID
	GetOrder(orderID types.OrderID) (*types.Order, bool)
	
	// GetUserOrders returns all orders for a user
	GetUserOrders(userID types.UserID) []*types.Order
	
	// GetBuyOrders returns all buy orders
	GetBuyOrders() []*types.Order
	
	// GetSellOrders returns all sell orders
	GetSellOrders() []*types.Order
	
	// GetBestBid returns the best bid order
	GetBestBid() *types.Order
	
	// GetBestAsk returns the best ask order
	GetBestAsk() *types.Order

	// GetCurrentPrice returns the last traded price
	GetCurrentPrice() *types.Price
	
	// GetDepth returns the orderbook depth up to a limit
	GetDepth(limit int) (bids, asks []PriceLevel)
	
	// Clear removes all orders
	Clear()
}

// PriceLevel represents an aggregated price level in the orderbook
type PriceLevel struct {
	Price    *types.Price
	Quantity *types.Quantity
	Orders   int // Number of orders at this level
}

// ConditionalOrderManager manages stop and TPSL orders
type ConditionalOrderManager interface {
	// AddStopOrder adds a stop order
	AddStopOrder(order *types.StopOrder) error
	
	// AddTPSLOrder adds a TPSL order
	AddTPSLOrder(order *types.TPSLOrder) error
	
	// CheckTriggers checks all conditional orders against current price

	// CheckTriggersWithOrderBook checks triggers with orderbook access for TPSL monitoring
	CheckTriggersWithOrderBook(currentPrice *types.Price, orderBook OrderBook) []*types.Order
	
	// CancelOrder cancels a conditional order
	CancelOrder(orderID types.OrderID) bool
	
	// CancelUserOrders cancels all conditional orders for a user
	CancelUserOrders(userID types.UserID) []types.OrderID
	
	// GetStopOrder returns a stop order by ID
	GetStopOrder(orderID types.OrderID) (*types.StopOrder, bool)
	
	// GetTPSLOrder returns a TPSL order by ID
	GetTPSLOrder(orderID types.OrderID) (*types.TPSLOrder, bool)
	
	// GetUserStopOrders returns all stop orders for a user
	GetUserStopOrders(userID types.UserID) []*types.StopOrder
	
	// GetUserTPSLOrders returns all TPSL orders for a user
	GetUserTPSLOrders(userID types.UserID) []*types.TPSLOrder
}


// TradingStatistics represents trading statistics
type TradingStatistics struct {
	Symbol       types.Symbol
	LastPrice    *types.Price
	Volume24h    *types.Quantity
	High24h      *types.Price
	Low24h       *types.Price
	OpenPrice    *types.Price
	TradeCount   uint64
	OpenInterest *types.Quantity // For futures
}