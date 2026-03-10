package book

import (
	"fmt"
	"strconv"
	"sync"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/metrics"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/queue"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
)

// OrderBook manages buy and sell orders for a trading pair
type OrderBook struct {
	symbol    types.Symbol
	buyQueue  *queue.BuyQueue
	sellQueue *queue.SellQueue

	// Order tracking
	orders     map[types.OrderID]*types.Order   // All orders by ID
	userOrders map[types.UserID][]types.OrderID // Orders by user

	// Price level tracking for depth calculation
	buyLevels  map[string]*PriceLevel // Price string -> aggregated level
	sellLevels map[string]*PriceLevel

	// Level2 change tracking (for diff calculation)
	dirtyBidPrices map[string]bool // Bid prices that changed this block
	dirtyAskPrices map[string]bool // Ask prices that changed this block

	// Current market state
	currentPrice  *types.Price
	lastTradeTime int64

	// Level2 snapshot cache for API performance
	snapshotCache    *types.Aggregated // Cached snapshot data
	snapshotBlockNum uint64            // Block number when snapshot was generated
	snapshotCacheMu  sync.RWMutex      // Separate mutex for snapshot cache

	mu sync.RWMutex
}

// PriceLevel represents an aggregated price level
type PriceLevel struct {
	Price      *types.Price
	Quantity   *types.Quantity
	OrderCount int
}

// NewOrderBook creates a new order book
func NewOrderBook(symbol types.Symbol) *OrderBook {
	return &OrderBook{
		symbol:           symbol,
		buyQueue:         queue.NewBuyQueue(),
		sellQueue:        queue.NewSellQueue(),
		orders:           make(map[types.OrderID]*types.Order),
		userOrders:       make(map[types.UserID][]types.OrderID),
		buyLevels:        make(map[string]*PriceLevel),
		sellLevels:       make(map[string]*PriceLevel),
		dirtyBidPrices:   make(map[string]bool),
		dirtyAskPrices:   make(map[string]bool),
		currentPrice:     types.NewPrice(0),
		snapshotCache:    nil, // Will be populated on first GenerateSnapshot call
		snapshotBlockNum: 0,
	}
}

// AddOrder adds an order to the orderbook
func (ob *OrderBook) AddOrder(order *types.Order) error {
	ob.mu.Lock()
	defer ob.mu.Unlock()

	if order == nil {
		return fmt.Errorf("order cannot be nil")
	}

	// Check if order already exists
	if _, exists := ob.orders[order.OrderID]; exists {
		return fmt.Errorf("order %s already exists", order.OrderID)
	}

	// Add to appropriate queue
	if order.Side == types.BUY {
		ob.buyQueue.AddOrder(order)
		ob.updatePriceLevel(ob.buyLevels, order, true)
	} else {
		ob.sellQueue.AddOrder(order)
		ob.updatePriceLevel(ob.sellLevels, order, true)
	}

	// Track order
	ob.orders[order.OrderID] = order
	ob.userOrders[order.UserID] = append(ob.userOrders[order.UserID], order.OrderID)

	// Update symbol-specific metrics for queue counts
	symbolStr := string(ob.symbol)
	metrics.GetSymbolGauge("orderbook/symbol/orders/buy", symbolStr).Update(int64(ob.buyQueue.Len()))
	metrics.GetSymbolGauge("orderbook/symbol/orders/sell", symbolStr).Update(int64(ob.sellQueue.Len()))

	return nil
}

// RemoveOrder removes an order from the orderbook
func (ob *OrderBook) RemoveOrder(orderID types.OrderID) error {
	ob.mu.Lock()
	defer ob.mu.Unlock()

	order, exists := ob.orders[orderID]
	if !exists {
		return fmt.Errorf("order %s not found", orderID)
	}

	// Remove from queue
	if order.Side == types.BUY {
		ob.buyQueue.Remove(orderID)
		ob.updatePriceLevel(ob.buyLevels, order, false)
	} else {
		ob.sellQueue.Remove(orderID)
		ob.updatePriceLevel(ob.sellLevels, order, false)
	}

	// Remove from tracking
	delete(ob.orders, orderID)
	ob.removeFromUserOrders(order.UserID, orderID)

	// Update symbol-specific metrics for queue counts
	symbolStr := string(ob.symbol)
	metrics.GetSymbolGauge("orderbook/symbol/orders/buy", symbolStr).Update(int64(ob.buyQueue.Len()))
	metrics.GetSymbolGauge("orderbook/symbol/orders/sell", symbolStr).Update(int64(ob.sellQueue.Len()))

	return nil
}

