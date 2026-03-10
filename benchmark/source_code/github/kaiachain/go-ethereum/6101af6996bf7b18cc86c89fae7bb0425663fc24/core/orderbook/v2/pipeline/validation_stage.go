package pipeline

import (
	"errors"
)

// ValidationStage handles order validation and permission checks
type ValidationStage struct{}

// Name returns the name of this stage
func (s *ValidationStage) Name() string {
	return "validation"
}

// Process validates the order and checks permissions
func (s *ValidationStage) Process(ctx *OrderContext) error {
	// Check if locker is nil
	if ctx.Locker == nil {
		return errors.New("locker is nil")
	}
	
	// Check if order is nil
	if ctx.Order == nil {
		return errors.New("order is nil")
	}
	
	// Check if engine is nil
	if ctx.Engine == nil {
		return errors.New("engine is nil")
	}
	
	// Initialize empty slices for outputs
	if ctx.Trades == nil {
		ctx.Trades = make([]interface{}, 0)
	}
	if ctx.Events == nil {
		ctx.Events = make([]interface{}, 0)
	}
	if ctx.TriggeredOrders == nil {
		ctx.TriggeredOrders = make([]interface{}, 0)
	}
	
	// Additional validation can be added here:
	// - Check order fields (price, quantity, etc.)
	// - Verify user permissions
	// - Check symbol validity
	// - Validate order type constraints
	
	return nil
}

// Rollback does nothing for validation stage
func (s *ValidationStage) Rollback(ctx *OrderContext) error {
	// Validation doesn't modify state, so nothing to rollback
	return nil
}