package engine

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/book"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/conditional"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/matching"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/metrics"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// SymbolEngine orchestrates order processing for a trading pair
type SymbolEngine struct {
	symbol types.Symbol

	// Core components
	marketRules        *types.MarketRules // Market rules for validation and adjustments
	orderBook          *book.OrderBook
	matcher            interfaces.OrderMatcher
	conditionalManager *conditional.Manager // Using Manager with 4-module pattern

	// TEMPORARY FIX: Balance manager for TPSL lock inheritance
	// TODO-Orderbook: Refactor to proper architecture after settlement timing is fixed
	balanceManager interface {
		Lock(orderID string, user common.Address, token string, amount *uint256.Int) error
		Unlock(orderID string) error
		GetLock(orderID string) (*types.LockInfo, bool)
		RegisterTPSLAlias(originalOrderID types.OrderID)
		UpdateLockForTriggeredMarketOrder(order *types.Order) error
	}

	// Triggered order queue (BFS processing)
	triggeredQueue []*types.Order

	// Block context
	blockNumber uint64

	// Synchronization
	mu sync.Mutex
}

// NewSymbolEngine creates a new symbol engine
// TEMPORARY FIX: Now accepts balanceManager for TPSL lock inheritance
// TODO-Orderbook: Refactor to proper architecture after settlement timing is fixed
func NewSymbolEngine(symbol types.Symbol, balanceManager interface {
	Lock(orderID string, user common.Address, token string, amount *uint256.Int) error
	Unlock(orderID string) error
	GetLock(orderID string) (*types.LockInfo, bool)
	RegisterTPSLAlias(originalOrderID types.OrderID)
	UpdateLockForTriggeredMarketOrder(order *types.Order) error
}) *SymbolEngine {
	// Initialize market rules
	marketRules := types.NewMarketRules()

	engine := &SymbolEngine{
		symbol:             symbol,
		marketRules:        marketRules,
		orderBook:          book.NewOrderBook(symbol),
		matcher:            matching.NewPriceTimePriority(symbol, marketRules), // Pass market rules to matcher
		conditionalManager: conditional.NewManager(),                           // 4-module pattern
		balanceManager:     balanceManager,                                     // TEMPORARY: For TPSL lock inheritance
	}

	// Wire up callbacks for conditional manager
	// These callbacks integrate the conditional system with the orderbook

	// Order processor: Adds orders to the engine's processing queue
	engine.conditionalManager.SetOrderProcessor(func(order *types.Order) error {
		// Add to triggered queue for BFS processing
		engine.triggeredQueue = append(engine.triggeredQueue, order)
		return nil
	})

	// Order canceller: Cancels orders from the orderbook
	engine.conditionalManager.SetOrderCanceller(func(orderID types.OrderID) error {
		// Use cancelOrderDirect to avoid circular dependency
		return engine.cancelOrderDirect(orderID, "Conditional/OCO cancellation")
	})

	return engine
}

// SetBlockContext sets the current block context
func (e *SymbolEngine) SetBlockContext(blockNumber uint64) {
	e.mu.Lock()
	defer e.mu.Unlock()

	e.blockNumber = blockNumber
}

// ProcessOrder processes a new order and returns all order results including triggered orders
func (e *SymbolEngine) ProcessOrder(order *types.Order) ([]*OrderResult, error) {
	e.mu.Lock()
	defer e.mu.Unlock()

	// Start timer for matching performance
	startTime := time.Now()
	defer func() {
		metrics.GetSymbolTimer("orderbook/symbol/matching/time", string(e.symbol)).UpdateSince(startTime)
	}()

	log.Trace("Processing order in symbol engine",
		"orderID", order.OrderID,
		"symbol", e.symbol,
		"type", order.OrderType,
		"side", order.Side,
		"price", order.Price,
		"quantity", order.Quantity)

	// Update order metrics
	// Update symbol-specific metrics for order placement
	symbolStr := string(e.symbol)
	metrics.GetSymbolCounter("orderbook/symbol/orders/placed", symbolStr).Inc(1)

	var results []*OrderResult

	// Initialize triggered queue for this order processing
	e.triggeredQueue = make([]*types.Order, 0)

	// Process the main order
	result, err := e.processOrderInternal(order)
	if err != nil {
		log.Error("Failed to process order internally",
			"orderID", order.OrderID,
			"error", err)
		return nil, err
	}
	results = append(results, result)

	log.Trace("Main order processed",
		"orderID", order.OrderID,
		"status", result.Status,
		"trades", len(result.Trades),
		"filledQty", result.FilledQuantity)

	// Process triggered orders in BFS order (like legacy processOrder)
	if len(e.triggeredQueue) > 0 {
		log.Debug("Processing triggered orders",
			"count", len(e.triggeredQueue),
			"originalOrder", order.OrderID)
	}

	// Collect failed orders from triggered orders
	var triggeredFailedOrders types.FailedOrders

	for len(e.triggeredQueue) > 0 {
		// FIFO processing for order guarantee
		triggered := e.triggeredQueue[0]
		e.triggeredQueue = e.triggeredQueue[1:]

		log.Trace("Processing triggered order",
			"orderID", triggered.OrderID,
			"type", triggered.OrderType,
			"side", triggered.Side)

		// For triggered stop/sl market orders, update the lock based on current market conditions
		// When stop/sl orders trigger, they maintain their OrderType (STOP_MARKET or SL_MARKET)
		// We update the lock to include all available balance for market execution
		if (triggered.OrderType == types.STOP_MARKET || triggered.OrderType == types.SL_MARKET) &&
			e.balanceManager != nil {
			log.Debug("Updating lock for triggered stop market order",
				"orderID", triggered.OrderID,
				"orderType", triggered.OrderType,
				"existingLock", triggered.LockedAmount)

			// Update the lock to include all available balance
			if err := e.balanceManager.UpdateLockForTriggeredMarketOrder(triggered); err != nil {
				log.Warn("Failed to update lock for triggered market order",
					"orderID", triggered.OrderID,
					"error", err)

				triggered.Status = types.REJECTED
				failReason := fmt.Sprintf("Updating lock failed for market order: %v", err)

				// Handle OCO cancellation for failed TP/SL orders
				additionalFailedOrders := e.handleFailedOrders(triggered.OrderID, failReason)
				triggeredFailedOrders = append(triggeredFailedOrders, additionalFailedOrders...)

				// Continue processing even if lock update fails
				continue
			}
		}

		// Process the triggered order
		triggerResult, err := e.processOrderInternal(triggered)
		if err != nil {
			triggered.Status = types.REJECTED
			failReason := fmt.Sprintf("Triggered order failed: %v", err)

			// Handle OCO cancellation for failed TP/SL orders
			additionalFailedOrders := e.handleFailedOrders(triggered.OrderID, failReason)
			triggeredFailedOrders = append(triggeredFailedOrders, additionalFailedOrders...)

			// Log error but continue processing other triggered orders
			log.Warn("Failed to process triggered order",
				"orderID", triggered.OrderID,
				"error", err,
				"ocoCancelled", len(additionalFailedOrders)-1)
			continue
		}

		// Add triggered order result
		triggerResult.Order = triggered // Include the order object for post-processing

		// Merge any failed orders from the triggered order processing
		if len(triggerResult.FailedOrders) > 0 {
			triggeredFailedOrders = append(triggeredFailedOrders, triggerResult.FailedOrders...)
		}

		results = append(results, triggerResult)

		log.Trace("Triggered order processed",
			"orderID", triggered.OrderID,
			"status", triggerResult.Status,
			"trades", len(triggerResult.Trades))
	}

	// Add all failed triggered orders to the first result
	if len(results) > 0 && len(triggeredFailedOrders) > 0 {
		// Merge failed orders from triggered processing into the main result
		results[0].FailedOrders = append(results[0].FailedOrders, triggeredFailedOrders...)
		log.Debug("Failed triggered orders added to results",
			"count", len(triggeredFailedOrders),
			"totalFailed", len(results[0].FailedOrders))
	}

	return results, nil
}

