package dispatcher

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/balance"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/engine"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/metrics"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/persistence"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// Dispatcher manages symbol engines and coordinates balance operations
// Now with async channel-based processing aligned with v1 pattern
type Dispatcher struct {
	engines        map[types.Symbol]*engine.SymbolEngine
	balanceManager *balance.Manager
	stateDB        types.StateDB
	marketRules    *types.MarketRules // Market rules for initial validation
	mu             sync.RWMutex

	// Async processing
	requestChan chan interfaces.Request
	workerCount int

	// Symbol routing for order lookup
	symbolRouting map[string]types.Symbol
	orderCache    map[string]*types.Order

	// Lifecycle management
	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup

	// Metrics tracking (moved to metrics package)
	lastRequestCount int64

	// Persistence
	persistence *persistence.PersistenceManager
}

// NewDispatcher creates a new dispatcher with default configuration
// StateDB will be provided dynamically per request via SetStateDB
func NewDispatcher(p *persistence.PersistenceManager) *Dispatcher {
	ctx, cancel := context.WithCancel(context.Background())
	balanceManager := balance.NewManager()

	return &Dispatcher{
		engines:          make(map[types.Symbol]*engine.SymbolEngine),
		balanceManager:   balanceManager,
		stateDB:          nil,                                 // Will be set per request
		marketRules:      types.NewMarketRules(),              // Initialize market rules
		requestChan:      make(chan interfaces.Request, 1000), // Buffered channel
		workerCount:      1,                                   // Single worker for now, can be increased for parallel processing
		symbolRouting:    make(map[string]types.Symbol),
		orderCache:       make(map[string]*types.Order),
		ctx:              ctx,
		cancel:           cancel,
		persistence:      p,
		lastRequestCount: 0,
	}
}

// NewDispatcherWithConfig creates a new dispatcher with custom balance configuration
// StateDB will be provided dynamically per request via SetStateDB
func NewDispatcherWithConfig(config types.BalanceManagerConfig) *Dispatcher {
	ctx, cancel := context.WithCancel(context.Background())

	balanceManager := balance.NewManagerWithConfig(config)

	return &Dispatcher{
		engines:        make(map[types.Symbol]*engine.SymbolEngine),
		balanceManager: balanceManager,
		stateDB:        nil,                    // Will be set per request
		marketRules:    types.NewMarketRules(), // Initialize market rules
		requestChan:    make(chan interfaces.Request, 1000),
		workerCount:    1,
		symbolRouting:  make(map[string]types.Symbol),
		orderCache:     make(map[string]*types.Order),
		ctx:            ctx,
		cancel:         cancel,
	}
}

// Start starts the dispatcher's worker goroutines
func (d *Dispatcher) Start() {

	for i := 0; i < d.workerCount; i++ {
		d.wg.Add(1)
		go d.processWorker()
	}
	log.Debug("Dispatcher started", "workers", d.workerCount)
}

// Stop gracefully shuts down the dispatcher
func (d *Dispatcher) Stop() error {
	log.Debug("Stopping dispatcher...")

	// Cancel context to stop accepting new requests
	d.cancel()

	// Close request channel to stop workers
	close(d.requestChan)

	// Wait for all workers to finish
	d.wg.Wait()

	log.Debug("Dispatcher stopped")
	return nil
}

// DispatchReq implements the async dispatch pattern (v1 compatible)
func (d *Dispatcher) DispatchReq(req interfaces.Request) {
	queueDepth := len(d.requestChan)

	// Update queue depth metric
	metrics.DispatcherQueueLengthGauge.Update(int64(queueDepth))

	if queueDepth > 800 {
		log.Warn("High request queue depth", "depth", queueDepth, "max", 1000)
	}

	select {
	case d.requestChan <- req:
		// Request queued successfully
		metrics.DispatcherRequestsTotal.Inc(1)
		log.Trace("Request queued", "queueDepth", queueDepth+1)
	case <-d.ctx.Done():
		// Dispatcher is shutting down
		log.Error("Dispatcher shutting down, rejecting request")
		metrics.DispatcherRequestsFailed.Inc(1)
		req.ResponseChannel() <- interfaces.NewErrorResponse(errors.New("dispatcher shutting down"))
	}
}

// processWorker is the worker goroutine that processes requests
func (d *Dispatcher) processWorker() {
	defer d.wg.Done()

	for req := range d.requestChan {
		resp := d.processRequest(req)
		select {
		case req.ResponseChannel() <- resp:
			// Response sent successfully
		case <-d.ctx.Done():
			// Context cancelled, exit worker
			return
		}
	}
}

