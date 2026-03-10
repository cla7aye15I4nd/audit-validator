package orderbook

import (
	"container/heap"
	"fmt"

	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// BaseEvent contains common fields for all events
type BaseEvent struct {
	BlockNumber uint64
	TxIndex     int
	Timestamp   int64
}

// OrderbookEvent represents a deterministic state transition
type OrderbookEvent interface {
	Apply(d *Dispatcher) error // Deterministic state transition
	GetBase() BaseEvent
	GetEventType() string
}

// Helper function to create a new base event
func newBaseEvent(blockNum uint64, txIndex int) BaseEvent {
	return BaseEvent{
		BlockNumber: blockNum,
		TxIndex:     txIndex,
		Timestamp:   0, // Will be set by the event creator
	}
}

// OrderAddedEvent - Order added to buy/sell queue
type OrderAddedEvent struct {
	BaseEvent
	Order *Order
}

func (e *OrderAddedEvent) GetBase() BaseEvent {
	return e.BaseEvent
}

func (e *OrderAddedEvent) GetEventType() string {
	return "OrderAdded"
}

func (e *OrderAddedEvent) Apply(d *Dispatcher) error {
	if e.Order == nil {
		return fmt.Errorf("OrderAddedEvent: order is nil")
	}

	// Get or create engine
	engine := d.getOrCreateEngineForRecovery(e.Order.Symbol)

	// Check if order already exists (can happen with modify operations that reuse OrderID)
	if _, exists := engine.userBook.GetOrder(e.Order.OrderID); exists {
		// Order already exists, need to remove it first from queue
		if e.Order.Side == BUY {
			for i, order := range engine.buyQueue {
				if order.OrderID == e.Order.OrderID {
					heap.Remove(&engine.buyQueue, i)
					break
				}
			}
		} else {
			for i, order := range engine.sellQueue {
				if order.OrderID == e.Order.OrderID {
					heap.Remove(&engine.sellQueue, i)
					break
				}
			}
		}

		log.Info("OrderAddedEvent: Replaced existing order during recovery",
			"orderID", e.Order.OrderID,
			"symbol", e.Order.Symbol,
			"side", e.Order.Side,
			"price", e.Order.Price.String())
	}

	// Create a single copy that will be shared between userbook and queue
	orderCopy := e.Order.Copy()

	// Add to user book
	engine.userBook.AddOrder(orderCopy)

	// Add to appropriate queue (same instance)
	if e.Order.Side == BUY {
		heap.Push(&engine.buyQueue, orderCopy)
		engine.buyDirty[e.Order.Price.String()] = struct{}{}
	} else {
		heap.Push(&engine.sellQueue, orderCopy)
		engine.sellDirty[e.Order.Price.String()] = struct{}{}
	}

	// Update order routing
	d.mu.Lock()
	d.orderRouting[e.Order.OrderID] = OrderRoutingInfo{
		Symbol: e.Order.Symbol,
	}
	d.mu.Unlock()

	log.Info("OrderAddedEvent: Applied order",
		"orderID", e.Order.OrderID,
		"symbol", e.Order.Symbol,
		"side", e.Order.Side,
		"price", e.Order.Price.String(),
		"qty", e.Order.Quantity.String())

	return nil
}

// OrderQuantityUpdatedEvent - Updates order quantity (partial fill)
type OrderQuantityUpdatedEvent struct {
	BaseEvent
	OrderID     string
	Symbol      string
	NewQuantity *uint256.Int
}

func (e *OrderQuantityUpdatedEvent) GetBase() BaseEvent {
	return e.BaseEvent
}

func (e *OrderQuantityUpdatedEvent) GetEventType() string {
	return "OrderQuantityUpdated"
}

func (e *OrderQuantityUpdatedEvent) Apply(d *Dispatcher) error {
	d.mu.RLock()
	engine, exists := d.engines[e.Symbol]
	d.mu.RUnlock()

	if !exists {
		return fmt.Errorf("OrderQuantityUpdatedEvent: engine not found for symbol %s", e.Symbol)
	}

	// Find order in userbook
	order, _ := engine.userBook.GetOrder(e.OrderID)
	if order == nil {
		return fmt.Errorf("OrderQuantityUpdatedEvent: order %s not found", e.OrderID)
	}

	// Update quantity
	order.Quantity = e.NewQuantity.Clone()

	// Also update in the queue (heap maintains order by price, not quantity)
	// The order pointer in queue is the same as in userbook
	if order.Side == BUY {
		engine.buyDirty[order.Price.String()] = struct{}{}
	} else {
		engine.sellDirty[order.Price.String()] = struct{}{}
	}

	return nil
}

// OrderRemovedEvent - Order removed from all structures
type OrderRemovedEvent struct {
	BaseEvent
	OrderID string
	Symbol  string
	Side    Side
}

func (e *OrderRemovedEvent) GetBase() BaseEvent {
	return e.BaseEvent
}

func (e *OrderRemovedEvent) GetEventType() string {
	return "OrderRemoved"
}

func (e *OrderRemovedEvent) Apply(d *Dispatcher) error {
	d.mu.RLock()
	engine, exists := d.engines[e.Symbol]
	d.mu.RUnlock()

	if !exists {
		return fmt.Errorf("OrderRemovedEvent: engine not found for symbol %s", e.Symbol)
	}

	// Get order and mark as canceled (keep in userBook for consistency)
	order, exists := engine.userBook.GetOrder(e.OrderID)
	if order != nil && exists {
		// Mark order as canceled (like in normal cancel flow)
		order.IsCanceled = true
		
		// Update dirty flags for price level
		if order.Side == BUY {
			engine.buyDirty[order.Price.String()] = struct{}{}
		} else {
			engine.sellDirty[order.Price.String()] = struct{}{}
		}
	}

	// Remove from appropriate queue
	if e.Side == BUY {
		for i, order := range engine.buyQueue {
			if order.OrderID == e.OrderID {
				heap.Remove(&engine.buyQueue, i)
				break
			}
		}
	} else {
		for i, order := range engine.sellQueue {
			if order.OrderID == e.OrderID {
				heap.Remove(&engine.sellQueue, i)
				break
			}
		}
	}

	// Remove from order routing (but keep in userBook with IsCanceled=true)
	d.mu.Lock()
	delete(d.orderRouting, e.OrderID)
	d.mu.Unlock()

	return nil
}

// PriceUpdatedEvent - Updates current price for a symbol
type PriceUpdatedEvent struct {
	BaseEvent
	Symbol string
	Price  *uint256.Int
}

func (e *PriceUpdatedEvent) GetBase() BaseEvent {
	return e.BaseEvent
}

func (e *PriceUpdatedEvent) GetEventType() string {
	return "PriceUpdated"
}

func (e *PriceUpdatedEvent) Apply(d *Dispatcher) error {
	d.mu.RLock()
	engine, exists := d.engines[e.Symbol]
	d.mu.RUnlock()

	if !exists {
		// Create engine if it doesn't exist (possible for first trade)
		engine = d.getOrCreateEngineForRecovery(e.Symbol)
	}

	engine.currentPrice = e.Price.Clone()
	return nil
}

// TPSLOrderAddedEvent - TPSL order added
type TPSLOrderAddedEvent struct {
	BaseEvent
	TPSLOrder *TPSLOrder
}

func (e *TPSLOrderAddedEvent) GetBase() BaseEvent {
	return e.BaseEvent
}

func (e *TPSLOrderAddedEvent) GetEventType() string {
	return "TPSLOrderAdded"
}

func (e *TPSLOrderAddedEvent) Apply(d *Dispatcher) error {
	if e.TPSLOrder == nil {
		return fmt.Errorf("TPSLOrderAddedEvent: TPSL order is nil")
	}

	// Get symbol from TPSL order
	symbol := ""
	if e.TPSLOrder.TPOrder != nil && e.TPSLOrder.TPOrder.Order != nil {
		symbol = e.TPSLOrder.TPOrder.Order.Symbol
	} else if e.TPSLOrder.SLOrder != nil && e.TPSLOrder.SLOrder.Order != nil {
		symbol = e.TPSLOrder.SLOrder.Order.Symbol
	}

	if symbol == "" {
		return fmt.Errorf("TPSLOrderAddedEvent: cannot determine symbol from TPSL order")
	}

	engine := d.getOrCreateEngineForRecovery(symbol)

	// Add TPSL order
	engine.conditionalOrderManager.legacyOrders = append(engine.conditionalOrderManager.legacyOrders, e.TPSLOrder.Copy())
	// Also add to queue
	if e.TPSLOrder.TPOrder != nil && e.TPSLOrder.SLOrder != nil {
		entry := ConditionalOrderEntry{
			OrderID:   e.TPSLOrder.TPOrder.Order.OrderID,
			OrderType: ConditionalTPSL,
			Data:      e.TPSLOrder.Copy(),
			Timestamp: e.TPSLOrder.TPOrder.Order.Timestamp,
			Sequence:  engine.conditionalOrderManager.nextSequence,
		}
		engine.conditionalOrderManager.nextSequence++
		engine.conditionalOrderManager.queue = append(engine.conditionalOrderManager.queue, entry)
	} else {
		// Single stop order
		var orderID string
		var timestamp int64
		if e.TPSLOrder.TPOrder != nil {
			orderID = e.TPSLOrder.TPOrder.Order.OrderID
			timestamp = e.TPSLOrder.TPOrder.Order.Timestamp
		} else if e.TPSLOrder.SLOrder != nil {
			orderID = e.TPSLOrder.SLOrder.Order.OrderID
			timestamp = e.TPSLOrder.SLOrder.Order.Timestamp
		}
		entry := ConditionalOrderEntry{
			OrderID:   orderID,
			OrderType: ConditionalStop,
			Data:      e.TPSLOrder.Copy(),
			Timestamp: timestamp,
			Sequence:  engine.conditionalOrderManager.nextSequence,
		}
		engine.conditionalOrderManager.nextSequence++
		engine.conditionalOrderManager.queue = append(engine.conditionalOrderManager.queue, entry)
	}

	return nil
}

// TPSLOrderRemovedEvent - TPSL order removed
type TPSLOrderRemovedEvent struct {
	BaseEvent
	OrderID string // The order ID (currently same as TPSL ID)
	Symbol  string
}

func (e *TPSLOrderRemovedEvent) GetBase() BaseEvent {
	return e.BaseEvent
}

func (e *TPSLOrderRemovedEvent) GetEventType() string {
	return "TPSLOrderRemoved"
}

func (e *TPSLOrderRemovedEvent) Apply(d *Dispatcher) error {
	d.mu.RLock()
	engine, exists := d.engines[e.Symbol]
	d.mu.RUnlock()

	if !exists {
		return fmt.Errorf("TPSLOrderRemovedEvent: engine not found for symbol %s", e.Symbol)
	}

	// Remove from both legacy orders and queue
	var newLegacy []*TPSLOrder
	for _, tpsl := range engine.conditionalOrderManager.legacyOrders {
		var tpslOrderID string
		if tpsl.TPOrder != nil && tpsl.TPOrder.Order != nil {
			tpslOrderID = tpsl.TPOrder.Order.OrderID
		} else if tpsl.SLOrder != nil && tpsl.SLOrder.Order != nil {
			tpslOrderID = tpsl.SLOrder.Order.OrderID
		}

		if tpslOrderID != e.OrderID {
			newLegacy = append(newLegacy, tpsl)
		}
	}
	engine.conditionalOrderManager.legacyOrders = newLegacy
	
	// Also remove from queue
	var newQueue []ConditionalOrderEntry
	for _, entry := range engine.conditionalOrderManager.queue {
		keep := true
		if tpsl, ok := entry.Data.(*TPSLOrder); ok {
			if (tpsl.TPOrder != nil && tpsl.TPOrder.Order != nil && tpsl.TPOrder.Order.OrderID == e.OrderID) ||
			   (tpsl.SLOrder != nil && tpsl.SLOrder.Order != nil && tpsl.SLOrder.Order.OrderID == e.OrderID) {
				keep = false
			}
		}
		if keep {
			newQueue = append(newQueue, entry)
		}
	}
	engine.conditionalOrderManager.queue = newQueue

	return nil
}

// Helper method for Dispatcher to get or create engine during recovery
func (d *Dispatcher) getOrCreateEngineForRecovery(symbol string) *SymbolEngine {
	d.mu.Lock()
	defer d.mu.Unlock()

	engine, exists := d.engines[symbol]
	if !exists {
		d.symbols[symbol] = struct{}{}
		// Create engine without starting goroutine for recovery
		engine = &SymbolEngine{
			symbol:                  symbol,
			buyQueue:                make(BuyQueue, 0),
			sellQueue:               make(SellQueue, 0),
			userBook:                NewUserBook(),
			conditionalOrderManager: NewConditionalOrderManager(),
			snapshotManager:         NewSnapshotManager(symbol),
			marketRules:             NewMarketRules(),
			tradeMatcher:            NewTradeMatcher(symbol),
			triggered:               make([]*TriggeredOrder, 0),
			level2Book:              NewLevel2Book(),
			buyDirty:                make(map[string]struct{}),
			sellDirty:               make(map[string]struct{}),
			queue:                   make(chan Request, OrderQueueSize),
			quit:                    make(chan struct{}),
		}
		d.engines[symbol] = engine
	}

	return engine
}

// StartEngineGoroutines starts the goroutines for all engines after recovery
func (d *Dispatcher) StartEngineGoroutines() {
	d.mu.RLock()
	defer d.mu.RUnlock()

	for _, engine := range d.engines {
		go engine.run()
	}
}
