package pipeline

// This file shows how to integrate the new pipeline system with symbol_engine.go
// It's an example/documentation file, not meant to be compiled directly

/*
Example integration with symbol_engine.go:

// In symbol_engine.go, add:

import "github.com/kaiachain/kaia-orderbook-dex-core/go-ethereum/core/orderbook/pipeline"

type SymbolEngine struct {
    // ... existing fields ...
    
    // Add pipeline manager
    pipelineManager *pipeline.PipelineManager
}

func NewSymbolEngine(symbol string) *SymbolEngine {
    e := &SymbolEngine{
        // ... existing initialization ...
    }
    
    // Initialize pipeline manager
    e.pipelineManager = pipeline.NewPipelineManager()
    
    // Enable modify support if needed
    e.pipelineManager.EnableModifySupport()
    
    return e
}

// Update processOrder to use pipeline
func (e *SymbolEngine) processOrder(order *Order, locker *DefaultLocker) ([]*Trade, []string, []OrderbookEvent) {
    // Create context
    ctx := pipeline.NewOrderContext(order, locker, e)
    ctx.Metadata["action"] = "order"
    
    // Execute pipeline
    err := e.pipelineManager.GetTradingPipeline().Execute(ctx)
    if err != nil {
        log.Error("Pipeline execution failed", "error", err)
        // Fallback to legacy processing
        return e.processOrderLegacy(order, locker)
    }
    
    // Extract results from context
    trades := convertTrades(ctx.Trades)
    events := convertEvents(ctx.Events)
    
    // Process triggered orders
    var triggeredOrderIDs []string
    for _, triggered := range ctx.TriggeredOrders {
        triggeredOrder := triggered.(*TriggeredOrder)
        triggeredOrderIDs = append(triggeredOrderIDs, triggeredOrder.order.OrderID)
        
        // Process triggered order through pipeline
        triggeredCtx := pipeline.NewOrderContext(triggeredOrder.order, locker, e)
        triggeredCtx.Metadata["action"] = "order"
        
        if err := e.pipelineManager.GetTradingPipeline().Execute(triggeredCtx); err != nil {
            log.Error("Pipeline execution failed for triggered order", "error", err)
            // Fallback to legacy
            stopTrades, stopEvents := e.processOrderWithoutStopOrder(triggeredOrder.order, locker)
            trades = append(trades, stopTrades...)
            events = append(events, stopEvents...)
        } else {
            trades = append(trades, convertTrades(triggeredCtx.Trades)...)
            events = append(events, convertEvents(triggeredCtx.Events)...)
        }
    }
    
    return trades, triggeredOrderIDs, events
}

// Update cancelOrder to use pipeline
func (e *SymbolEngine) cancelOrder(orderID string, locker *DefaultLocker) (bool, []string, []OrderbookEvent) {
    // Create context for cancel
    ctx := pipeline.NewOrderContext(nil, locker, e)
    ctx.Metadata["action"] = "cancel"
    ctx.Metadata["orderID"] = orderID
    
    // Execute management pipeline
    err := e.pipelineManager.GetManagementPipeline().Execute(ctx)
    if err != nil {
        log.Error("Cancel pipeline failed", "error", err)
        // Fallback to legacy
        return e.cancelOrderLegacy(orderID, locker)
    }
    
    // Extract results
    success := ctx.Metadata["cancelSuccess"].(bool)
    cancelledIDs := ctx.Metadata["cancelledOrderIDs"].([]string)
    events := convertEvents(ctx.Events)
    
    return success, cancelledIDs, events
}

// Update cancelAllOrdersByUser to use pipeline
func (e *SymbolEngine) cancelAllOrdersByUser(userId string, locker *DefaultLocker) ([]string, []OrderbookEvent) {
    // Create context for cancel all
    ctx := pipeline.NewOrderContext(nil, locker, e)
    ctx.Metadata["action"] = "cancel_all"
    ctx.Metadata["userID"] = userId
    
    // Execute management pipeline
    err := e.pipelineManager.GetManagementPipeline().Execute(ctx)
    if err != nil {
        log.Error("Cancel all pipeline failed", "error", err)
        // Fallback to legacy
        return e.cancelAllOrdersByUserLegacy(userId, locker)
    }
    
    // Extract results
    cancelledIDs := ctx.Metadata["cancelledOrderIDs"].([]string)
    events := convertEvents(ctx.Events)
    
    return cancelledIDs, events
}

// Update modifyRequest to use pipeline
func (e *SymbolEngine) modifyRequest(args *ModifyArgs, locker *DefaultLocker) ([]*Trade, []string, []string, bool, []OrderbookEvent) {
    // First cancel the old order using management pipeline
    cancelCtx := pipeline.NewOrderContext(nil, locker, e)
    cancelCtx.Metadata["action"] = "cancel"
    cancelCtx.Metadata["orderID"] = args.OrderId
    
    err := e.pipelineManager.GetManagementPipeline().Execute(cancelCtx)
    if err != nil || !cancelCtx.Metadata["cancelSuccess"].(bool) {
        log.Warn("Failed to cancel order for modify", "error", err)
        return nil, nil, nil, false, nil
    }
    
    cancelledIDs := cancelCtx.Metadata["cancelledOrderIDs"].([]string)
    cancelEvents := convertEvents(cancelCtx.Events)
    
    // Create new order with modifications
    newOrder := createModifiedOrder(args)
    
    // Process new order through trading pipeline
    orderCtx := pipeline.NewOrderContext(newOrder, locker, e)
    orderCtx.Metadata["action"] = "modify"
    orderCtx.Metadata["cancelledOrderID"] = args.OrderId
    orderCtx.Metadata["cancelledOrderIDs"] = cancelledIDs
    
    err = e.pipelineManager.GetTradingPipeline().Execute(orderCtx)
    if err != nil {
        log.Error("Modify pipeline failed", "error", err)
        return nil, nil, cancelledIDs, false, cancelEvents
    }
    
    // Extract results
    trades := convertTrades(orderCtx.Trades)
    triggered := orderCtx.TriggeredOrderIDs
    events := append(cancelEvents, convertEvents(orderCtx.Events)...)
    
    return trades, triggered, cancelledIDs, true, events
}

// Update addStopOrder to use pipeline
func (e *SymbolEngine) addStopOrder(stopOrder *StopOrder, locker *DefaultLocker) ([]*Trade, []string, *bool, []OrderbookEvent) {
    // Check if should trigger immediately
    shouldTrigger, triggerAbove := e.conditionalOrderManager.ShouldTriggerImmediately(stopOrder, e.currentPrice)
    
    if shouldTrigger {
        // Process as regular order through pipeline
        ctx := pipeline.NewOrderContext(stopOrder.Order, locker, e)
        ctx.Metadata["action"] = "stop_order"
        
        err := e.pipelineManager.GetTradingPipeline().Execute(ctx)
        if err != nil {
            log.Error("Stop order pipeline failed", "error", err)
            // Fallback to legacy
            trades, triggered, events := e.processOrderLegacy(stopOrder.Order, locker)
            triggered = append([]string{stopOrder.Order.OrderID}, triggered...)
            return trades, triggered, nil, events
        }
        
        trades := convertTrades(ctx.Trades)
        triggered := append([]string{stopOrder.Order.OrderID}, ctx.TriggeredOrderIDs...)
        events := convertEvents(ctx.Events)
        
        return trades, triggered, nil, events
    }
    
    // Add to conditional manager (not triggered)
    e.conditionalOrderManager.AddStopOrder(stopOrder, e.currentPrice, locker)
    
    // Generate event
    event := &TPSLOrderAddedEvent{
        BaseEvent: e.createEvent(),
        TPSLOrder: createTPSLFromStop(stopOrder, triggerAbove),
    }
    
    return nil, nil, &triggerAbove, []OrderbookEvent{event}
}

// Helper functions for type conversion
func convertTrades(trades []interface{}) []*Trade {
    result := make([]*Trade, len(trades))
    for i, t := range trades {
        result[i] = t.(*Trade)
    }
    return result
}

func convertEvents(events []interface{}) []OrderbookEvent {
    result := make([]OrderbookEvent, len(events))
    for i, e := range events {
        result[i] = e.(OrderbookEvent)
    }
    return result
}
*/