package pipeline

import (
	"errors"
)

// NewManagementPipeline creates a pipeline for order management operations
// Handles: CANCEL, CANCEL_ALL
func NewManagementPipeline() *Pipeline {
	return NewPipeline(
		&CancelValidationStage{},
		&LockingStage{}, // Reuses the same locking stage
		&CancelExecutionStage{},
		&EventGenerationStage{}, // Reuses the same event stage
	)
}

// CancelValidationStage validates cancel and cancel-all requests
type CancelValidationStage struct{}

func (s *CancelValidationStage) Name() string {
	return "cancel_validation"
}

func (s *CancelValidationStage) Process(ctx *OrderContext) error {
	// Check if locker is nil
	if ctx.Locker == nil {
		return errors.New("locker is nil")
	}
	
	// Check if engine is nil
	if ctx.Engine == nil {
		return errors.New("engine is nil")
	}
	
	// Initialize empty slices for outputs
	if ctx.Events == nil {
		ctx.Events = make([]interface{}, 0)
	}
	
	// Check for cancel-specific parameters
	if ctx.Metadata["action"] == "cancel" {
		// Single order cancel
		orderID, exists := ctx.Metadata["orderID"]
		if !exists || orderID == "" {
			return errors.New("orderID is required for cancel operation")
		}
		
		// Verify order exists and ownership (this will be done in execution stage)
		// Just validate the input format here
		
	} else if ctx.Metadata["action"] == "cancel_all" {
		// Cancel all orders for a user
		userID, exists := ctx.Metadata["userID"]
		if !exists || userID == "" {
			return errors.New("userID is required for cancel_all operation")
		}
	} else {
		return errors.New("unknown cancel action")
	}
	
	return nil
}

func (s *CancelValidationStage) Rollback(ctx *OrderContext) error {
	// Validation doesn't modify state, so nothing to rollback
	return nil
}

// CancelExecutionStage executes the actual cancellation
type CancelExecutionStage struct{}

func (s *CancelExecutionStage) Name() string {
	return "cancel_execution"
}

func (s *CancelExecutionStage) Process(ctx *OrderContext) error {
	// This stage will delegate to the engine's cancel logic
	// The actual implementation will be done when we integrate with the main orderbook package
	
	action := ctx.Metadata["action"]
	
	if action == "cancel" {
		// Cancel single order
		// In actual implementation:
		// orderID := ctx.Metadata["orderID"].(string)
		// success, cancelledIDs := ctx.Engine.cancelOrderInternal(orderID, ctx.Locker)
		// ctx.Metadata["cancelledOrderIDs"] = cancelledIDs
		// ctx.Metadata["cancelSuccess"] = success
		
		// For now, just set placeholder results
		ctx.Metadata["cancelledOrderIDs"] = []string{}
		ctx.Metadata["cancelSuccess"] = true
		
	} else if action == "cancel_all" {
		// Cancel all orders for user
		// In actual implementation:
		// userID := ctx.Metadata["userID"].(string)
		// cancelledIDs := ctx.Engine.cancelAllOrdersByUserInternal(userID, ctx.Locker)
		// ctx.Metadata["cancelledOrderIDs"] = cancelledIDs
		
		// For now, just set placeholder results
		ctx.Metadata["cancelledOrderIDs"] = []string{}
	}
	
	return nil
}

func (s *CancelExecutionStage) Rollback(ctx *OrderContext) error {
	// To rollback cancellation, we would need to restore the orders
	// This is complex and might not be supported in the current implementation
	// For now, we just clear the results
	delete(ctx.Metadata, "cancelledOrderIDs")
	delete(ctx.Metadata, "cancelSuccess")
	return nil
}