// processRequest processes a single request and returns a response
func (d *Dispatcher) processRequest(req interfaces.Request) interfaces.Response {
	// Start processing timer
	startTime := time.Now()
	defer func() {
		metrics.DispatcherProcessingTimer.UpdateSince(startTime)
	}()

	if req == nil {
		metrics.DispatcherRequestsFailed.Inc(1)
		return interfaces.NewErrorResponse(fmt.Errorf("request cannot be nil"))
	}

	//// Log request to WAL if persistence is enabled
	//var walSequence uint64
	//if d.persistence != nil {
	//	seq, err := d.persistence.LogRequest(req)
	//	if err != nil {
	//		log.Error("Failed to log request to WAL", "error", err)
	//	} else {
	//		walSequence = seq
	//	}
	//}

	// Update balance manager's StateDB if provided in request
	if req.StateDB() != nil {
		d.balanceManager.SetStateDB(req.StateDB())
	}

	// Update balance manager's FeeRetriever if provided in request
	if req.FeeGetter() != nil {
		d.balanceManager.SetFeeRetriever(req.FeeGetter())
	}

	// Route based on request type
	var resp interfaces.Response
	switch r := req.(type) {
	case *interfaces.OrderRequest:
		resp = d.handleOrderRequest(r)
	case *interfaces.CancelRequest:
		resp = d.handleCancelRequest(r)
	case *interfaces.CancelAllRequest:
		resp = d.handleCancelAllRequest(r)
	case *interfaces.ModifyRequest:
		resp = d.handleModifyRequest(r)
	case *interfaces.StopOrderRequest:
		resp = d.handleStopOrderRequest(r)
	default:
		log.Error("Unsupported request type", "type", fmt.Sprintf("%T", req))
		metrics.DispatcherRequestsFailed.Inc(1)
		resp = interfaces.NewErrorResponse(fmt.Errorf("unsupported request type: %T", req))
	}

	//// Log response to WAL if persistence is enabled
	//if d.persistence != nil && walSequence > 0 {
	//	if err := d.persistence.LogResponse(walSequence, resp); err != nil {
	//		log.Error("Failed to log response to WAL", "error", err)
	//	}
	//}

	// Update success/failure metrics
	if resp.Error() != nil {
		metrics.DispatcherRequestsFailed.Inc(1)
	} else {
		metrics.DispatcherRequestsSuccessful.Inc(1)
	}

	return resp
}

// settleTrade handles trade settlement with balance manager
func (d *Dispatcher) settleTrade(trade *types.Trade) error {
	if trade == nil {
		return fmt.Errorf("trade cannot be nil")
	}

	// Settle through balance manager
	if err := d.balanceManager.SettleTrade(trade); err != nil {
		return fmt.Errorf("failed to settle trade %s: %w", trade.TradeID, err)
	}

	// Update volume metrics
	if trade.Price != nil && trade.Quantity != nil {
		volume := common.Uint256MulScaledDecimal(trade.Price, trade.Quantity)
		if volume != nil {
			// Convert volume to readable units (divide by 10^18)
			// This gives approximate volume in whole units
			oneEther := uint256.NewInt(1e18)
			volumeInUnits := new(uint256.Int).Div(volume, oneEther)
			metrics.DispatcherTotalVolumeGauge.Update(int64(volumeInUnits.Uint64()))
		}
	}

	// Note: Market order completion is now handled in handlePlaceOrder
	// after all trades are settled, not per-trade

	return nil
}

