package tpsl

import (
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
)

// StopLossTrigger implements a stop-loss trigger
type StopLossTrigger struct {
	Order        *types.Order     // The order to execute when triggered
	StopPrice    *uint256.Int     // The trigger price
	TriggerAbove bool             // true: trigger when price >= stopPrice
	Status       types.OrderStatus
}

// NewStopLossTrigger creates a new stop-loss trigger
func NewStopLossTrigger(order *types.Order, stopPrice *uint256.Int, triggerAbove bool) *StopLossTrigger {
	return &StopLossTrigger{
		Order:        order,
		StopPrice:    stopPrice,
		TriggerAbove: triggerAbove,
		Status:       types.TRIGGER_WAIT,
	}
}

// GetOrderID returns the order ID
func (t *StopLossTrigger) GetOrderID() types.OrderID {
	if t.Order != nil {
		return t.Order.OrderID
	}
	return ""
}

// GetUserID returns the user ID
func (t *StopLossTrigger) GetUserID() types.UserID {
	if t.Order != nil {
		return t.Order.UserID
	}
	return ""
}

// ShouldTrigger checks if the trigger condition is met
func (t *StopLossTrigger) ShouldTrigger(currentPrice *uint256.Int) bool {
	if t.Status != types.TRIGGER_WAIT {
		return false
	}
	if currentPrice == nil || t.StopPrice == nil {
		return false
	}

	if t.TriggerAbove {
		return currentPrice.Cmp(t.StopPrice) >= 0
	}
	return currentPrice.Cmp(t.StopPrice) <= 0
}

// Execute returns the order to execute
func (t *StopLossTrigger) Execute() *types.Order {
	if t.Order == nil || t.Status != types.TRIGGER_WAIT {
		return nil
	}

	t.Status = types.TRIGGERED
	t.Order.Status = types.TRIGGERED
	return t.Order
}

// Cancel cancels the trigger
func (t *StopLossTrigger) Cancel() {
	t.Status = types.CANCELLED
	if t.Order != nil {
		t.Order.Status = types.CANCELLED
	}
}

// GetOrder returns the underlying order
func (t *StopLossTrigger) GetOrder() *types.Order {
	return t.Order
}

// GetStopPrice returns the stop price
func (t *StopLossTrigger) GetStopPrice() *uint256.Int {
	return t.StopPrice
}

// IsTriggerAbove returns whether trigger is above price
func (t *StopLossTrigger) IsTriggerAbove() bool {
	return t.TriggerAbove
}

// StopOrderTrigger implements a stop order trigger
type StopOrderTrigger struct {
	Order        *types.Order
	StopPrice    *uint256.Int
	TriggerAbove bool
	Status       types.OrderStatus
}

// NewStopOrderTrigger creates a new stop order trigger
func NewStopOrderTrigger(order *types.Order, stopPrice *uint256.Int, triggerAbove bool) *StopOrderTrigger {
	return &StopOrderTrigger{
		Order:        order,
		StopPrice:    stopPrice,
		TriggerAbove: triggerAbove,
		Status:       types.TRIGGER_WAIT,
	}
}

// GetOrderID returns the order ID
func (t *StopOrderTrigger) GetOrderID() types.OrderID {
	if t.Order != nil {
		return t.Order.OrderID
	}
	return ""
}

// GetUserID returns the user ID
func (t *StopOrderTrigger) GetUserID() types.UserID {
	if t.Order != nil {
		return t.Order.UserID
	}
	return ""
}

// ShouldTrigger checks if the trigger condition is met
func (t *StopOrderTrigger) ShouldTrigger(currentPrice *uint256.Int) bool {
	if t.Status != types.TRIGGER_WAIT {
		return false
	}
	if currentPrice == nil || t.StopPrice == nil {
		return false
	}

	if t.TriggerAbove {
		return currentPrice.Cmp(t.StopPrice) >= 0
	}
	return currentPrice.Cmp(t.StopPrice) <= 0
}

// Execute returns the order to execute
func (t *StopOrderTrigger) Execute() *types.Order {
	if t.Order == nil || t.Status != types.TRIGGER_WAIT {
		return nil
	}

	t.Status = types.TRIGGERED
	t.Order.Status = types.TRIGGERED

	return t.Order
}

// Cancel cancels the trigger
func (t *StopOrderTrigger) Cancel() {
	t.Status = types.CANCELLED
	if t.Order != nil {
		t.Order.Status = types.CANCELLED
	}
}

// GetOrder returns the underlying order
func (t *StopOrderTrigger) GetOrder() *types.Order {
	return t.Order
}

// GetStopPrice returns the stop price
func (t *StopOrderTrigger) GetStopPrice() *uint256.Int {
	return t.StopPrice
}

// IsTriggerAbove returns whether this is a trigger above price
func (t *StopOrderTrigger) IsTriggerAbove() bool {
	return t.TriggerAbove
}