// UpdateOrder updates an order (for partial fills)
func (ob *OrderBook) UpdateOrder(order *types.Order) error {
	ob.mu.Lock()
	defer ob.mu.Unlock()

	oldOrder, exists := ob.orders[order.OrderID]
	if !exists {
		return fmt.Errorf("order %s not found", order.OrderID)
	}

	// Update in queue
	if order.Side == types.BUY {
		ob.buyQueue.Update(order)
		// Update price level (remove old, add new)
		ob.updatePriceLevel(ob.buyLevels, oldOrder, false)
		ob.updatePriceLevel(ob.buyLevels, order, true)
	} else {
		ob.sellQueue.Update(order)
		ob.updatePriceLevel(ob.sellLevels, oldOrder, false)
		ob.updatePriceLevel(ob.sellLevels, order, true)
	}

	// Update tracking
	ob.orders[order.OrderID] = order

	// Update symbol-specific metrics for queue counts
	symbolStr := string(ob.symbol)
	metrics.GetSymbolGauge("orderbook/symbol/orders/buy", symbolStr).Update(int64(ob.buyQueue.Len()))
	metrics.GetSymbolGauge("orderbook/symbol/orders/sell", symbolStr).Update(int64(ob.sellQueue.Len()))

	return nil
}

// GetOrder returns an order by ID
func (ob *OrderBook) GetOrder(orderID types.OrderID) (*types.Order, bool) {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	order, exists := ob.orders[orderID]
	if !exists {
		return nil, false
	}

	// Return a copy to prevent external modification
	return order.Copy(), true
}

// GetUserOrders returns all orders for a user
func (ob *OrderBook) GetUserOrders(userID types.UserID) []*types.Order {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	orderIDs := ob.userOrders[userID]
	result := make([]*types.Order, 0, len(orderIDs))

	for _, id := range orderIDs {
		if order, exists := ob.orders[id]; exists {
			result = append(result, order.Copy())
		}
	}

	return result
}

// GetBuyOrders returns all buy orders
func (ob *OrderBook) GetBuyOrders() []*types.Order {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	return ob.buyQueue.GetOrdersSorted()
}

// GetSellOrders returns all sell orders
func (ob *OrderBook) GetSellOrders() []*types.Order {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	return ob.sellQueue.GetOrdersSorted()
}

// GetBestBid returns the best bid order
func (ob *OrderBook) GetBestBid() *types.Order {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	return ob.buyQueue.Peek()
}

// GetBestAsk returns the best ask order
func (ob *OrderBook) GetBestAsk() *types.Order {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	return ob.sellQueue.Peek()
}

// GetDepth returns the orderbook depth up to a limit
func (ob *OrderBook) GetDepth(limit int) (bids, asks []interfaces.PriceLevel) {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	// Get sorted orders
	buyOrders := ob.buyQueue.GetOrdersSorted()
	sellOrders := ob.sellQueue.GetOrdersSorted()

	// Aggregate by price level
	bids = ob.aggregateOrders(buyOrders, limit)
	asks = ob.aggregateOrders(sellOrders, limit)

	return bids, asks
}

// GetSpread returns the bid-ask spread
func (ob *OrderBook) GetSpread() *types.Price {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	bestBuy := ob.buyQueue.Peek()
	bestSell := ob.sellQueue.Peek()

	if bestBuy == nil || bestSell == nil {
		return nil
	}

	// Spread = ask - bid
	spread := new(types.Price).Sub(bestSell.Price, bestBuy.Price)
	return spread
}

// Clear removes all orders
func (ob *OrderBook) Clear() {
	ob.mu.Lock()
	defer ob.mu.Unlock()

	ob.buyQueue.Clear()
	ob.sellQueue.Clear()
	ob.orders = make(map[types.OrderID]*types.Order)
	ob.userOrders = make(map[types.UserID][]types.OrderID)
	ob.buyLevels = make(map[string]*PriceLevel)
	ob.sellLevels = make(map[string]*PriceLevel)
}

// Helper methods