// handleFailedOrders handles OCO cancellation for failed triggered orders
// Returns all failed orders including the original and any cancelled OCO pairs
func (e *SymbolEngine) handleFailedOrders(failedOrderID types.OrderID, reason string) types.FailedOrders {
	var failedOrders types.FailedOrders

	// Add the original failed order
	failedOrders = append(failedOrders, types.FailedOrder{
		OrderID: failedOrderID,
		Reason:  reason,
	})

	// Get OCO related orders
	relatedOrders := e.conditionalManager.GetRelatedOrders(failedOrderID)

	// No related orders (Stop order or standalone order)
	if len(relatedOrders) == 0 {
		log.Debug("No OCO pair for failed order",
			"orderID", failedOrderID)
		return failedOrders
	}

	// Has OCO pair (TP or SL order)
	for _, relatedID := range relatedOrders {
		// Cancel the related order (fix: use relatedID, not failedOrderID)
		cancelledID, cancelled := e.conditionalManager.CancelSingleOrder(relatedID)
		if cancelled {
			log.Debug("OCO order cancelled due to failed pair",
				"failedOrder", failedOrderID,
				"cancelledOrder", cancelledID)

			failedOrders = append(failedOrders, types.FailedOrder{
				OrderID: cancelledID,
				Reason:  fmt.Sprintf("OCO cancelled: paired order %s failed - %s", failedOrderID, reason),
			})
		} else {
			log.Warn("Failed to cancel OCO pair order",
				"failedOrder", failedOrderID,
				"targetOrder", relatedID)
		}
	}

	log.Debug("Failed order OCO handling completed",
		"originalFailed", failedOrderID,
		"totalFailed", len(failedOrders),
		"ocoCancelled", len(failedOrders)-1)

	return failedOrders
}

// ProcessStopOrder processes a stop order (conditional order)
func (e *SymbolEngine) ProcessStopOrder(stopOrder *types.StopOrder) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	// Validate stop order
	if stopOrder == nil || stopOrder.Order == nil {
		return fmt.Errorf("invalid stop order")
	}

	if stopOrder.Order.Symbol != e.symbol {
		return fmt.Errorf("symbol mismatch: expected %s, got %s", e.symbol, stopOrder.Order.Symbol)
	}

	// set trigger above after comparing current price with stop price
	stopOrder.SetTriggerAbove(e.orderBook.GetCurrentPrice())

	// Add to conditional manager
	err := e.conditionalManager.AddStopOrder(stopOrder)
	if err != nil {
		return fmt.Errorf("failed to add stop order: %w", err)
	}

	log.Debug("Stop order added",
		"orderID", stopOrder.Order.OrderID,
		"stopPrice", stopOrder.StopPrice,
		"triggerAbove", stopOrder.TriggerAbove)

	return nil
}

