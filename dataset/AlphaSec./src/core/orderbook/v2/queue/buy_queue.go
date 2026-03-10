package queue

import (
	"container/heap"
	
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
)

// BuyQueue implements a max heap for buy orders
// Higher price orders have priority, then earlier timestamp
type BuyQueue struct {
	orders []*types.Order
	index  map[types.OrderID]int // OrderID -> heap index for O(1) lookup
}

// NewBuyQueue creates a new buy queue
func NewBuyQueue() *BuyQueue {
	q := &BuyQueue{
		orders: make([]*types.Order, 0),
		index:  make(map[types.OrderID]int),
	}
	heap.Init(q)
	return q
}

// AddOrder adds an order to the queue
func (q *BuyQueue) AddOrder(order *types.Order) {
	heap.Push(q, order)
}

// RemoveTop removes and returns the top order
func (q *BuyQueue) RemoveTop() *types.Order {
	if q.Len() == 0 {
		return nil
	}
	return heap.Pop(q).(*types.Order)
}

// Peek returns the top order without removing it
func (q *BuyQueue) Peek() *types.Order {
	if q.Len() == 0 {
		return nil
	}
	return q.orders[0]
}

// Update updates an order in the queue (for partial fills)
func (q *BuyQueue) Update(order *types.Order) {
	idx, exists := q.index[order.OrderID]
	if !exists {
		return
	}
	
	q.orders[idx] = order
	// Fix heap property after update
	heap.Fix(q, idx)
}

// Remove removes a specific order by ID
func (q *BuyQueue) Remove(orderID types.OrderID) bool {
	idx, exists := q.index[orderID]
	if !exists {
		return false
	}
	
	heap.Remove(q, idx)
	return true
}

// IsEmpty returns true if the queue is empty
func (q *BuyQueue) IsEmpty() bool {
	return q.Len() == 0
}

// Clear removes all orders from the queue
func (q *BuyQueue) Clear() {
	q.orders = q.orders[:0]
	q.index = make(map[types.OrderID]int)
}

// GetOrders returns all orders in the queue (in heap order, not sorted)
func (q *BuyQueue) GetOrders() []*types.Order {
	// Return a copy to prevent external modification
	result := make([]*types.Order, len(q.orders))
	copy(result, q.orders)
	return result
}

// GetOrdersSorted returns all orders sorted by priority
func (q *BuyQueue) GetOrdersSorted() []*types.Order {
	// Create a copy and sort it
	temp := make([]*types.Order, len(q.orders))
	copy(temp, q.orders)
	
	// Use a temporary heap to sort
	tempQueue := &BuyQueue{
		orders: temp,
		index:  make(map[types.OrderID]int),
	}
	heap.Init(tempQueue)
	
	result := make([]*types.Order, 0, len(temp))
	for tempQueue.Len() > 0 {
		result = append(result, heap.Pop(tempQueue).(*types.Order))
	}
	
	return result
}

// heap.Interface implementation

// Len returns the number of orders in the queue
func (q *BuyQueue) Len() int {
	return len(q.orders)
}

// Less compares two orders for priority
// For buy orders: higher price comes first, then earlier timestamp
func (q *BuyQueue) Less(i, j int) bool {
	// First compare prices (higher price = higher priority for buy)
	priceCmp := q.orders[i].Price.Cmp(q.orders[j].Price)
	if priceCmp != 0 {
		return priceCmp > 0 // Higher price first
	}
	
	// Same price: earlier timestamp wins (FIFO)
	return q.orders[i].Timestamp < q.orders[j].Timestamp
}

// Swap swaps two orders in the queue
func (q *BuyQueue) Swap(i, j int) {
	q.orders[i], q.orders[j] = q.orders[j], q.orders[i]
	
	// Update index map
	q.index[q.orders[i].OrderID] = i
	q.index[q.orders[j].OrderID] = j
	
	// Update heap index in orders
	q.orders[i].Index = i
	q.orders[j].Index = j
}

// Push adds an element to the heap (heap.Interface requirement)
func (q *BuyQueue) Push(x interface{}) {
	order := x.(*types.Order)
	order.Index = len(q.orders)
	q.orders = append(q.orders, order)
	q.index[order.OrderID] = order.Index
}

// Pop removes and returns the last element (heap.Interface requirement)
func (q *BuyQueue) Pop() interface{} {
	n := len(q.orders)
	order := q.orders[n-1]
	q.orders = q.orders[:n-1]
	
	// Clean up index map
	delete(q.index, order.OrderID)
	order.Index = -1
	
	return order
}