// processTradesAndCleanup handles trade settlement and removes fully filled orders from cache
func (d *Dispatcher) processTradesAndCleanup(trades []*types.Trade, context string) error {
	for _, trade := range trades {
		// Settle the trade
		if err := d.settleTrade(trade); err != nil {
			log.Error("[BALANCE INCONSISTENCY] Failed to settle trade",
				"tradeID", trade.TradeID,
				"context", context,
				"error", err)
			// Continue processing other trades even if one fails
		}

		// Clean up orders that can't be processed further (fully filled or dust)
		// Check if buy order should be unlocked
		if trade.IsBuyerMaker && trade.BuyOrderFullyFilled {
			d.balanceManager.CompleteOrder(string(trade.BuyOrderID))
			d.mu.Lock()
			delete(d.symbolRouting, string(trade.BuyOrderID))
			delete(d.orderCache, string(trade.BuyOrderID))
			d.mu.Unlock()
			log.Debug("Removed buy order from cache (filled or dust)",
				"orderID", trade.BuyOrderID,
				"fullyFilled", trade.BuyOrderFullyFilled,
				"tradeID", trade.TradeID,
				"context", context)
		}

		// Check if sell order should be unlocked
		if !trade.IsBuyerMaker && trade.SellOrderFullyFilled {
			d.balanceManager.CompleteOrder(string(trade.SellOrderID))
			d.mu.Lock()
			delete(d.symbolRouting, string(trade.SellOrderID))
			delete(d.orderCache, string(trade.SellOrderID))
			d.mu.Unlock()
			log.Debug("Removed sell order from cache (filled or dust)",
				"orderID", trade.SellOrderID,
				"fullyFilled", trade.SellOrderFullyFilled,
				"tradeID", trade.TradeID,
				"context", context)
		}
	}
	return nil
}

// getOrCreateEngine gets existing engine or creates new one
func (d *Dispatcher) getOrCreateEngine(symbol types.Symbol) *engine.SymbolEngine {
	d.mu.Lock()
	defer d.mu.Unlock()

	eng, exists := d.engines[symbol]
	if !exists {
		// TEMPORARY FIX: Pass balance manager to engine for TPSL lock inheritance
		// TODO-Orderbook: Refactor to proper architecture after settlement timing is fixed
		eng = engine.NewSymbolEngine(symbol, d.balanceManager)
		d.engines[symbol] = eng
		log.Debug("Created new symbol engine", "symbol", symbol)

		// Update active engines metric
		metrics.DispatcherActiveEnginesGauge.Update(int64(len(d.engines)))
	}

	return eng
}

// getEngine gets existing engine
func (d *Dispatcher) getEngine(symbol types.Symbol) *engine.SymbolEngine {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.engines[symbol]
}

// GetEngine returns the engine for a symbol (nil if not exists) - public version
func (d *Dispatcher) GetEngine(symbol types.Symbol) interface{} {
	return d.getEngine(symbol)
}

// GetOrCreateEngine returns existing or creates new engine for symbol - public version
func (d *Dispatcher) GetOrCreateEngine(symbol types.Symbol) *engine.SymbolEngine {
	return d.getOrCreateEngine(symbol)
}

// GetCachedOrder returns a cached order by ID (for v1 compatibility)
func (d *Dispatcher) GetCachedOrder(orderID string) *types.Order {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.orderCache[orderID]
}

// New handler methods for interface-based requests

// handleOrderRequest processes an order placement request
func (d *Dispatcher) handleOrderRequest(req *interfaces.OrderRequest) interfaces.Response {
	order := req.Order
	if order == nil {
		return interfaces.NewErrorResponse(fmt.Errorf("order cannot be nil"))
	}

	log.Debug("Processing order",
		"orderID", order.OrderID,
		"user", order.UserID,
		"symbol", order.Symbol,
		"type", order.OrderType,
		"side", order.Side,
		"price", order.Price,
		"quantity", order.Quantity)

	// Lock balance
	if err := d.balanceManager.LockForOrder(order); err != nil {
		log.Error("Failed to lock balance for order",
			"orderID", order.OrderID,
			"user", order.UserID,
			"error", err)
		return interfaces.NewErrorResponse(err)
	}

	// Get or create engine
	engine := d.getOrCreateEngine(order.Symbol)

	// Process order (returns multiple results for main + triggered orders)
	engineResults, err := engine.ProcessOrder(order)
	if err != nil {
		// Rollback balance lock
		d.balanceManager.CompleteOrder(string(order.OrderID))
		log.Error("Failed to process order",
			"orderID", order.OrderID,
			"error", err)
		return interfaces.NewErrorResponse(err)
	}

	log.Debug("Order processed successfully",
		"orderID", order.OrderID,
		"results", len(engineResults))

	// Process all order results and build response
	return d.processOrderResults(order, engineResults)
}