// processOrderInternal processes a single order through the pipeline (no recursion)
func (e *SymbolEngine) processOrderInternal(order *types.Order) (*OrderResult, error) {
	// ============================================================
	// STAGE 1: Validation
	// Description: Validate order and initialize status
	// Future: Will be extracted to ValidationStage
	// ============================================================
	if order == nil {
		return nil, fmt.Errorf("order cannot be nil")
	}

	// Validate order
	if err := e.validateOrder(order); err != nil {
		return nil, err
	}

	// Set order status
	order.Status = types.PENDING

	// ============================================================
	// STAGE 2: Matching
	// Description: Execute price-time priority matching algorithm using OrderBook
	// Future: Will be extracted to MatchingStage
	// ============================================================
	if log.Root().Enabled(context.Background(), log.LevelDebug) {
		bids, asks := e.orderBook.GetDepth(5)
		log.Trace("Starting order matching",
			"orderID", order.OrderID,
			"bidLevels", len(bids),
			"askLevels", len(asks))
	}

	var failedOrders types.FailedOrders // Track all failed orders
	matchResult, err := e.matcher.MatchOrder(order, e.orderBook)
	if err != nil {
		log.Error("Order matching failed",
			"orderID", order.OrderID,
			"error", err)
		return nil, fmt.Errorf("matching failed: %w", err)
	}

	if len(matchResult.Trades) > 0 {
		var remainingQty *types.Quantity
		if matchResult.RemainingOrder != nil {
			remainingQty = matchResult.RemainingOrder.Quantity
		}
		log.Debug("Order matched",
			"orderID", order.OrderID,
			"trades", len(matchResult.Trades),
			"filledQty", matchResult.FilledQuantity,
			"remainingQty", remainingQty)

		// Update symbol-specific metrics for trades
		symbolStr := string(e.symbol)
		metrics.GetSymbolCounter("orderbook/symbol/trades/executed", symbolStr).Inc(int64(len(matchResult.Trades)))
	}

	if len(matchResult.FailedOrders) > 0 {
		failedOrders = append(failedOrders, matchResult.FailedOrders...)
	}

	// ============================================================
	// STAGE 3: State Synchronization
	// Description: Update orderbook state with match results
	// Future: Will be extracted to StateSynchronizationStage
	// ============================================================
	// Update current price if trades occurred
	if len(matchResult.Trades) > 0 {
		lastTrade := matchResult.Trades[len(matchResult.Trades)-1]
		e.orderBook.UpdatePrice(lastTrade.Price, int64(lastTrade.Timestamp))
		log.Trace("Price updated from trades",
			"symbol", e.symbol,
			"newPrice", lastTrade.Price,
			"timestamp", lastTrade.Timestamp)
	}

	// ============================================================
	// STAGE 4: Conditional Order Processing
	// Description: 3 clear steps for conditional order handling
	// NOTE: Errors here don't fail the main order (following CEX standards)
	//
	// TPSL Architecture:
	// - TPSL creation happens HERE in stage 3 via createTPSLForFilledOrders
	// - Lock calculation happens LATER via calculateTPSLLockRequirements
	// - Lock transformation is handled by the dispatcher after trade settlement
	// ============================================================
	var (
		localErrors  []error
		tpslErrors   []error
		triggeredIds []types.OrderID
		cancelledIds []types.OrderID
	)

	if len(matchResult.Trades) > 0 {
		// Step 1: Handle OCO for TP orders that got filled
		// (Must be done BEFORE creating new TPSL to avoid conflicts)
		e.processTPOrderFills(matchResult)

		// Step 2: Create TPSL for newly filled orders with TPSL context
		// This is where TPSL orders are actually created via conditionalManager
		var tpslFailedOrders types.FailedOrders
		localErrors, tpslFailedOrders = e.createTPSLForFilledOrders(matchResult)
		if len(localErrors) > 0 {
			tpslErrors = append(tpslErrors, localErrors...)
			failedOrders = append(failedOrders, tpslFailedOrders...)
		}

		// Step 3: Check price triggers for conditional orders (Stop, TPSL SL)
		lastPrice := e.orderBook.GetCurrentPrice()
		triggeredIds, localErrors = e.checkConditionalTriggers(lastPrice)
		if len(localErrors) > 0 {
			tpslErrors = append(tpslErrors, localErrors...)
		}
	}

	// ============================================================
	// STAGE 7: Finalization
	// Description: Update tx index, determine final status, and prepare response
	// Future: Will be extracted to FinalizationStage
	// ============================================================

	// Determine final status
	finalStatus := e.determineFinalStatus(matchResult)

	// Initialize result
	result := &OrderResult{
		Order:             order,
		OrderID:           order.OrderID,
		Symbol:            e.symbol,
		Status:            finalStatus,
		FilledQuantity:    matchResult.FilledQuantity,
		Trades:            matchResult.Trades,
		TPSLErrors:        tpslErrors,
		TriggeredOrderIds: triggeredIds,
		CancelledOrderIds: cancelledIds,
		FailedOrders:      failedOrders, // Include failed orders (TPSL and triggered orders)
	}

	return result, nil
}

// CancelOrder cancels an order
func (e *SymbolEngine) CancelOrder(orderID types.OrderID) (*CancelResult, error) {
	e.mu.Lock()
	defer e.mu.Unlock()

	log.Trace("Cancelling order", "orderID", orderID, "reason", "User requested")

	result, err := e.cancelOrderInternal(orderID, "User requested")
	if err != nil {
		log.Error("Failed to cancel order", "orderID", orderID, "error", err)
		return nil, err
	}

	if result.Cancelled {
		log.Debug("Order cancelled",
			"orderID", orderID,
			"cancelledCount", len(result.CancelledOrderIds))
		// Update symbol-specific metrics for cancellation
		symbolStr := string(e.symbol)
		metrics.GetSymbolCounter("orderbook/symbol/orders/cancelled", symbolStr).Inc(int64(len(result.CancelledOrderIds)))
	}

	return result, nil
}

// cancelOrderDirect removes an order directly from orderbook or triggeredQueue without OCO checks
// This is used by conditional manager to avoid circular dependencies
func (e *SymbolEngine) cancelOrderDirect(orderID types.OrderID, reason string) error {
	// Try to remove from orderbook first
	if _, exists := e.orderBook.GetOrder(orderID); exists {
		if err := e.orderBook.RemoveOrder(orderID); err != nil {
			return err
		}
		return nil
	}

	// If not in orderbook, check triggeredQueue
	// This handles the case where TP order is queued but not yet in orderbook
	// TODO-Orderbook: This linear search is O(n). Consider using a more efficient data structure
	// like a linked list + map hybrid for O(1) removal if performance becomes an issue
	for i, order := range e.triggeredQueue {
		if order != nil && order.OrderID == orderID {
			// Remove from queue
			e.triggeredQueue = append(e.triggeredQueue[:i], e.triggeredQueue[i+1:]...)
			log.Trace("Order removed from triggered queue",
				"orderID", orderID,
				"reason", reason)
			return nil
		}
	}

	return fmt.Errorf("order %s not found in orderbook or triggered queue", orderID)
}

