package pipeline

// ConditionalCheckStage handles TPSL/Stop order trigger checks after matching
type ConditionalCheckStage struct{}

// Name returns the name of this stage
func (s *ConditionalCheckStage) Name() string {
	return "conditional_check"
}

// Process checks and triggers conditional orders based on the last trade price
func (s *ConditionalCheckStage) Process(ctx *OrderContext) error {
	// Check if any trades were executed
	if len(ctx.Trades) == 0 {
		// No trades, no price update, no conditional checks needed
		return nil
	}
	
	// Check if we have a last trade price
	if ctx.LastTradePrice == nil {
		// No price to check against
		return nil
	}
	
	// Check TPSL orders
	// This will delegate to the engine's checkTPSLOrders method
	// In the actual implementation:
	// 1. Update current price: ctx.Engine.currentPrice = ctx.LastTradePrice
	// 2. Check conditional orders: ctx.Engine.checkTPSLOrders(ctx.LastTradePrice, ctx.Locker)
	// 3. Collect triggered orders: ctx.TriggeredOrders = ctx.Engine.triggered
	
	// The triggered orders will be processed after the main pipeline completes
	// This matches the current implementation where triggered orders are processed
	// in a loop after the main order processing
	
	// Also check if the current order being processed has TPSL attached
	// and if it's fully filled, activate the TPSL orders
	// This logic is currently in processSingleTrade:
	// if order.Quantity.IsZero() && order.TPSL != nil {
	//     ctx.Engine.addTPSLOrder(order.TPSL, ctx.Locker)
	// }
	
	return nil
}

// Rollback reverses any conditional order triggers
func (s *ConditionalCheckStage) Rollback(ctx *OrderContext) error {
	// Clear triggered orders from context
	ctx.TriggeredOrders = make([]interface{}, 0)
	
	// In future, we could implement more sophisticated rollback
	// For now, just clear the triggered orders list
	
	return nil
}