// processOrderResults processes engine results and builds the response
func (d *Dispatcher) processOrderResults(mainOrder *types.Order, results []*engine.OrderResult) interfaces.Response {
	var allTrades []*types.Trade
	var allTriggeredIds []types.OrderID
	var failedOrders types.FailedOrders
	var completedOrderIDs types.OrderIDs

	// TODO-Orderbook: This is a quick fix for TPSL order cancellation
	// The proper solution is to have a unified order management system that tracks all order types
	// (regular, conditional, TPSL) in a consistent way. This pre-registration is a workaround
	// to ensure TPSL order IDs can be found when cancellation is requested.
	// This should be refactored when the orderbook architecture is properly redesigned.
	// If the main order has TPSL and was filled, pre-register the TPSL order IDs
	// This ensures they can be found when cancellation is requested
	if mainOrder != nil && mainOrder.HasTPSL() {
		d.mu.Lock()
		// Generate and register TP order ID
		tpOrderID := types.GenerateTPOrderID(mainOrder.OrderID)
		d.symbolRouting[string(tpOrderID)] = mainOrder.Symbol

		// Generate and register SL order ID
		slOrderID := types.GenerateSLOrderID(mainOrder.OrderID)
		d.symbolRouting[string(slOrderID)] = mainOrder.Symbol
		d.mu.Unlock()

		log.Debug("Pre-registered TPSL order IDs after order fill",
			"mainOrderID", mainOrder.OrderID,
			"tpOrderID", tpOrderID,
			"slOrderID", slOrderID,
			"symbol", mainOrder.Symbol)
	}

	// Process each order result (main order + triggered orders)
	for _, result := range results {
		d.mu.Lock()
		d.symbolRouting[string(result.OrderID)] = result.Symbol
		d.orderCache[string(result.OrderID)] = result.Order
		d.mu.Unlock()

		// Handle trades for this order
		if result.Trades != nil && len(result.Trades) > 0 {
			d.processTradesAndCleanup(result.Trades, "order_processing")
			allTrades = append(allTrades, result.Trades...)
		}

		// Complete market orders (always remove from cache regardless of trades)
		if result.Order != nil && result.Status.IsTerminal() {
			d.balanceManager.CompleteOrder(string(result.OrderID))
			// Remove from tracking
			d.mu.Lock()
			delete(d.symbolRouting, string(result.OrderID))
			delete(d.orderCache, string(result.OrderID))
			d.mu.Unlock()
			// Add to completed orders list if the order was filled (not cancelled/failed)
			if result.Status == types.FILLED {
				completedOrderIDs = append(completedOrderIDs, result.OrderID)
			}
			log.Debug("Removed terminated order from cache",
				"orderID", result.OrderID,
				"status", result.Status,
				"tradesGenerated", len(result.Trades))
		}

		// Collect triggered order IDs
		allTriggeredIds = append(allTriggeredIds, result.TriggeredOrderIds...)

		// Collect failed orders
		if len(result.FailedOrders) > 0 {
			for _, failed := range result.FailedOrders {
				d.balanceManager.CompleteOrder(string(failed.OrderID))
				d.mu.Lock()
				delete(d.symbolRouting, string(failed.OrderID))
				delete(d.orderCache, string(failed.OrderID))
				d.mu.Unlock()
				log.Debug("Removed failed order from cache",
					"orderID", failed.OrderID,
					"reason", failed.Reason)
			}
		}

		failedOrders = append(failedOrders, result.FailedOrders...)
	}

	// Update metrics
	metrics.DispatcherTotalOrders.Inc(1)
	if allTrades != nil {
		metrics.DispatcherTotalTrades.Inc(int64(len(allTrades)))
	}

	// Create response with all collected data
	var response *interfaces.OrderResponse
	if len(failedOrders) > 0 {
		log.Warn("Some orders failed during processing",
			"failedCount", len(failedOrders))
		response = interfaces.NewOrderResponseWithFailures(mainOrder, allTrades, allTriggeredIds, failedOrders)
	} else {
		response = interfaces.NewOrderResponse(mainOrder, allTrades, allTriggeredIds)
	}

	// Add completed order IDs to response
	response.CompletedOrderIDs = completedOrderIDs

	return response
}