// cancelOrderInternal cancels an order without acquiring mutex (must be called with mutex held)
func (e *SymbolEngine) cancelOrderInternal(orderID types.OrderID, reason string) (*CancelResult, error) {
	var order *types.Order
	var cancelledIds []types.OrderID

	// Try to remove from orderbook first
	if bookOrder, exists := e.orderBook.GetOrder(orderID); exists && !bookOrder.IsPendingTP() {
		if err := e.orderBook.RemoveOrder(orderID); err != nil {
			return nil, err
		}
		order = bookOrder
		cancelledIds = append(cancelledIds, orderID)
		if order.HasTPSL() {
			cancelledIds = append(cancelledIds, types.GenerateTPOrderID(orderID))
			cancelledIds = append(cancelledIds, types.GenerateSLOrderID(orderID))
		}

		return &CancelResult{
			Cancelled:         true,
			CancelledOrderIds: cancelledIds,
		}, nil
	}

	// Cancel any related conditional orders (TPSL, Stop)
	cancelled, cancelledIds := e.conditionalManager.CancelOrder(orderID)

	// Check if we found anything
	if !cancelled {
		return nil, fmt.Errorf("order %s not found", orderID)
	}

	return &CancelResult{
		Cancelled:         true,
		CancelledOrderIds: cancelledIds,
	}, nil
}

// CancelAllOrders cancels all orders for a user
func (e *SymbolEngine) CancelAllOrders(userID types.UserID) (*CancelAllResult, error) {
	e.mu.Lock()
	defer e.mu.Unlock()

	cancelledOrderIDs := make([]types.OrderID, 0)

	// Step 1: Get user orders from orderbook
	userOrders := e.orderBook.GetUserOrders(userID)

	// Step 2: Cancel each regular order (including TP orders)
	// This will also cancel related SL orders via OCO
	for _, order := range userOrders {
		result, err := e.cancelOrderInternal(order.OrderID, "Cancel all")
		if err != nil {
			// Log error but continue cancelling other orders
			log.Error("Failed to cancel order during cancel all",
				"orderID", order.OrderID,
				"error", err)
			continue
		}
		cancelledOrderIDs = append(cancelledOrderIDs, result.CancelledOrderIds...)
	}

	// Step 3: Get remaining conditional orders AFTER orderbook cancellation
	// At this point, SL orders have been cancelled via OCO, so this returns only Stop orders
	conditionalOrderIDs := e.conditionalManager.GetUserOrders(userID)

	// Step 4: Cancel remaining conditional orders (standalone Stop orders)
	for _, orderID := range conditionalOrderIDs {
		// Try to cancel - if it was already cancelled via OCO, cancelOrderInternal will handle it
		result, err := e.cancelOrderInternal(orderID, "Cancel all")
		if err != nil {
			// Log error but continue cancelling other orders
			log.Error("Failed to cancel conditional order during cancel all",
				"orderID", orderID,
				"error", err)
			continue
		}
		cancelledOrderIDs = append(cancelledOrderIDs, result.CancelledOrderIds...)
	}

	return &CancelAllResult{
		CancelledOrderIds: cancelledOrderIDs,
	}, nil
}

// CreateModifiedOrder creates a new order with modifications applied
// This is a pure function that doesn't modify any state
func CreateModifiedOrder(existingOrder *types.Order, newID types.OrderID, newPrice *types.Price, newQuantity *types.Quantity) (*types.Order, error) {
	// Basic validation - no TPSL orders
	if existingOrder.HasTPSL() {
		return nil, fmt.Errorf("cannot modify order with TPSL")
	}

	// Calculate filled quantity
	filledQty := new(types.Quantity).Sub(existingOrder.OrigQty, existingOrder.Quantity)

	// If new quantity is provided, validate it's greater than filled quantity
	if newQuantity != nil {
		if newQuantity.Cmp(filledQty) <= 0 {
			return nil, fmt.Errorf("new quantity must be greater than already filled quantity")
		}
	}

	// Create a new order with modified parameters
	modifiedOrder := types.NewOrder(
		newID,
		existingOrder.UserID,
		existingOrder.Symbol,
		existingOrder.Side,
		existingOrder.OrderMode,
		existingOrder.OrderType,
		existingOrder.Price,    // to be updated below
		existingOrder.Quantity, // to be updated below
		nil)

	// Apply new price if provided, otherwise use existing
	if newPrice != nil {
		modifiedOrder.Price = newPrice
	} else {
		modifiedOrder.Price = existingOrder.Price
	}

	// Apply new quantity if provided
	if newQuantity != nil {
		// Set OrigQty to the new total quantity
		modifiedOrder.OrigQty = newQuantity
		// Set Quantity to new quantity minus already filled amount
		modifiedOrder.Quantity = new(types.Quantity).Sub(newQuantity, filledQty)
	} else {
		// Keep the same total quantity, adjust for filled amount
		modifiedOrder.OrigQty = existingOrder.OrigQty
		modifiedOrder.Quantity = existingOrder.Quantity
	}

	return modifiedOrder, nil
}

