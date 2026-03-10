package types

import (
	"github.com/holiman/uint256"
)

// ConditionalOrderType represents the type of conditional order
type ConditionalOrderType uint8

const (
	ConditionalTypeStop ConditionalOrderType = iota
	ConditionalTypeTPSL
)

// TriggerType represents the type of conditional trigger
type TriggerType uint8

const (
	STOP_LOSS TriggerType = iota
	TAKE_PROFIT
)

// ConditionalOrder is the interface for all conditional order types
type ConditionalOrder interface {
	// Basic identifiers
	GetOrderID() OrderID
	GetUserID() UserID
	GetOrderType() ConditionalOrderType

	// Status management
	GetStatus() OrderStatus
	Cancel()

	// Trigger check
	ShouldTrigger(currentPrice *uint256.Int) bool
	
	// Trigger execution - returns order to execute and order ID to cancel (OCO)
	Trigger() (*Order, OrderID)
}

// StopOrder represents a stop-loss or take-profit order
type StopOrder struct {
	// The underlying order to execute when triggered
	Order *Order

	// Trigger conditions
	StopPrice    *uint256.Int // Trigger price
	TriggerAbove bool         // true: trigger when price >= StopPrice, false: when price <= StopPrice

	// Status tracking (TRIGGER_WAIT -> TRIGGERED/CANCELLED)
	Status    OrderStatus
	CreatedAt int64
}

// NewStopOrder creates a new stop order
func NewStopOrder(order *Order, stopPrice *uint256.Int) *StopOrder {
	// Ensure inner order has same status
	if order != nil {
		order.Status = TRIGGER_WAIT
	}
	return &StopOrder{
		Order:        order,
		StopPrice:    stopPrice,
		Status:       TRIGGER_WAIT,
		CreatedAt:    TimeNow(),
	}
}

// SetTriggerAbove sets when the order should be triggered
func (s *StopOrder) SetTriggerAbove(currentPrice *uint256.Int) {
	if currentPrice == nil {
		s.TriggerAbove = true
		return
	}
	s.TriggerAbove = currentPrice.Cmp(s.StopPrice) < 0
}

// ShouldTrigger checks if the stop order should be triggered based on current price
func (s *StopOrder) ShouldTrigger(currentPrice *uint256.Int) bool {
	if s.Status != TRIGGER_WAIT {
		return false
	}
	if currentPrice == nil || s.StopPrice == nil {
		return false
	}

	if s.TriggerAbove {
		return currentPrice.Cmp(s.StopPrice) >= 0
	}
	return currentPrice.Cmp(s.StopPrice) <= 0
}

// Trigger marks the order as triggered and returns order to execute and order to cancel
func (s *StopOrder) Trigger() (*Order, OrderID) {
	if s.Status != TRIGGER_WAIT {
		return nil, ""
	}
	s.Status = TRIGGERED
	if s.Order != nil {
		s.Order.Status = TRIGGERED // Keep same status as StopOrder
	}
	return s.Order, "" // No order to cancel for stop orders
}

// GetOrderID returns the order ID
func (s *StopOrder) GetOrderID() OrderID {
	if s.Order != nil {
		return s.Order.OrderID
	}
	return ""
}

// GetUserID returns the user ID
func (s *StopOrder) GetUserID() UserID {
	if s.Order != nil {
		return s.Order.UserID
	}
	return ""
}

// GetOrderType returns the conditional order type
func (s *StopOrder) GetOrderType() ConditionalOrderType {
	return ConditionalTypeStop
}

// GetStatus returns the order status
func (s *StopOrder) GetStatus() OrderStatus {
	return s.Status
}

// Cancel cancels the stop order
func (s *StopOrder) Cancel() {
	s.Status = CANCELLED
	if s.Order != nil {
		s.Order.Status = CANCELLED // Keep same status as StopOrder
	}
}

// Copy creates a deep copy of the stop order
func (s *StopOrder) Copy() *StopOrder {
	if s == nil {
		return nil
	}

	return &StopOrder{
		Order:        s.Order.Copy(),
		StopPrice:    s.StopPrice.Clone(),
		TriggerAbove: s.TriggerAbove,
		Status:       s.Status,
		CreatedAt:    s.CreatedAt,
	}
}

// TPSLOrder represents a combined Take-Profit and Stop-Loss order with OCO logic
type TPSLOrder struct {
	// Original order that created this TPSL
	OriginalOrderID OrderID
	UserID          UserID

	// Take Profit - regular limit order in orderbook
	TPOrderID OrderID // ID of TP order in orderbook

	// Stop Loss - conditional order waiting for trigger
	SLOrder        *Order       // Order to execute when SL triggers
	SLTriggerPrice *uint256.Int // Price that triggers SL
	SLTriggerAbove bool         // true: trigger when price >= SLPrice, false: when price <= SLPrice

	// Status (TRIGGER_WAIT -> TRIGGERED/CANCELLED)
	Status    OrderStatus
	CreatedAt int64
}