// updatePriceLevel updates the aggregated price level
func (ob *OrderBook) updatePriceLevel(levels map[string]*PriceLevel, order *types.Order, add bool) {
	priceStr := order.Price.String()

	// Mark price as dirty for Level2 diff tracking
	if order.Side == types.BUY {
		ob.dirtyBidPrices[priceStr] = true
	} else {
		ob.dirtyAskPrices[priceStr] = true
	}

	level, exists := levels[priceStr]
	if !exists && add {
		levels[priceStr] = &PriceLevel{
			Price:      order.Price.Clone(),
			Quantity:   order.Quantity.Clone(),
			OrderCount: 1,
		}
		return
	}

	if !exists {
		return // Nothing to remove
	}

	if add {
		level.Quantity = new(types.Quantity).Add(level.Quantity, order.Quantity)
		level.OrderCount++
	} else {
		level.Quantity = new(types.Quantity).Sub(level.Quantity, order.Quantity)
		level.OrderCount--

		if level.OrderCount == 0 {
			delete(levels, priceStr)
		}
	}
}

// removeFromUserOrders removes an order ID from user's order list
func (ob *OrderBook) removeFromUserOrders(userID types.UserID, orderID types.OrderID) {
	orderIDs := ob.userOrders[userID]
	for i, id := range orderIDs {
		if id == orderID {
			// Remove by swapping with last and truncating
			orderIDs[i] = orderIDs[len(orderIDs)-1]
			ob.userOrders[userID] = orderIDs[:len(orderIDs)-1]

			// Clean up if user has no more orders
			if len(ob.userOrders[userID]) == 0 {
				delete(ob.userOrders, userID)
			}
			return
		}
	}
}

// aggregateOrders aggregates orders by price level
func (ob *OrderBook) aggregateOrders(orders []*types.Order, limit int) []interfaces.PriceLevel {
	levels := make([]interfaces.PriceLevel, 0)
	levelMap := make(map[string]*interfaces.PriceLevel)

	for _, order := range orders {
		priceStr := order.Price.String()

		if level, exists := levelMap[priceStr]; exists {
			level.Quantity = new(types.Quantity).Add(level.Quantity, order.Quantity)
			level.Orders++
		} else {
			newLevel := &interfaces.PriceLevel{
				Price:    order.Price.Clone(),
				Quantity: order.Quantity.Clone(),
				Orders:   1,
			}
			levelMap[priceStr] = newLevel
			levels = append(levels, *newLevel)

			if len(levels) >= limit {
				break
			}
		}
	}

	return levels
}

// GetCurrentPrice returns the current/last traded price
func (ob *OrderBook) GetCurrentPrice() *types.Price {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	if ob.currentPrice == nil {
		return nil
	}
	return ob.currentPrice.Clone()
}

// UpdatePrice updates the current price and last trade time
func (ob *OrderBook) UpdatePrice(price *types.Price, timestamp int64) {
	ob.mu.Lock()
	defer ob.mu.Unlock()

	ob.currentPrice = price.Clone()
	ob.lastTradeTime = timestamp
}

// GetLastTradeTime returns the last trade timestamp
func (ob *OrderBook) GetLastTradeTime() int64 {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	return ob.lastTradeTime
}

// GetBuyOrderCount returns the number of buy orders
func (ob *OrderBook) GetBuyOrderCount() int {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	return ob.buyQueue.Len()
}

// GetSellOrderCount returns the number of sell orders
func (ob *OrderBook) GetSellOrderCount() int {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	return ob.sellQueue.Len()
}

// Level2 Book Methods

// GetLevel2Diff returns the price levels that changed since last call
// Returns absolute quantities for changed prices (0 means removed)
// Clears dirty flags after returning
func (ob *OrderBook) GetLevel2Diff() (bidDiff, askDiff [][]string) {
	ob.mu.Lock()
	defer ob.mu.Unlock()

	// Process dirty bid prices
	if len(ob.dirtyBidPrices) > 0 {
		bidDiff = ob.formatDirtyLevels(ob.buyLevels, ob.dirtyBidPrices, true)
		ob.dirtyBidPrices = make(map[string]bool)
	}

	// Process dirty ask prices
	if len(ob.dirtyAskPrices) > 0 {
		askDiff = ob.formatDirtyLevels(ob.sellLevels, ob.dirtyAskPrices, false)
		ob.dirtyAskPrices = make(map[string]bool)
	}

	return bidDiff, askDiff
}

