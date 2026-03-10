package orderbook

import (
	"time"

	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// ConditionalOrderType represents the type of conditional order
type ConditionalOrderType uint8

const (
	ConditionalTPSL ConditionalOrderType = iota // Order with both TP and SL
	ConditionalStop                             // Single stop order (TP or SL)
	// Future: ConditionalOCO, ConditionalIceberg, etc.
)

// ConditionalOrderEntry represents an entry in the unified FIFO queue
type ConditionalOrderEntry struct {
	OrderID      string
	OrderType    ConditionalOrderType
	Data         interface{} // Type-specific data (*TPSLOrder for both types currently)
	Timestamp    int64
	Sequence     uint64 // Global sequence number for strict FIFO
	ShouldRemove bool   // Set by Process to indicate removal from queue
}

// OrderHandler defines the interface for handling different order types
type OrderHandler interface {
	// Process handles a triggered order
	Process(entry *ConditionalOrderEntry, lastPrice *uint256.Int, userBook *UserBook, locker *DefaultLocker, cancelFunc func(string, *DefaultLocker) bool) *TriggeredOrder
	// Cancel cancels an order by ID (returns cancelled order IDs)
	Cancel(orderID string, data interface{}, locker *DefaultLocker, cancelOrderbookFunc func(string, *DefaultLocker) bool) []string
	// CancelByUser cancels all orders for a user
	CancelByUser(userId string, data interface{}, locker *DefaultLocker) []string
	// ShouldTrigger checks if the order should trigger
	ShouldTrigger(data interface{}, lastPrice *uint256.Int) bool
	// GetOrderIDs returns the order IDs for this entry
	GetOrderIDs(data interface{}) []string
	// GetUserID returns the user ID for this entry
	GetUserID(data interface{}) string
}

// ConditionalOrderManager manages all conditional orders with unified FIFO queue
type ConditionalOrderManager struct {
	queue        []ConditionalOrderEntry
	handlers     map[ConditionalOrderType]OrderHandler
	nextSequence uint64

	// For backward compatibility with existing TPSLManager structure
	legacyOrders []*TPSLOrder // All orders in TPSLOrder format
}

// NewConditionalOrderManager creates a new ConditionalOrderManager
func NewConditionalOrderManager() *ConditionalOrderManager {
	m := &ConditionalOrderManager{
		queue:        make([]ConditionalOrderEntry, 0),
		handlers:     make(map[ConditionalOrderType]OrderHandler),
		nextSequence: 0,
		legacyOrders: make([]*TPSLOrder, 0),
	}

	// Register handlers
	m.handlers[ConditionalTPSL] = NewTPSLHandler()
	m.handlers[ConditionalStop] = NewStopOrderHandler()

	return m
}

// AddTPSLOrder adds a TPSL order (with both TP and SL)
func (m *ConditionalOrderManager) AddTPSLOrder(tpslOrder *TPSLOrder, locker *DefaultLocker) {
	if tpslOrder.TPOrder == nil || tpslOrder.SLOrder == nil {
		panic(ErrTPSLMissingOrders.Error())
	}

	if tpslOrder.submitted {
		return
	}

	now := time.Now().UnixNano()
	tpslOrder.TPOrder.Order.Timestamp = now
	tpslOrder.SLOrder.Order.Timestamp = now

	// Add to queue
	entry := ConditionalOrderEntry{
		OrderID:   tpslOrder.TPOrder.Order.OrderID, // Use TP order ID as identifier
		OrderType: ConditionalTPSL,
		Data:      tpslOrder,
		Timestamp: now,
		Sequence:  m.nextSequence,
	}
	m.nextSequence++
	m.queue = append(m.queue, entry)

	// Maintain legacy array
	m.legacyOrders = append(m.legacyOrders, tpslOrder)
}

// AddStopOrder adds a single stop order (either TP or SL)
func (m *ConditionalOrderManager) AddStopOrder(stopOrder *StopOrder, currentPrice *uint256.Int, locker *DefaultLocker) (bool, bool) {
	if currentPrice == nil || currentPrice.Cmp(stopOrder.StopPrice) == 0 {
		// Should trigger immediately
		return true, false
	}

	stopOrder.TriggerAbove = currentPrice.Cmp(stopOrder.StopPrice) < 0
	order := stopOrder.Order
	order.Timestamp = time.Now().UnixNano()
	locker.LockStopOrder(order, stopOrder.StopPrice)

	// Create TPSLOrder wrapper for legacy compatibility
	var tpslOrder *TPSLOrder
	if (stopOrder.TriggerAbove && order.Side == BUY) ||
		(!stopOrder.TriggerAbove && order.Side == SELL) {
		// TP
		tpslOrder = &TPSLOrder{
			TPOrder: stopOrder,
			SLOrder: nil,
		}
	} else {
		// SL
		tpslOrder = &TPSLOrder{
			TPOrder: nil,
			SLOrder: stopOrder,
		}
	}

	// Add to queue
	entry := ConditionalOrderEntry{
		OrderID:   order.OrderID,
		OrderType: ConditionalStop,
		Data:      tpslOrder, // Store as TPSLOrder for compatibility
		Timestamp: order.Timestamp,
		Sequence:  m.nextSequence,
	}
	m.nextSequence++
	m.queue = append(m.queue, entry)

	// Maintain legacy array
	m.legacyOrders = append(m.legacyOrders, tpslOrder)

	return false, stopOrder.TriggerAbove
}

// CheckOrders checks all conditional orders in FIFO order
func (m *ConditionalOrderManager) CheckOrders(lastTradePrice *uint256.Int, userBook *UserBook, locker *DefaultLocker,
	cancelFunc func(string, *DefaultLocker) bool) (triggered []*TriggeredOrder) {

	var remaining []ConditionalOrderEntry
	var remainingLegacy []*TPSLOrder

	log.Info("Checking conditional orders", "lastTradePrice", toDecimal(lastTradePrice), "count", len(m.queue))

	// Process queue in FIFO order
	for _, entry := range m.queue {
		handler, exists := m.handlers[entry.OrderType]
		if !exists {
			log.Error("No handler for order type", "type", entry.OrderType)
			continue
		}

		// Check if should trigger
		if handler.ShouldTrigger(entry.Data, lastTradePrice) {
			// Process the triggered order
			result := handler.Process(&entry, lastTradePrice, userBook, locker, cancelFunc)
			if result != nil {
				triggered = append(triggered, result)
			}
			
			// Check if entry should be removed from queue
			// The handler sets entry.ShouldRemove to indicate removal
			if !entry.ShouldRemove {
				// Keep in queue for continued monitoring
				remaining = append(remaining, entry)
				if tpsl, ok := entry.Data.(*TPSLOrder); ok {
					remainingLegacy = append(remainingLegacy, tpsl)
				}
			}
		} else {
			// Not triggered, keep in queue
			remaining = append(remaining, entry)

			// Keep in legacy array
			if tpsl, ok := entry.Data.(*TPSLOrder); ok {
				remainingLegacy = append(remainingLegacy, tpsl)
			}
		}
	}

	m.queue = remaining
	m.legacyOrders = remainingLegacy

	return triggered
}

// CancelOrder cancels a conditional order by order ID
func (m *ConditionalOrderManager) CancelOrder(orderID string, locker *DefaultLocker,
	cancelOrderbookFunc func(string, *DefaultLocker) bool) ([]string, bool) {

	// Just try to find and cancel by the given ID
	for i := len(m.queue) - 1; i >= 0; i-- {
		entry := m.queue[i]
		handler, exists := m.handlers[entry.OrderType]
		if !exists {
			continue
		}

		// Try to cancel by the given ID
		if cancelledIDs := handler.Cancel(orderID, entry.Data, locker, cancelOrderbookFunc); len(cancelledIDs) > 0 {
			// Remove from queue
			m.queue = append(m.queue[:i], m.queue[i+1:]...)
			// Update legacy orders
			if tpsl, ok := entry.Data.(*TPSLOrder); ok {
				m.legacyOrders = m.removeFromLegacy(m.legacyOrders, tpsl)
			}
			return cancelledIDs, true
		}
	}

	return nil, false
}

// Helper function to remove from legacy orders
func (m *ConditionalOrderManager) removeFromLegacy(orders []*TPSLOrder, toRemove *TPSLOrder) []*TPSLOrder {
	for i, order := range orders {
		if order == toRemove {
			return append(orders[:i], orders[i+1:]...)
		}
	}
	return orders
}

// CancelAllByUser cancels all orders for a user
func (m *ConditionalOrderManager) CancelAllByUser(userId string, locker *DefaultLocker,
	baseToken, quoteToken string) (cancelOrderIds []string) {

	var remaining []ConditionalOrderEntry
	var remainingLegacy []*TPSLOrder

	for _, entry := range m.queue {
		handler, exists := m.handlers[entry.OrderType]
		if !exists {
			remaining = append(remaining, entry)
			continue
		}

		// Check if this order belongs to the user
		if handler.GetUserID(entry.Data) == userId {
			// Cancel the order
			cancelledIds := handler.CancelByUser(userId, entry.Data, locker)
			cancelOrderIds = append(cancelOrderIds, cancelledIds...)
		} else {
			// Keep in queue
			remaining = append(remaining, entry)

			// Keep in legacy array
			if tpsl, ok := entry.Data.(*TPSLOrder); ok {
				remainingLegacy = append(remainingLegacy, tpsl)
			}
		}
	}

	m.queue = remaining
	m.legacyOrders = remainingLegacy

	return cancelOrderIds
}

// GetOrders returns all orders in legacy TPSLOrder format (for backward compatibility)
func (m *ConditionalOrderManager) GetOrders() []*TPSLOrder {
	return m.legacyOrders
}

// GetOrderByID finds any conditional order by ID
func (m *ConditionalOrderManager) GetOrderByID(orderID string) *StopOrder {
	for _, entry := range m.queue {
		if tpsl, ok := entry.Data.(*TPSLOrder); ok {
			if tpsl.TPOrder != nil && tpsl.TPOrder.Order.OrderID == orderID {
				return tpsl.TPOrder
			}
			if tpsl.SLOrder != nil && tpsl.SLOrder.Order.OrderID == orderID {
				return tpsl.SLOrder
			}
		}
	}
	return nil
}
