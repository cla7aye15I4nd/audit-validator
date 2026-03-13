package pipeline

import (
	"github.com/holiman/uint256"
)

// OrderContext holds all data and state during order processing through the pipeline
type OrderContext struct {
	// Input parameters
	Order  interface{} // *orderbook.Order
	Locker interface{} // *orderbook.DefaultLocker
	Engine interface{} // *orderbook.SymbolEngine

	// Pipeline execution state
	StageIndex    int   // Current stage index
	Error         error // Error that occurred during processing

	// Output data
	Trades            []interface{} // []*orderbook.Trade
	Events            []interface{} // []orderbook.OrderbookEvent
	TriggeredOrderIDs []string      // Triggered stop order IDs
	TriggeredOrders   []interface{} // []*orderbook.TriggeredOrder to process after pipeline

	// Intermediate data for stages to share
	BaseToken     string       // Base token for the trading pair
	QuoteToken    string       // Quote token for the trading pair
	MarketLocked  *uint256.Int // Amount locked for market orders
	ExecutedCost  *uint256.Int // Total cost executed (for buy orders)
	ExecutedQty   *uint256.Int // Total quantity executed (for sell orders)
	LastTradePrice *uint256.Int // Last trade price for conditional checks

	// Stage-specific flags
	OrderAddedToQueue bool // Whether order was added to queue
	TradesProcessed   bool // Whether trades have been processed
	EventsGenerated   bool // Whether events have been generated

	// Additional context data
	Metadata map[string]interface{} // Generic metadata storage
}

// NewOrderContext creates a new OrderContext with the given parameters
func NewOrderContext(order, locker, engine interface{}) *OrderContext {
	return &OrderContext{
		Order:           order,
		Locker:          locker,
		Engine:          engine,
		Metadata:        make(map[string]interface{}),
		Trades:          make([]interface{}, 0),
		Events:          make([]interface{}, 0),
		TriggeredOrders: make([]interface{}, 0),
	}
}