// GenerateSnapshot generates and caches a Level2 snapshot for the given block
// This should be called at the end of each block to pre-compute the snapshot
func (ob *OrderBook) GenerateSnapshot(blockNum uint64) {
	ob.mu.RLock()
	bids := ob.formatAllLevels(ob.buyLevels, true)
	asks := ob.formatAllLevels(ob.sellLevels, false)
	ob.mu.RUnlock()

	snapshot := &types.Aggregated{
		Symbol: string(ob.symbol),
		Bids:   bids,
		Asks:   asks,
	}

	// Update cache with separate mutex to minimize lock time
	ob.snapshotCacheMu.Lock()
	ob.snapshotCache = snapshot
	ob.snapshotBlockNum = blockNum
	ob.snapshotCacheMu.Unlock()

}

// GetLevel2Snapshot returns the full Level2 orderbook
// If a cached snapshot exists, it returns that for better performance
func (ob *OrderBook) GetLevel2Snapshot() *types.Aggregated {
	// Try to return cached snapshot first
	ob.snapshotCacheMu.RLock()
	if ob.snapshotCache != nil {
		cached := ob.snapshotCache
		ob.snapshotCacheMu.RUnlock()
		return cached
	}
	ob.snapshotCacheMu.RUnlock()

	// No cache available, generate fresh snapshot
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	bids := ob.formatAllLevels(ob.buyLevels, true)
	asks := ob.formatAllLevels(ob.sellLevels, false)

	return &types.Aggregated{
		Symbol: string(ob.symbol),
		Bids:   bids,
		Asks:   asks,
	}
}

// formatDirtyLevels formats only the dirty price levels as [[price, quantity]]
func (ob *OrderBook) formatDirtyLevels(levels map[string]*PriceLevel, dirtyPrices map[string]bool, descending bool) [][]string {
	result := make([][]string, 0, len(dirtyPrices))

	for priceStr := range dirtyPrices {
		level, exists := levels[priceStr]

		// Convert price string (which is in uint256 format) to decimal
		price := (*types.Price)(types.MustFromUint256String(priceStr))
		priceDecimal := types.PriceToDecimalString(price, types.ScalingExp)

		var quantityStr string
		if exists && level.Quantity != nil && !level.Quantity.IsZero() {
			// Price level exists with quantity
			quantityStr = types.QuantityToDecimalString(level.Quantity, types.ScalingExp)
		} else {
			// Price level removed - send 0
			quantityStr = "0"
		}

		result = append(result, []string{priceDecimal, quantityStr})
	}

	// Sort by price
	ob.sortLevel2(result, descending)

	return result
}

// formatAllLevels formats all price levels as [[price, quantity]]
func (ob *OrderBook) formatAllLevels(levels map[string]*PriceLevel, descending bool) [][]string {
	result := make([][]string, 0, len(levels))

	for _, level := range levels {
		if level.Quantity == nil || level.Quantity.IsZero() {
			continue
		}

		priceDecimal := types.PriceToDecimalString(level.Price, types.ScalingExp)
		quantityDecimal := types.QuantityToDecimalString(level.Quantity, types.ScalingExp)

		result = append(result, []string{priceDecimal, quantityDecimal})
	}

	// Sort by price
	ob.sortLevel2(result, descending)

	return result
}

// sortLevel2 sorts the Level2 data by price
func (ob *OrderBook) sortLevel2(data [][]string, descending bool) {
	// Simple bubble sort for now (prices are already in decimal format)
	n := len(data)
	for i := 0; i < n-1; i++ {
		for j := 0; j < n-i-1; j++ {
			// Parse as float for comparison (already decimal strings)
			price1, _ := strconv.ParseFloat(data[j][0], 64)
			price2, _ := strconv.ParseFloat(data[j+1][0], 64)

			shouldSwap := false
			if descending {
				shouldSwap = price1 < price2
			} else {
				shouldSwap = price1 > price2
			}

			if shouldSwap {
				data[j], data[j+1] = data[j+1], data[j]
			}
		}
	}
}

// Snapshot Support Methods

// GetAllOrders returns all active orders in the orderbook
func (ob *OrderBook) GetAllOrders() []*types.Order {
	ob.mu.RLock()
	defer ob.mu.RUnlock()

	orders := make([]*types.Order, 0, len(ob.orders))
	for _, order := range ob.orders {
		orders = append(orders, order)
	}
	return orders
}
