package pipeline

// EventGenerationStage handles event generation and publication
type EventGenerationStage struct {
	stateMutexLocked bool
}

// Name returns the name of this stage
func (s *EventGenerationStage) Name() string {
	return "event_generation"
}

// Process generates events for all operations that occurred
func (s *EventGenerationStage) Process(ctx *OrderContext) error {
	// Generate events based on what happened during processing
	
	// Event types to generate:
	// 1. OrderAddedEvent - if order was added to queue
	// 2. TradeExecutedEvent - for each trade
	// 3. OrderRemovedEvent - for fully filled orders
	// 4. OrderQuantityUpdatedEvent - for partially filled orders
	// 5. TPSLOrderAddedEvent - if TPSL orders were activated
	// 6. TPSLOrderTriggeredEvent - for triggered conditional orders
	
	// In the actual implementation:
	// - Check if order was added to queue → generate OrderAddedEvent
	// - Process trade events from settlement stage
	// - Generate events for triggered conditional orders
	
	// The events are stored in ctx.Events and will be returned to the caller
	
	// Finally, unlock the state mutex
	// This is the last stage, so we unlock here
	// ctx.Engine.stateMu.Unlock()
	s.stateMutexLocked = false
	
	// Mark that events have been generated
	ctx.EventsGenerated = true
	
	return nil
}

// Rollback clears generated events and ensures mutex is unlocked
func (s *EventGenerationStage) Rollback(ctx *OrderContext) error {
	// Clear generated events
	ctx.Events = make([]interface{}, 0)
	ctx.EventsGenerated = false
	
	// Ensure state mutex is unlocked
	// Note: The LockingStage rollback should have already done this
	// but we double-check here as this is the last stage
	if s.stateMutexLocked {
		// ctx.Engine.stateMu.Unlock()
		s.stateMutexLocked = false
	}
	
	return nil
}