// NewTPSLOrder creates a new TPSL order
func NewTPSLOrder(originalOrderID OrderID, userID UserID, tpOrderID OrderID, slOrder *Order, slPrice *uint256.Int, slTriggerAbove bool) *TPSLOrder {
	// Ensure SL order has proper status
	if slOrder != nil {
		slOrder.Status = TRIGGER_WAIT
	}

	return &TPSLOrder{
		OriginalOrderID: originalOrderID,
		UserID:          userID,
		TPOrderID:       tpOrderID,
		SLOrder:         slOrder,
		SLTriggerPrice:  slPrice,
		SLTriggerAbove:  slTriggerAbove,
		Status:          TRIGGER_WAIT, // TP active in orderbook, SL waiting
		CreatedAt:       TimeNow(),
	}
}

// ShouldTriggerSL checks if SL should be triggered based on current price
func (t *TPSLOrder) ShouldTriggerSL(currentPrice *uint256.Int) bool {
	if t.Status != TRIGGER_WAIT {
		return false
	}
	if currentPrice == nil || t.SLTriggerPrice == nil {
		return false
	}

	if t.SLTriggerAbove {
		return currentPrice.Cmp(t.SLTriggerPrice) >= 0
	}
	return currentPrice.Cmp(t.SLTriggerPrice) <= 0
}

// OnTPFilled handles TP order being filled
func (t *TPSLOrder) OnTPFilled() {
	if t.Status != TRIGGER_WAIT {
		return
	}

	t.Status = TRIGGERED
	// SL no longer needed (OCO completed)
	if t.SLOrder != nil {
		t.SLOrder.Status = CANCELLED
	}
}

// Trigger triggers the SL order and returns it along with TP order to cancel (OCO)
func (t *TPSLOrder) Trigger() (*Order, OrderID) {
	if t.SLOrder == nil || t.Status != TRIGGER_WAIT {
		return nil, ""
	}

	t.Status = TRIGGERED
	t.SLOrder.Status = TRIGGERED

	// Return SL order to execute and TP order to cancel (OCO)
	return t.SLOrder, t.TPOrderID
}

// TriggerSL is a helper method that triggers the stop-loss order
func (t *TPSLOrder) TriggerSL() *Order {
	order, _ := t.Trigger()
	return order
}

// GetTPOrderID returns the TP order ID for tracking
func (t *TPSLOrder) GetTPOrderID() OrderID {
	return t.TPOrderID
}

// OnTPPartialFill handles partial fill of TP order (OCO logic)
func (t *TPSLOrder) OnTPPartialFill() bool {
	if t.Status != TRIGGER_WAIT {
		return false
	}

	t.Status = TRIGGERED
	// Cancel SL on any TP fill (OCO)
	if t.SLOrder != nil {
		t.SLOrder.Status = CANCELLED
	}
	return true
}

// GetOrderID returns the original order ID
func (t *TPSLOrder) GetOrderID() OrderID {
	return t.OriginalOrderID
}

// GetUserID returns the user ID
func (t *TPSLOrder) GetUserID() UserID {
	return t.UserID
}

// GetOrderType returns the conditional order type
func (t *TPSLOrder) GetOrderType() ConditionalOrderType {
	return ConditionalTypeTPSL
}

// GetStatus returns the order status
func (t *TPSLOrder) GetStatus() OrderStatus {
	return t.Status
}

// ShouldTrigger checks if TPSL should trigger (only SL needs checking since TP is in orderbook)
func (t *TPSLOrder) ShouldTrigger(currentPrice *uint256.Int) bool {
	return t.ShouldTriggerSL(currentPrice)
}

// Cancel cancels the TPSL order
func (t *TPSLOrder) Cancel() {
	t.Status = CANCELLED
	// TP order in orderbook needs separate cancellation
	// SL order is cancelled here
	if t.SLOrder != nil {
		t.SLOrder.Status = CANCELLED
	}
}

// Copy creates a deep copy of the TPSL order
func (t *TPSLOrder) Copy() *TPSLOrder {
	if t == nil {
		return nil
	}

	return &TPSLOrder{
		OriginalOrderID: t.OriginalOrderID,
		TPOrderID:       t.TPOrderID,
		SLOrder:         t.SLOrder.Copy(),
		SLTriggerPrice:  t.SLTriggerPrice.Clone(),
		SLTriggerAbove:  t.SLTriggerAbove,
		Status:          t.Status,
		CreatedAt:       t.CreatedAt,
	}
}