// handleCancelRequest processes a cancel request
func (d *Dispatcher) handleCancelRequest(req *interfaces.CancelRequest) interfaces.Response {
	if req.OrderID == "" {
		return interfaces.NewErrorResponse(fmt.Errorf("orderID required for cancellation"))
	}

	log.Debug("Processing cancel request", "orderID", req.OrderID)

	// Look up symbol
	d.mu.RLock()
	s, found := d.symbolRouting[req.OrderID]
	d.mu.RUnlock()
	if !found {
		log.Error("Order not found for cancellation", "orderID", req.OrderID)
		return interfaces.NewErrorResponse(fmt.Errorf("order not found: %v", req.OrderID))
	}
	symbol := s

	// Get engine
	engine := d.getEngine(symbol)
	if engine == nil {
		log.Error("Symbol engine not found", "symbol", symbol)
		return interfaces.NewErrorResponse(fmt.Errorf("symbol engine not found"))
	}

	// Cancel order
	cancelResult, err := engine.CancelOrder(types.OrderID(req.OrderID))
	if err != nil {
		log.Error("Failed to cancel order", "orderID", req.OrderID, "error", err)
		return interfaces.NewErrorResponse(err)
	}

	// Unlock balance
	if cancelResult.Cancelled {
		d.balanceManager.CompleteOrder(req.OrderID)

		// Remove from cache
		d.mu.Lock()
		delete(d.orderCache, req.OrderID)
		delete(d.symbolRouting, req.OrderID)
		d.mu.Unlock()

		log.Debug("Order cancelled successfully",
			"orderID", req.OrderID,
			"cancelledCount", len(cancelResult.CancelledOrderIds))
	}

	return interfaces.NewCancelResponse(cancelResult.CancelledOrderIds)
}

// handleCancelAllRequest processes a cancel all request
func (d *Dispatcher) handleCancelAllRequest(req *interfaces.CancelAllRequest) interfaces.Response {
	if req.UserID == "" {
		return interfaces.NewErrorResponse(fmt.Errorf("userID required for cancel all"))
	}

	log.Debug("Processing cancel all request", "userID", req.UserID)

	// Unlock all balances for user
	unlockedOrders := d.balanceManager.UnlockAllForUser(req.UserID)
	log.Debug("Unlocked user balances", "userID", req.UserID, "orderCount", len(unlockedOrders))

	// Cancel in engines
	cancelledOrderIDs := make([]types.OrderID, 0)

	// Cancel across all symbols
	d.mu.RLock()
	engines := make([]*engine.SymbolEngine, 0, len(d.engines))
	for _, eng := range d.engines {
		engines = append(engines, eng)
	}
	d.mu.RUnlock()

	for _, eng := range engines {
		result, err := eng.CancelAllOrders(types.UserID(req.UserID))
		if err != nil {
			log.Error("Failed to cancel all orders in engine", "userID", req.UserID, "error", err)
			return interfaces.NewErrorResponse(fmt.Errorf("failed to cancelAll"))
		}

		if len(result.CancelledOrderIds) > 0 {
			log.Debug("Cancelled orders in engine",
				"count", len(result.CancelledOrderIds))
		}
		cancelledOrderIDs = append(cancelledOrderIDs, result.CancelledOrderIds...)
	}

	// Clean up cache for cancelled orders
	d.mu.Lock()
	for _, orderID := range unlockedOrders {
		delete(d.orderCache, orderID)
		delete(d.symbolRouting, orderID)
	}
	d.mu.Unlock()

	log.Debug("Cancel all completed",
		"userID", req.UserID,
		"totalCancelled", len(cancelledOrderIDs))

	return interfaces.NewCancelAllResponse(cancelledOrderIDs)
}

