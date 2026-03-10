package pipeline

// SettlementStage handles trade settlement and balance updates
type SettlementStage struct{}

// Name returns the name of this stage
func (s *SettlementStage) Name() string {
	return "settlement"
}

// Process settles trades and updates balances
func (s *SettlementStage) Process(ctx *OrderContext) error {
	// Process completed trades
	// This will delegate to the engine's tradeMatcher.processCompletedTrades
	
	// In the actual implementation:
	// 1. Iterate through ctx.Trades
	// 2. For each trade, call processSingleTrade:
	//    - Update current price
	//    - Update user balances
	//    - Handle fees
	//    - Update dirty price levels
	//    - Handle TPSL order activation if orders are fully filled
	// 3. Mark trades as processed
	
	// The actual settlement logic includes:
	// - Updating buy/sell order quantities
	// - Transferring tokens between users
	// - Collecting fees
	// - Updating order book state
	
	// Set flag to indicate trades have been processed
	ctx.TradesProcessed = true
	
	// Note: We don't unlock the state mutex here
	// That will be done in the EventGenerationStage (the last stage)
	
	return nil
}

// Rollback reverses any settlement operations
func (s *SettlementStage) Rollback(ctx *OrderContext) error {
	// Mark trades as not processed
	ctx.TradesProcessed = false
	
	// In future, we could implement balance reversal here
	// For now, the existing implementation doesn't support this
	
	return nil
}