// ModifyOrder modifies an existing order by canceling and reprocessing it
// Only basic orders without TPSL can be modified
func (e *SymbolEngine) ModifyOrder(orderID, newID types.OrderID, newPrice *types.Price, newQuantity *types.Quantity) (*ModifyResult, error) {
	e.mu.Lock()
	defer e.mu.Unlock()

	// Get the existing order
	existingOrder, exists := e.orderBook.GetOrder(orderID)
	if !exists {
		return nil, fmt.Errorf("order %s not found", orderID)
	}

	// Create modified order using the helper function
	modifiedOrder, err := CreateModifiedOrder(existingOrder, newID, newPrice, newQuantity)
	if err != nil {
		return nil, err
	}

	// Cancel the existing order internally
	cancelResult, err := e.cancelOrderInternal(orderID, "Modification")
	if err != nil {
		return nil, fmt.Errorf("failed to cancel order for modification: %w", err)
	}

	// Process the modified order
	processResult, err := e.processOrderInternal(modifiedOrder)
	if err != nil {
		// Order modification failed - the original order is already cancelled
		// Log the failure but don't try to restore
		return nil, fmt.Errorf("failed to process modified order: %w", err)
	}

	// Update modification metrics
	// Update symbol-specific metrics for modification
	metrics.GetSymbolCounter("orderbook/symbol/orders/modified", string(e.symbol)).Inc(1)

	return &ModifyResult{
		NewOrder:          modifiedOrder,
		Trades:            processResult.Trades,
		TriggeredOrderIds: processResult.TriggeredOrderIds,
		CancelledOrderIds: append(processResult.CancelledOrderIds, cancelResult.CancelledOrderIds...),
	}, nil
}

// GetOrderBook returns the current orderbook state
func (e *SymbolEngine) GetOrderBook() interfaces.OrderBook {
	return e.orderBook
}

// GetDepth returns the orderbook depth
func (e *SymbolEngine) GetDepth(limit int) ([]interfaces.PriceLevel, []interfaces.PriceLevel) {
	return e.orderBook.GetDepth(limit)
}

// GetSnapshot returns a snapshot of the engine state
func (e *SymbolEngine) GetSnapshot() *OrderBookSnapshot {
	e.mu.Lock()
	defer e.mu.Unlock()

	buyOrders := e.orderBook.GetBuyOrders()
	sellOrders := e.orderBook.GetSellOrders()

	return &OrderBookSnapshot{
		Symbol:       e.symbol,
		Timestamp:    types.TimeNow(),
		CurrentPrice: e.orderBook.GetCurrentPrice(),
		BuyOrders:    buyOrders,
		SellOrders:   sellOrders,
	}
}

// HasTPSL checks if an order has active TPSL
func (e *SymbolEngine) HasTPSL(orderID types.OrderID) bool {
	e.mu.Lock()
	defer e.mu.Unlock()

	return e.conditionalManager.HasTPSL(orderID)
}

// Reset resets the engine state
func (e *SymbolEngine) Reset() {
	e.mu.Lock()
	defer e.mu.Unlock()

	e.orderBook.Clear()
	e.conditionalManager.Clear()
}

// processTPOrderFills checks if any filled orders are TP orders and handles OCO
// This is called BEFORE creating new TPSL to avoid conflicts
// Returns cancelled order IDs from OCO processing
func (e *SymbolEngine) processTPOrderFills(matchResult *interfaces.MatchResult) []types.OrderID {
	var allCancelledOrders []types.OrderID

	// Check each trade to see if a TP order got filled
	for _, trade := range matchResult.Trades {
		// Process buy order if it participated in the trade
		if trade.Quantity != nil && trade.Quantity.Sign() > 0 {
			cancelledOrders := e.conditionalManager.HandleOrderFill(trade.BuyOrderID)
			allCancelledOrders = append(allCancelledOrders, cancelledOrders...)
		}

		// Process sell order if it participated in the trade
		if trade.Quantity != nil && trade.Quantity.Sign() > 0 {
			cancelledOrders := e.conditionalManager.HandleOrderFill(trade.SellOrderID)
			allCancelledOrders = append(allCancelledOrders, cancelledOrders...)
		}
	}

	return allCancelledOrders
}

// createTPSLForFilledOrders creates TPSL for orders that were fully filled and have TPSL context
// Returns slice of errors for failed TPSL creations (doesn't stop processing)
// Also returns detailed FailedOrders for tracking
func (e *SymbolEngine) createTPSLForFilledOrders(matchResult *interfaces.MatchResult) ([]error, types.FailedOrders) {
	var errors []error
	var failedOrders types.FailedOrders

	// Process filled orders with TPSL from the match result
	// These were saved before being removed from the orderbook
	for _, filledOrder := range matchResult.FilledOrdersWithTPSL {
		if err := e.createTPSLOrders(filledOrder); err != nil {
			errors = append(errors,
				fmt.Errorf("TPSL creation failed for order %s: %w", filledOrder.OrderID, err))

			// Track specific failed TP/SL orders
			if filledOrder.TPSL != nil {
				if filledOrder.TPSL.TPLimitPrice != nil {
					failedOrders = append(failedOrders, types.FailedOrder{
						OrderID: types.GenerateTPOrderID(filledOrder.OrderID),
						Reason:  fmt.Sprintf("TP order creation failed: %v", err),
					})
				}
				if filledOrder.TPSL.SLTriggerPrice != nil {
					failedOrders = append(failedOrders, types.FailedOrder{
						OrderID: types.GenerateSLOrderID(filledOrder.OrderID),
						Reason:  fmt.Sprintf("SL order creation failed: %v", err),
					})
				}
			}
		}
	}

	return errors, failedOrders
}