// handleModifyRequest processes a modify request
func (d *Dispatcher) handleModifyRequest(req *interfaces.ModifyRequest) interfaces.Response {
	if req.OrderID == "" {
		return interfaces.NewErrorResponse(fmt.Errorf("orderID required for modification"))
	}

	log.Debug("Processing modify request",
		"orderID", req.OrderID,
		"newOrderID", req.NewOrderID,
		"newPrice", req.NewPrice,
		"newQuantity", req.NewQuantity)

	// Look up symbol
	d.mu.RLock()
	s, found := d.symbolRouting[string(req.OrderID)]
	d.mu.RUnlock()
	if !found {
		log.Error("Order not found for modification", "orderID", req.OrderID)
		return interfaces.NewErrorResponse(fmt.Errorf("order not found: %s", req.OrderID))
	}
	symbol := s

	// Get engine
	eng := d.getOrCreateEngine(symbol)

	// Get the existing order from the engine's orderbook
	orderBook := eng.GetOrderBook()
	existingOrder, exists := orderBook.GetOrder(req.OrderID)
	if !exists {
		return interfaces.NewErrorResponse(fmt.Errorf("order %s not found in orderbook", req.OrderID))
	}

	// Step 1: Create the modified order using the helper function
	// This validates the modification without changing any state
	modifiedOrder, err := engine.CreateModifiedOrder(existingOrder, req.NewOrderID, req.NewPrice, req.NewQuantity)
	if err != nil {
		return interfaces.NewErrorResponse(fmt.Errorf("invalid modification: %w", err))
	}

	// Step 2: Pre-adjust locks BEFORE modifying the order
	// This ensures we have sufficient balance locked before the order becomes active
	if err := d.balanceManager.ModifyOrderLock(string(req.OrderID), modifiedOrder); err != nil {
		return interfaces.NewErrorResponse(fmt.Errorf("failed to adjust locks for modification: %w", err))
	}

	// Step 3: Now modify the order in the engine (cancels old, places new)
	// At this point, locks are already adjusted, so the new order can safely execute
	modifyResult, err := eng.ModifyOrder(req.OrderID, req.NewOrderID, req.NewPrice, req.NewQuantity)
	if err != nil {
		// Rollback lock changes if modification fails
		// Try to restore the original lock state
		log.Error("Order modification failed after lock adjustment, attempting to restore locks",
			"orderID", req.OrderID,
			"error", err)
		// Note: We can't perfectly rollback here since the original order might be partially filled
		// The best we can do is log the error for manual intervention
		return interfaces.NewErrorResponse(err)
	}

	// Step 4: Update cache BEFORE trade processing
	// This ensures new order is in cache so it can be removed if fully filled
	d.mu.Lock()
	delete(d.orderCache, string(req.OrderID))    // Remove old order
	delete(d.symbolRouting, string(req.OrderID)) // Remove old routing

	// Add new order to cache (may be removed during trade processing if fully filled)
	if modifyResult.NewOrder != nil {
		d.orderCache[string(req.NewOrderID)] = modifyResult.NewOrder
		d.symbolRouting[string(req.NewOrderID)] = symbol
	}
	d.mu.Unlock()

	// Step 5: Handle trades from modification
	if modifyResult.Trades != nil && len(modifyResult.Trades) > 0 {
		d.processTradesAndCleanup(modifyResult.Trades, "order_modification")
	}

	// Track completed orders
	var completedOrderIDs types.OrderIDs

	// Step 6: Check if the new order was fully filled and remove from cache
	if modifyResult.NewOrder != nil && modifyResult.NewOrder.Status.IsTerminal() {
		d.balanceManager.CompleteOrder(string(req.NewOrderID))
		d.mu.Lock()
		delete(d.symbolRouting, string(req.NewOrderID))
		delete(d.orderCache, string(req.NewOrderID))
		d.mu.Unlock()
		// Add to completed orders list if filled (not cancelled)
		if modifyResult.NewOrder.Status == types.FILLED {
			completedOrderIDs = append(completedOrderIDs, types.OrderID(req.NewOrderID))
		}
		log.Debug("Removed modified order from cache",
			"orderID", req.NewOrderID,
			"status", modifyResult.NewOrder.Status)
	}

	// Create response and add completed order IDs
	response := interfaces.NewModifyResponse(modifyResult.Trades, modifyResult.TriggeredOrderIds, modifyResult.CancelledOrderIds)
	response.CompletedOrderIDs = completedOrderIDs
	return response
}

// handleStopOrderRequest processes a stop order request
func (d *Dispatcher) handleStopOrderRequest(req *interfaces.StopOrderRequest) interfaces.Response {
	stopOrder := req.StopOrder
	if stopOrder == nil || stopOrder.Order == nil {
		return interfaces.NewErrorResponse(fmt.Errorf("stop order cannot be nil"))
	}

	// Get or create engine
	engine := d.getOrCreateEngine(stopOrder.Order.Symbol)

	// Check if current price exists (no trades have occurred yet)
	orderBook := engine.GetOrderBook()
	currentPrice := orderBook.GetCurrentPrice()
	if currentPrice == nil || currentPrice.IsZero() {
		return interfaces.NewErrorResponse(fmt.Errorf("cannot place stop order: no market price available"))
	}

	// Lock balance for stop order
	if err := d.balanceManager.LockForStopOrder(stopOrder); err != nil {
		return interfaces.NewErrorResponse(err)
	}

	// Process stop order
	if err := engine.ProcessStopOrder(stopOrder); err != nil {
		d.balanceManager.CompleteOrder(string(stopOrder.Order.OrderID))
		return interfaces.NewErrorResponse(err)
	}

	// Track stop order in both routing and cache
	d.mu.Lock()
	d.symbolRouting[string(stopOrder.Order.OrderID)] = stopOrder.Order.Symbol
	d.orderCache[string(stopOrder.Order.OrderID)] = stopOrder.Order
	d.mu.Unlock()

	return interfaces.NewStopOrderResponse(stopOrder.TriggerAbove)
}

