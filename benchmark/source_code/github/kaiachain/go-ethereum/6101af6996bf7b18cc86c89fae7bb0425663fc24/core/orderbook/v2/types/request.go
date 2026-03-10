package types

// RequestType represents the type of orderbook request
type RequestType uint8

const (
	PlaceOrder RequestType = iota
	CancelOrder
	CancelAllOrders
	ModifyOrder
	PlaceStopOrder
)

// Request represents an orderbook operation request
type Request struct {
	Type      RequestType
	RequestID string // Unique request identifier
	
	// State and fee management (injected per request)
	StateDB      StateDB       // Current blockchain state for this request
	FeeRetriever FeeRetriever  // Fee configuration for this request
	
	// Order operations
	Order      *Order      // For PlaceOrder, ModifyOrder
	StopOrder  *StopOrder  // For PlaceStopOrder

	// Cancel operations
	OrderID    string // For CancelOrder, ModifyOrder (old order)
	OldOrderID string // For ModifyOrder
	
	// Cancel operations specific
	UserID string // For CancelAllOrders
	Symbol Symbol // For symbol-specific operations
}

// OrderbookResponse extends Response with orderbook-specific fields
type OrderbookResponse struct {
	Success bool
	Error   string
	Message string
	
	// Order operation results
	Order       *Order
	OrderStatus OrderStatus
	OrderID     OrderID
	
	// Trade results
	Trades []*Trade
	
	// Cancel results
	CancelledOrders []OrderID
	
	// Orderbook snapshot (for legacy dispatcher and client communication)
	Orderbook    *OrderbookData
}

// OrderbookData represents orderbook snapshot
type OrderbookData struct {
	Symbol    Symbol
	Timestamp int64
	Bids      []PriceLevel
	Asks      []PriceLevel
}

// PriceLevel represents a price level in the orderbook
type PriceLevel struct {
	Price    *Price
	Quantity *Quantity
	Orders   int // Number of orders at this level
}