// createTPSLOrders creates TP and SL orders for a filled order with TPSL
// Returns error if creation fails (following CEX pattern: main order succeeds, TPSL is best-effort)
func (e *SymbolEngine) createTPSLOrders(order *types.Order) error {
	if order == nil || !order.HasTPSL() {
		return nil
	}

	// Check if TPSL already exists for this order
	if e.conditionalManager.HasTPSL(order.OrderID) {
		// TPSL already created for this order - not an error
		return nil
	}

	// TEMPORARY FIX: Create TPSL lock before TPSL creation
	// This moves lock inheritance from settlement to TPSL creation time
	// TODO-Orderbook: Refactor to proper architecture after settlement timing is fixed
	if e.balanceManager != nil {
		if err := e.createTPSLLock(order); err != nil {
			// Lock creation failed, fail TPSL creation
			return fmt.Errorf("failed to create TPSL lock: %w", err)
		}
	}

	// Create TPSL through ManagerV2's unified interface
	// Price is already uint256.Int (type alias)
	err := e.conditionalManager.CreateTPSLForFilledOrder(order)
	if err != nil {
		e.balanceManager.Unlock(string(order.OrderID))
		return fmt.Errorf("failed to create TPSL: %w", err)
	}

	log.Debug("TPSL created successfully",
		"originalOrderID", order.OrderID,
		"tpOrderID", types.GenerateTPOrderID(order.OrderID),
		"slOrderID", types.GenerateSLOrderID(order.OrderID))

	return nil
}

// createTPSLLock creates TPSL lock before TPSL creation (temporary fix)
// TEMPORARY FIX: This is moved from settlement to TPSL creation time
// TODO-Orderbook: Refactor to proper architecture after settlement timing is fixed
func (e *SymbolEngine) createTPSLLock(order *types.Order) error {
	if order == nil || order.TPSL == nil {
		return nil
	}

	// Determine the token to lock based on order side
	// Buy order: lock base tokens (what they received)
	// Sell order: lock quote tokens (what they received)
	var token string
	var amount *uint256.Int
	baseToken, quoteToken := types.GetTokens(order.Symbol)

	// Calculate the filled amount (OrigQty - Quantity)
	filledQty := new(uint256.Int).Sub(order.OrigQty, order.Quantity)

	if order.Side == types.BUY {
		// Buy order: should have received base tokens, lock them for TPSL
		token = baseToken
		amount = filledQty // The base tokens received
	} else {
		// Sell order: should have received quote tokens, lock them for TPSL
		token = quoteToken

		// For SELL orders with TPSL, we need to lock enough quote tokens
		// to buy back at the stop loss price (which is higher than sell price)
		// Use the higher of: original price or stop loss limit price
		priceToUse := order.Price
		if priceToUse == nil {
			return errors.New("price is nil")
		}

		// Check if SL limit price is higher (worst case for SELL order)
		if order.TPSL != nil {
			if order.TPSL.SLLimitPrice != nil {
				if order.TPSL.SLLimitPrice.Cmp(priceToUse) > 0 {
					// Use SL limit price as it requires more quote tokens
					priceToUse = order.TPSL.SLLimitPrice
					log.Trace("Using SL limit price for TPSL lock calculation",
						"orderID", order.OrderID,
						"originalPrice", order.Price.String(),
						"slLimitPrice", order.TPSL.SLLimitPrice.String())
				}
			} else {
				if order.TPSL.SLTriggerPrice != nil {
					priceToUse = order.TPSL.SLTriggerPrice
					log.Trace("Using SL trigger price for TPSL lock calculation",
						"orderID", order.OrderID,
						"originalPrice", order.Price.String(),
						"slTriggerPrice", order.TPSL.SLTriggerPrice.String())
				}
			}
		}

		amount = common.Uint256MulScaledDecimal(priceToUse, filledQty)
	}

	if amount == nil || amount.Sign() <= 0 {
		return fmt.Errorf("cannot create TPSL lock: invalid amount for order %s, filledQty=%s",
			order.OrderID, filledQty)
	}

	// Convert UserID to address
	userAddr := common.HexToAddress(string(order.UserID))

	// Create the TPSL lock
	tpslLockID := fmt.Sprintf("%s_TPSL", order.OrderID)

	// Check if lock already exists
	if _, exists := e.balanceManager.GetLock(tpslLockID); exists {
		log.Warn("TPSL lock already exists",
			"orderID", order.OrderID)
		// Already created, this is OK (idempotent operation)
		return nil
	}

	if err := e.balanceManager.Lock(tpslLockID, userAddr, token, amount); err != nil {
		log.Error("Failed to create early TPSL lock",
			"orderID", order.OrderID,
			"token", token,
			"amount", amount.String(),
			"error", err)
		// Return error to fail TPSL creation
		return fmt.Errorf("failed to lock %s %s for TPSL: %w", amount.String(), token, err)
	}

	log.Debug("Early TPSL lock created",
		"orderID", order.OrderID,
		"token", token,
		"amount", amount.String())

	// Register TP/SL order IDs as aliases for this TPSL lock
	e.balanceManager.RegisterTPSLAlias(order.OrderID)

	return nil
}

// checkConditionalTriggers checks price triggers for Stop orders and TPSL SL orders
// Returns errors from trigger operations (best-effort, doesn't stop processing)
func (e *SymbolEngine) checkConditionalTriggers(lastPrice *types.Price) ([]types.OrderID, []error) {
	var triggeredIds []types.OrderID
	var errors []error

	if lastPrice == nil {
		return triggeredIds, errors
	}

	// Check triggers through ManagerV2
	// Price is already uint256.Int (type alias)
	triggeredOrders, cancelledOrders := e.conditionalManager.CheckTriggers(lastPrice)

	// Add triggered orders to the processing queue
	for _, order := range triggeredOrders {
		log.Debug("Conditional order triggered",
			"orderID", order.OrderID,
			"side", order.Side,
			"price", order.Price)

		// Add to triggered queue for BFS processing
		e.triggeredQueue = append(e.triggeredQueue, order)
		triggeredIds = append(triggeredIds, order.OrderID)
	}

	// Log cancelled orders (OCO)
	for _, orderID := range cancelledOrders {
		log.Debug("Order cancelled via OCO",
			"orderID", orderID,
			"reason", "OCO trigger")
	}

	return triggeredIds, errors
}

