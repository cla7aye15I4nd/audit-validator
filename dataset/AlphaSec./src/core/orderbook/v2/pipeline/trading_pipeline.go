package pipeline

// NewTradingPipeline creates a pipeline for order trading operations
// Handles: ORDER, MODIFY (with preprocessing), STOP_ORDER
func NewTradingPipeline() *Pipeline {
	return NewPipeline(
		&ValidationStage{},
		&LockingStage{},
		&MatchingStage{},
		&ConditionalCheckStage{},
		&SettlementStage{},
		&QueueUpdateStage{},
		&EventGenerationStage{},
	)
}

// NewTradingPipelineWithModifySupport creates a pipeline that can handle modify operations
// The ModifyPreprocessStage will cancel the old order before matching the new one
func NewTradingPipelineWithModifySupport() *Pipeline {
	return NewPipeline(
		&ValidationStage{},
		&LockingStage{},
		&ModifyPreprocessStage{}, // Only included when modify support is needed
		&MatchingStage{},
		&ConditionalCheckStage{},
		&SettlementStage{},
		&QueueUpdateStage{},
		&EventGenerationStage{},
	)
}

// ModifyPreprocessStage handles the cancel step of a modify operation
type ModifyPreprocessStage struct{}

func (s *ModifyPreprocessStage) Name() string {
	return "modify_preprocess"
}

func (s *ModifyPreprocessStage) Process(ctx *OrderContext) error {
	// Check if this is a modify operation
	// This is indicated by having a "cancelledOrderID" in metadata
	cancelledID, exists := ctx.Metadata["cancelledOrderID"]
	if !exists {
		// Not a modify operation, skip this stage
		return nil
	}
	
	// The actual cancellation has already been done by the caller
	// This stage just needs to ensure the context is set up correctly
	// for the new order to be processed
	
	// Store the cancelled order ID in the context for event generation
	if ctx.Metadata["cancelledOrderIDs"] == nil {
		ctx.Metadata["cancelledOrderIDs"] = []string{}
	}
	
	cancelledIDs := ctx.Metadata["cancelledOrderIDs"].([]string)
	cancelledIDs = append(cancelledIDs, cancelledID.(string))
	ctx.Metadata["cancelledOrderIDs"] = cancelledIDs
	
	// The new order should already be in ctx.Order
	// Continue to matching stage
	
	return nil
}

func (s *ModifyPreprocessStage) Rollback(ctx *OrderContext) error {
	// If we need to rollback a modify, we should restore the cancelled order
	// However, this is complex and might not be supported in the current implementation
	// For now, we just clear the metadata
	delete(ctx.Metadata, "cancelledOrderID")
	delete(ctx.Metadata, "cancelledOrderIDs")
	return nil
}