// GetOrderbookSnapshot returns orderbook snapshot for a symbol
// This is used by legacy dispatcher and external APIs
func (d *Dispatcher) GetOrderbookSnapshot(symbol types.Symbol, depth int) *types.OrderbookData {
	engine := d.getEngine(symbol)
	if engine == nil {
		// Return empty orderbook for non-existent symbol
		return &types.OrderbookData{
			Symbol: symbol,
			Asks:   []types.PriceLevel{},
			Bids:   []types.PriceLevel{},
		}
	}

	return engine.GetOrderbookSnapshot(depth)
}

// GetOrderbookLevel3 returns level 3 orderbook data (all orders)
// This is used for detailed market data feeds
func (d *Dispatcher) GetOrderbookLevel3(symbol types.Symbol) *types.OrderbookData {
	engine := d.getEngine(symbol)
	if engine == nil {
		return &types.OrderbookData{
			Symbol: symbol,
			Asks:   []types.PriceLevel{},
			Bids:   []types.PriceLevel{},
		}
	}

	// Get full orderbook (depth = 0 means all levels)
	return engine.GetOrderbookSnapshot(0)
}

// GetStats returns dispatcher statistics
func (d *Dispatcher) GetStats() map[string]interface{} {
	d.mu.RLock()
	defer d.mu.RUnlock()

	stats := make(map[string]interface{})
	stats["total_engines"] = len(d.engines)
	stats["total_orders"] = metrics.DispatcherTotalOrders.Snapshot().Count()
	stats["total_trades"] = metrics.DispatcherTotalTrades.Snapshot().Count()
	stats["total_volume"] = metrics.DispatcherTotalVolumeGauge.Snapshot().Value()

	// Get per-engine statistics
	engineStats := make(map[string]interface{})
	for symbol, eng := range d.engines {
		engineStats[string(symbol)] = eng.GetStats()
	}
	stats["engines"] = engineStats

	return stats
}

// Shutdown gracefully shuts down the dispatcher
func (d *Dispatcher) Shutdown() error {
	d.mu.Lock()
	defer d.mu.Unlock()

	// Shutdown all engines
	for symbol, eng := range d.engines {
		if err := eng.Shutdown(); err != nil {
			log.Error("Failed to shutdown engine",
				"symbol", symbol,
				"error", err)
		}
	}

	// Clear engines
	d.engines = make(map[types.Symbol]*engine.SymbolEngine)

	log.Debug("Dispatcher shutdown complete",
		"total_orders", metrics.DispatcherTotalOrders.Snapshot().Count(),
		"total_trades", metrics.DispatcherTotalTrades.Snapshot().Count(),
		"total_volume", metrics.DispatcherTotalVolumeGauge.Snapshot().Value())

	return nil
}

func (d *Dispatcher) WriteSnapshot(blockNum uint64) {
	// Handle persistence
	if d.persistence != nil {
		if err := d.persistence.WriteSnapshot(blockNum, d); err != nil {
			log.Error("Failed to write snapshot", "block", blockNum, "error", err)
		}
	}
}

// OnBlockEnd is called at the end of each block for snapshot checks
func (d *Dispatcher) OnBlockEnd(blockNum uint64) {
	// Generate snapshots for all engines (for API performance)
	d.mu.RLock()
	engines := make([]*engine.SymbolEngine, 0, len(d.engines))
	for _, eng := range d.engines {
		engines = append(engines, eng)
	}
	d.mu.RUnlock()

	// Generate snapshots in parallel for better performance
	var wg sync.WaitGroup
	for _, eng := range engines {
		wg.Add(1)
		go func(e *engine.SymbolEngine) {
			defer wg.Done()
			e.MakeSnapshot(blockNum)
		}(eng)
	}
	wg.Wait()

	// TODO-Orderbook: temporary disabled persistence
	//// Handle persistence
	//if d.persistence != nil {
	//	if err := d.persistence.OnBlockEnd(blockNum, d); err != nil {
	//		log.Error("Failed to handle block end", "block", blockNum, "error", err)
	//	}
	//}
}