// Helper methods

func (e *SymbolEngine) validateOrder(order *types.Order) error {
	// Basic validation
	if order.OrderID == "" {
		return fmt.Errorf("order ID is required")
	}
	if order.UserID == "" {
		return fmt.Errorf("user ID is required")
	}
	if order.Symbol != e.symbol {
		return fmt.Errorf("symbol mismatch: expected %s, got %s", e.symbol, order.Symbol)
	}
	if order.Quantity == nil || order.Quantity.IsZero() {
		return fmt.Errorf("quantity must be positive")
	}

	// Limit orders must have price
	if order.OrderType.IsLimit() && (order.Price == nil || order.Price.IsZero()) {
		return fmt.Errorf("limit order must have price")
	}

	// Market rules validation (skip for market orders as they'll be validated during matching)
	if order.OrderType != types.MARKET {
		if err := e.marketRules.ValidateOrder(order); err != nil {
			return fmt.Errorf("market rules validation failed: %w", err)
		}
	}

	return nil
}

func (e *SymbolEngine) determineFinalStatus(result *interfaces.MatchResult) types.OrderStatus {
	if result.RemainingOrder == nil {
		// Fully filled or cancelled (market order)
		if result.FilledQuantity != nil && result.FilledQuantity.Sign() > 0 {
			return types.FILLED
		}
		return types.REJECTED
	}

	if result.FilledQuantity != nil && result.FilledQuantity.Sign() > 0 {
		return types.PARTIALLY_FILLED
	}

	return types.PENDING
}

// Result types

// OrderResult represents the result of order processing
type OrderResult struct {
	Order             *types.Order // The order that was processed
	OrderID           types.OrderID
	Symbol            types.Symbol
	Status            types.OrderStatus
	FilledQuantity    *types.Quantity
	Trades            []*types.Trade
	TPSLErrors        []error // Non-nil if TPSL creation had errors
	TriggeredOrderIds []types.OrderID
	CancelledOrderIds []types.OrderID
	FailedOrders      types.FailedOrders // Orders that failed during processing
}

// CancelResult represents the result of order cancellation
type CancelResult struct {
	Cancelled         bool
	CancelledOrderIds []types.OrderID
}

// CancelAllResult represents the result of cancelling all orders
type CancelAllResult struct {
	CancelledOrderIds []types.OrderID
}

// ModifyResult represents the result of order modification
type ModifyResult struct {
	NewOrder          *types.Order
	Trades            []*types.Trade
	TriggeredOrderIds []types.OrderID
	CancelledOrderIds []types.OrderID
}

// OrderBookSnapshot represents a point-in-time snapshot
type OrderBookSnapshot struct {
	Symbol       types.Symbol
	Timestamp    int64
	CurrentPrice *types.Price
	BuyOrders    []*types.Order
	SellOrders   []*types.Order
}

// EngineSnapshotData, ConditionalTrigger, and OCOPairSnapshot are now defined in types package

// Additional methods for dispatcher integration

// GetOrder retrieves an order from the orderbook
func (e *SymbolEngine) GetOrder(orderID types.OrderID) *types.Order {
	e.mu.Lock()
	defer e.mu.Unlock()

	order, _ := e.orderBook.GetOrder(orderID)
	return order
}

// GetOrderbookSnapshot returns a snapshot of the orderbook
func (e *SymbolEngine) GetOrderbookSnapshot(depth int) *types.OrderbookData {
	e.mu.Lock()
	defer e.mu.Unlock()

	asks, bids := e.orderBook.GetDepth(depth)

	// Convert to types.PriceLevel
	askLevels := make([]types.PriceLevel, len(asks))
	for i, level := range asks {
		askLevels[i] = types.PriceLevel{
			Price:    level.Price,
			Quantity: level.Quantity,
			Orders:   level.Orders,
		}
	}

	bidLevels := make([]types.PriceLevel, len(bids))
	for i, level := range bids {
		bidLevels[i] = types.PriceLevel{
			Price:    level.Price,
			Quantity: level.Quantity,
			Orders:   level.Orders,
		}
	}

	return &types.OrderbookData{
		Symbol:    e.symbol,
		Timestamp: types.TimeNow(),
		Asks:      askLevels,
		Bids:      bidLevels,
	}
}

// GetStats returns engine statistics
func (e *SymbolEngine) GetStats() map[string]interface{} {
	e.mu.Lock()
	defer e.mu.Unlock()

	stats := make(map[string]interface{})
	stats["symbol"] = e.symbol
	stats["current_price"] = e.orderBook.GetCurrentPrice()
	stats["buy_orders"] = e.orderBook.GetBuyOrderCount()
	stats["sell_orders"] = e.orderBook.GetSellOrderCount()
	stats["triggered_queue_size"] = len(e.triggeredQueue)

	return stats
}

// Shutdown gracefully shuts down the engine
func (e *SymbolEngine) Shutdown() error {
	e.mu.Lock()
	defer e.mu.Unlock()

	// Clear triggered queue
	e.triggeredQueue = nil

	log.Debug("Symbol engine shutdown", "symbol", e.symbol)
	return nil
}

// Level2 Book Methods

// UpdateLevel2 returns the Level2 depth changes since last call
// Returns only changed price levels with absolute quantities
func (e *SymbolEngine) UpdateLevel2() ([][]string, [][]string) {
	e.mu.Lock()
	defer e.mu.Unlock()

	return e.orderBook.GetLevel2Diff()
}

// GetLevel2Snapshot returns the full Level2 orderbook snapshot
func (e *SymbolEngine) GetLevel2Snapshot() *types.Aggregated {
	e.mu.Lock()
	defer e.mu.Unlock()

	snapshot := e.orderBook.GetLevel2Snapshot()
	snapshot.BlockNumber = e.blockNumber
	return snapshot
}

