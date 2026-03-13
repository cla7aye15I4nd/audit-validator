package pipeline

// MatchingStage handles order matching against the opposite queue
type MatchingStage struct{}

// Name returns the name of this stage
func (s *MatchingStage) Name() string {
	return "matching"
}

// Process matches the order against the opposite side queue
func (s *MatchingStage) Process(ctx *OrderContext) error {
	// Match order based on side
	// This will delegate to the engine's tradeMatcher
	
	// In the actual implementation, this will:
	// 1. Check order side (BUY or SELL)
	// 2. Call appropriate matching function:
	//    - For BUY: trades, executedCost := ctx.Engine.tradeMatcher.matchBuyOrder(...)
	//    - For SELL: trades, executedQty := ctx.Engine.tradeMatcher.matchSellOrder(...)
	// 3. Handle market order refunds if necessary
	// 4. Store results in context
	
	// For now, we just prepare the structure
	// The actual matching logic will be integrated when we connect with the main orderbook package
	
	// Store matching results in context
	// ctx.Trades = trades
	// ctx.ExecutedCost = executedCost (for buy orders)
	// ctx.ExecutedQty = executedQty (for sell orders)
	
	// Also store the last trade price for conditional order checking
	// if len(trades) > 0 {
	//     ctx.LastTradePrice = trades[len(trades)-1].Price
	// }
	
	return nil
}

// Rollback reverses any matching operations
func (s *MatchingStage) Rollback(ctx *OrderContext) error {
	// In future, we could implement trade reversal here
	// For now, the existing implementation doesn't support this
	return nil
}