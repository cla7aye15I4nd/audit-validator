package interfaces

import (
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
)

// ConditionalManager manages conditional orders (Stop, TPSL)
type ConditionalManager interface {
	// AddTPSLOrder adds a TPSL order and returns TP order if exists
	// The returned TP order should be immediately added to triggered queue
	AddTPSLOrder(tpsl *types.TPSLOrder) error
	
	// AddStopOrder adds a single stop order
	AddStopOrder(stop *types.StopOrder) error
	
	// CheckTriggers checks all conditional orders against current price
	// Returns: (triggered orders, order IDs to cancel)
	CheckTriggers(currentPrice *uint256.Int) ([]*types.Order, []types.OrderID)
	
	// OnOrderPartiallyFilled handles partial fill notification
	// Returns order IDs that should be cancelled (OCO logic)
	OnOrderPartiallyFilled(orderID types.OrderID) []types.OrderID

	// CancelOrder cancels a conditional order by ID
	CancelOrder(orderID types.OrderID) bool
	
	// CancelUserOrders cancels all conditional orders for a user
	CancelUserOrders(userID types.UserID) []types.OrderID
	
	// GetQueueSize returns the number of active conditional orders
	GetQueueSize() int
	
	// Clear removes all conditional orders
	Clear()
}