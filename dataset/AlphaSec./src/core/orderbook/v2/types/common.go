package types

import (
	"fmt"
	"time"

	"github.com/holiman/uint256"
)

// Price represents a price value
type Price = uint256.Int

// Quantity represents a quantity value
type Quantity = uint256.Int

// NewPrice creates a new price from uint64
func NewPrice(value uint64) *Price {
	return uint256.NewInt(value)
}

// NewQuantity creates a new quantity from uint64
func NewQuantity(value uint64) *Quantity {
	return uint256.NewInt(value)
}

// TimeNow returns current timestamp in nanoseconds
func TimeNow() int64 {
	return time.Now().UnixNano()
}

// ParseSymbol parses a symbol string into base and quote tokens
func ParseSymbol(symbol Symbol) (baseToken, quoteToken string) {
	// Simple implementation - should be improved
	// Assumes format like "BTC/USDT" or "ETH/USDC"
	for i, c := range symbol {
		if c == '/' {
			return string(symbol[:i]), string(symbol[i+1:])
		}
	}
	return string(symbol), ""
}

// CreateSymbol creates a symbol from base and quote tokens
func CreateSymbol(baseToken, quoteToken string) Symbol {
	return Symbol(baseToken + "/" + quoteToken)
}

// OrderRequest represents a request to place an order
type OrderRequest struct {
	UserID    UserID
	Symbol    Symbol
	Side      OrderSide
	OrderType OrderType
	Price     *Price    // Optional for market orders
	Quantity  *Quantity
	OrderMode OrderMode
	
	// Optional fields for conditional orders
	StopPrice    *Price
	TriggerAbove bool
	TPSL         *TPSLRequest // Optional TPSL attachment
}

// TPSLRequest represents a request to attach TPSL to an order
type TPSLRequest struct {
	// Take Profit
	TPPrice     *Price
	TPQuantity  *Quantity // Optional, defaults to full quantity
	
	// Stop Loss
	SLPrice     *Price
	SLQuantity  *Quantity // Optional, defaults to full quantity
}

// CancelRequest represents a request to cancel an order
type CancelRequest struct {
	OrderID OrderID
	UserID  UserID
}

// GenerateTradeID generates a unique trade ID
func GenerateTradeID() TradeID {
	// Simple implementation using timestamp
	// In production, use a more robust ID generation
	return TradeID(fmt.Sprintf("%d", time.Now().UnixNano()))
}

// CancelAllRequest represents a request to cancel all orders for a user
type CancelAllRequest struct {
	UserID UserID
	Symbol Symbol // Optional, if empty cancels all symbols
}

// ModifyRequest represents a request to modify an order
type ModifyRequest struct {
	OrderID     OrderID
	UserID      UserID
	NewPrice    *Price    // Optional
	NewQuantity *Quantity // Optional
}

// Response represents a generic response
type Response struct {
	Success bool
	Error   error
	Data    interface{}
}

// OrderResponse represents response for order placement
type OrderResponse struct {
	Order  *Order
	Trades []*Trade
	Error  error
}

// CancelResponse represents response for order cancellation
type CancelResponse struct {
	CancelledOrderIDs []OrderID
	Error             error
}

// ModifyResponse represents response for order modification
type ModifyResponse struct {
	ModifiedOrder *Order
	Trades        []*Trade
	Error         error
}