// ProcessRequestSync processes a request synchronously (for recovery)
func (d *Dispatcher) ProcessRequestSync(req interfaces.Request) interfaces.Response {
	return d.processRequest(req)
}

// GetEngines returns all engines as interface{}
func (d *Dispatcher) GetEngines() interface{} {
	d.mu.RLock()
	defer d.mu.RUnlock()

	// Return a copy to avoid concurrent modification
	engines := make(map[types.Symbol]*engine.SymbolEngine)
	for k, v := range d.engines {
		engines[k] = v
	}
	return engines
}

// GetSnapshotData returns the complete dispatcher state for persistence
func (d *Dispatcher) GetSnapshotData(blockNumber uint64) *types.DispatcherSnapshotData {
	d.mu.RLock()

	// Create a copy of engines map to work with
	enginesCopy := make(map[types.Symbol]*engine.SymbolEngine)
	for k, v := range d.engines {
		enginesCopy[k] = v
	}

	// Make copies of routing and cache data while holding lock
	symbolRouting := make(map[string]types.Symbol)
	for k, v := range d.symbolRouting {
		symbolRouting[k] = v
	}

	orderCache := make(map[string]*types.Order)
	for k, v := range d.orderCache {
		orderCache[k] = v
	}
	d.mu.RUnlock()

	// Capture engine snapshots in parallel (after releasing lock)
	engines := make(map[types.Symbol]*types.EngineSnapshotData)
	var engineMu sync.Mutex
	var wg sync.WaitGroup

	for symbol, eng := range enginesCopy {
		wg.Add(1)
		go func(sym types.Symbol, e *engine.SymbolEngine) {
			defer wg.Done()
			snapshot := e.GetSnapshotData()
			engineMu.Lock()
			engines[sym] = snapshot
			engineMu.Unlock()
		}(symbol, eng)
	}

	// Capture balance manager state in parallel
	var locks map[string]*types.LockInfo
	var lockAlias map[string]string
	wg.Add(1)
	go func() {
		defer wg.Done()
		locks, lockAlias = d.balanceManager.GetSnapshotData()
	}()

	// Wait for all parallel operations to complete
	wg.Wait()

	return &types.DispatcherSnapshotData{
		Locks:         locks,
		LockAlias:     lockAlias,
		SymbolRouting: symbolRouting,
		OrderCache:    orderCache,
		Engines:       engines,
		BlockNumber:   blockNumber,
	}
}

// RestoreFromSnapshot restores the dispatcher state from a snapshot
func (d *Dispatcher) RestoreFromSnapshot(snapshot *types.DispatcherSnapshotData) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	if snapshot == nil {
		return fmt.Errorf("snapshot cannot be nil")
	}

	// Restore balance manager state
	if err := d.balanceManager.RestoreFromSnapshot(snapshot.Locks, snapshot.LockAlias); err != nil {
		return fmt.Errorf("failed to restore balance manager: %w", err)
	}

	// Restore routing and cache
	d.symbolRouting = make(map[string]types.Symbol)
	for k, v := range snapshot.SymbolRouting {
		d.symbolRouting[k] = v
	}

	d.orderCache = make(map[string]*types.Order)
	for k, v := range snapshot.OrderCache {
		d.orderCache[k] = v
	}

	// Restore engines
	for symbol, engineSnapshot := range snapshot.Engines {
		eng, exists := d.engines[symbol]
		if !exists {
			// Create new engine if it doesn't exist
			eng = engine.NewSymbolEngine(symbol, d.balanceManager)
			d.engines[symbol] = eng
		}

		if err := eng.RestoreFromSnapshot(engineSnapshot); err != nil {
			return fmt.Errorf("failed to restore engine %s: %w", symbol, err)
		}
	}

	log.Debug("Dispatcher restored from snapshot",
		"engines", len(snapshot.Engines),
		"locks", len(snapshot.Locks),
		"routing", len(snapshot.SymbolRouting),
		"cache", len(snapshot.OrderCache),
		"block", snapshot.BlockNumber)

	return nil
}

// SetCurrentBlock sets the current block context for persistence
func (d *Dispatcher) SetCurrentBlock(blockNum uint64) {
	// Set block context for all engines
	d.mu.Lock()
	for _, eng := range d.engines {
		eng.SetBlockContext(blockNum)
	}
	d.mu.Unlock()

	// Set block context for persistence manager
	if d.persistence != nil {
		d.persistence.SetBlockContext(blockNum) // txIndex starts at 0
	}
}