// MakeSnapshot creates a snapshot at the given block number
func (e *SymbolEngine) MakeSnapshot(blockNumber uint64) {
	e.mu.Lock()
	defer e.mu.Unlock()

	// Generate and cache the snapshot in the orderbook
	e.orderBook.GenerateSnapshot(blockNumber)
}

// GetSnapshotFromLevel3 returns a Level2 snapshot from current Level3 orderbook
func (e *SymbolEngine) GetSnapshotFromLevel3() *types.Aggregated {
	return e.GetLevel2Snapshot()
}

// GetAllStopOrders returns all stop orders
func (e *SymbolEngine) GetAllStopOrders() []*types.StopOrder {
	if e.conditionalManager != nil {
		return e.conditionalManager.GetAllStopOrders()
	}
	return nil
}

// Snapshot and Recovery Methods

// GetSnapshotData captures the minimal engine state for persistence
func (e *SymbolEngine) GetSnapshotData() *types.EngineSnapshotData {
	e.mu.Lock()
	defer e.mu.Unlock()

	// 1. Symbol
	snapshot := &types.EngineSnapshotData{
		Symbol: e.symbol,
	}

	// 2. OrderBook data (minimal)
	// Get ALL orders - from this we can rebuild everything
	snapshot.Orders = e.orderBook.GetAllOrders()
	snapshot.CurrentPrice = e.orderBook.GetCurrentPrice()
	snapshot.LastTradeTime = e.orderBook.GetLastTradeTime()

	// 3. Conditional Manager state
	if e.conditionalManager != nil {
		// Get trigger manager state
		triggers, queue := e.conditionalManager.GetTriggerState()
		snapshot.Triggers = triggers
		snapshot.TriggerQueue = queue

		// Get OCO controller state
		snapshot.OCOPairs = e.conditionalManager.GetOCOPairs()
	}

	// 4. Block context
	snapshot.BlockNumber = e.blockNumber

	return snapshot
}

// RestoreFromSnapshot restores engine state from minimal snapshot data
func (e *SymbolEngine) RestoreFromSnapshot(snapshot *types.EngineSnapshotData) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if snapshot == nil {
		return fmt.Errorf("snapshot cannot be nil")
	}

	if snapshot.Symbol != e.symbol {
		return fmt.Errorf("symbol mismatch: expected %s, got %s", e.symbol, snapshot.Symbol)
	}

	// Reset the engine first
	e.reset()

	// 1. Restore block context
	e.blockNumber = snapshot.BlockNumber

	// 2. Restore OrderBook from minimal data
	// Restore ALL orders - this rebuilds queues, levels, user mappings automatically
	for _, order := range snapshot.Orders {
		if err := e.orderBook.AddOrder(order); err != nil {
			log.Error("Failed to restore order", "orderID", order.OrderID, "error", err)
		}
	}

	// Restore market state
	e.orderBook.UpdatePrice(snapshot.CurrentPrice, snapshot.LastTradeTime)

	// 3. Restore Conditional Manager state
	if e.conditionalManager != nil {
		// Restore triggers
		if len(snapshot.Triggers) > 0 || len(snapshot.TriggerQueue) > 0 {
			if err := e.conditionalManager.RestoreTriggerState(snapshot.Triggers, snapshot.TriggerQueue); err != nil {
				log.Error("Failed to restore trigger state", "error", err)
			}
		}

		// Restore OCO pairs
		if len(snapshot.OCOPairs) > 0 {
			if err := e.conditionalManager.RestoreOCOPairs(snapshot.OCOPairs); err != nil {
				log.Error("Failed to restore OCO pairs", "error", err)
			}
		}
	}

	log.Debug("Engine restored from minimal snapshot",
		"symbol", e.symbol,
		"orders", len(snapshot.Orders),
		"triggers", len(snapshot.Triggers),
		"ocoPairs", len(snapshot.OCOPairs),
		"block", snapshot.BlockNumber)

	return nil
}

// reset is the internal reset method (must be called with lock held)
func (e *SymbolEngine) reset() {
	// Create new orderbook
	e.orderBook = book.NewOrderBook(e.symbol)

	// Create new matcher with market rules
	e.matcher = matching.NewPriceTimePriority(e.symbol, e.marketRules)

	// Create new conditional manager
	e.conditionalManager = conditional.NewManager()

	// Wire up callbacks for conditional manager
	e.conditionalManager.SetOrderProcessor(func(order *types.Order) error {
		e.triggeredQueue = append(e.triggeredQueue, order)
		return nil
	})

	e.conditionalManager.SetOrderCanceller(func(orderID types.OrderID) error {
		return e.cancelOrderDirect(orderID, "Conditional/OCO cancellation")
	})

	// Clear triggered queue
	e.triggeredQueue = nil

	// Reset block context
	e.blockNumber = 0
}

// RestoreStopOrder restores a stop order
func (e *SymbolEngine) RestoreStopOrder(stopOrder *types.StopOrder) error {
	if e.conditionalManager == nil {
		return fmt.Errorf("conditional manager not initialized")
	}
	return e.conditionalManager.RestoreStopOrder(stopOrder)
}

// GetAllOrders returns all active orders
func (e *SymbolEngine) GetAllOrders() []*types.Order {
	e.mu.Lock()
	defer e.mu.Unlock()

	if e.orderBook == nil {
		return nil
	}

	// Collect all orders from the order book
	var orders []*types.Order

	// Get all buy orders
	buyOrders := e.orderBook.GetBuyOrders()
	orders = append(orders, buyOrders...)

	// Get all sell orders
	sellOrders := e.orderBook.GetSellOrders()
	orders = append(orders, sellOrders...)

	return orders
}
