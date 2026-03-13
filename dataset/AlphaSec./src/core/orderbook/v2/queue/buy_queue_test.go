package queue

import (
	"fmt"
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBuyQueue_NewBuyQueue(t *testing.T) {
	q := NewBuyQueue()
	assert.NotNil(t, q)
	assert.NotNil(t, q.orders)
	assert.NotNil(t, q.index)
	assert.Equal(t, 0, q.Len())
	assert.True(t, q.IsEmpty())
}

func TestBuyQueue_AddAndRemoveTop(t *testing.T) {
	q := NewBuyQueue()

	// Create test orders with different prices
	order1 := &types.Order{
		OrderID:   "order1",
		Price:     uint256.NewInt(100),
		Quantity:  uint256.NewInt(10),
		Timestamp: time.Now().UnixNano(),
	}

	order2 := &types.Order{
		OrderID:   "order2",
		Price:     uint256.NewInt(110), // Higher price
		Quantity:  uint256.NewInt(20),
		Timestamp: time.Now().UnixNano() + 1,
	}

	order3 := &types.Order{
		OrderID:   "order3",
		Price:     uint256.NewInt(105),
		Quantity:  uint256.NewInt(15),
		Timestamp: time.Now().UnixNano() + 2,
	}

	// Add orders
	q.AddOrder(order1)
	q.AddOrder(order2)
	q.AddOrder(order3)

	assert.Equal(t, 3, q.Len())
	assert.False(t, q.IsEmpty())

	// Should remove in order of price (highest first for buy queue)
	removed := q.RemoveTop()
	assert.Equal(t, "order2", string(removed.OrderID))
	assert.Equal(t, uint256.NewInt(110), removed.Price)

	removed = q.RemoveTop()
	assert.Equal(t, "order3", string(removed.OrderID))
	assert.Equal(t, uint256.NewInt(105), removed.Price)

	removed = q.RemoveTop()
	assert.Equal(t, "order1", string(removed.OrderID))
	assert.Equal(t, uint256.NewInt(100), removed.Price)

	// Queue should be empty now
	assert.True(t, q.IsEmpty())
	assert.Nil(t, q.RemoveTop())
}

func TestBuyQueue_Peek(t *testing.T) {
	q := NewBuyQueue()

	// Peek on empty queue
	assert.Nil(t, q.Peek())

	// Add orders
	order1 := &types.Order{
		OrderID:   "order1",
		Price:     uint256.NewInt(100),
		Quantity:  uint256.NewInt(10),
		Timestamp: time.Now().UnixNano(),
	}

	order2 := &types.Order{
		OrderID:   "order2",
		Price:     uint256.NewInt(110), // Higher price
		Quantity:  uint256.NewInt(20),
		Timestamp: time.Now().UnixNano() + 1,
	}

	q.AddOrder(order1)
	q.AddOrder(order2)

	// Peek should return highest price order without removing it
	peeked := q.Peek()
	assert.Equal(t, "order2", string(peeked.OrderID))
	assert.Equal(t, 2, q.Len()) // Should still have 2 orders

	// Peek again should return the same order
	peeked = q.Peek()
	assert.Equal(t, "order2", string(peeked.OrderID))
}

func TestBuyQueue_PriceTimePriority(t *testing.T) {
	q := NewBuyQueue()

	now := time.Now().UnixNano()

	// Create orders with same price but different timestamps
	order1 := &types.Order{
		OrderID:   "order1",
		Price:     uint256.NewInt(100),
		Quantity:  uint256.NewInt(10),
		Timestamp: now + 2, // Latest
	}

	order2 := &types.Order{
		OrderID:   "order2",
		Price:     uint256.NewInt(100), // Same price
		Quantity:  uint256.NewInt(20),
		Timestamp: now, // Earliest
	}

	order3 := &types.Order{
		OrderID:   "order3",
		Price:     uint256.NewInt(100), // Same price
		Quantity:  uint256.NewInt(15),
		Timestamp: now + 1, // Middle
	}

	// Add orders
	q.AddOrder(order1)
	q.AddOrder(order2)
	q.AddOrder(order3)

	// Should remove in order of timestamp (earliest first) when prices are equal
	removed := q.RemoveTop()
	assert.Equal(t, "order2", string(removed.OrderID))

	removed = q.RemoveTop()
	assert.Equal(t, "order3", string(removed.OrderID))

	removed = q.RemoveTop()
	assert.Equal(t, "order1", string(removed.OrderID))
}

func TestBuyQueue_Update(t *testing.T) {
	q := NewBuyQueue()

	// Create test orders
	order1 := &types.Order{
		OrderID:   "order1",
		Price:     uint256.NewInt(100),
		Quantity:  uint256.NewInt(10),
		Timestamp: time.Now().UnixNano(),
	}

	order2 := &types.Order{
		OrderID:   "order2",
		Price:     uint256.NewInt(110),
		Quantity:  uint256.NewInt(20),
		Timestamp: time.Now().UnixNano() + 1,
	}

	q.AddOrder(order1)
	q.AddOrder(order2)

	// Update order1's quantity (partial fill)
	updatedOrder := &types.Order{
		OrderID:   "order1",
		Price:     uint256.NewInt(100),
		Quantity:  uint256.NewInt(5), // Reduced quantity
		Timestamp: order1.Timestamp,
	}

	q.Update(updatedOrder)

	// Remove all orders and check the update
	removed := q.RemoveTop()
	assert.Equal(t, "order2", string(removed.OrderID))

	removed = q.RemoveTop()
	assert.Equal(t, "order1", string(removed.OrderID))
	assert.Equal(t, uint256.NewInt(5), removed.Quantity) // Should have updated quantity

	// Update non-existent order should not panic
	q.Update(&types.Order{OrderID: "nonexistent"})
}

func TestBuyQueue_Remove(t *testing.T) {
	q := NewBuyQueue()

	// Create test orders
	order1 := &types.Order{
		OrderID:   "order1",
		Price:     uint256.NewInt(100),
		Quantity:  uint256.NewInt(10),
		Timestamp: time.Now().UnixNano(),
	}

	order2 := &types.Order{
		OrderID:   "order2",
		Price:     uint256.NewInt(110),
		Quantity:  uint256.NewInt(20),
		Timestamp: time.Now().UnixNano() + 1,
	}

	order3 := &types.Order{
		OrderID:   "order3",
		Price:     uint256.NewInt(105),
		Quantity:  uint256.NewInt(15),
		Timestamp: time.Now().UnixNano() + 2,
	}

	q.AddOrder(order1)
	q.AddOrder(order2)
	q.AddOrder(order3)

	// Remove middle order
	success := q.Remove("order3")
	assert.True(t, success)
	assert.Equal(t, 2, q.Len())

	// Try to remove non-existent order
	success = q.Remove("nonexistent")
	assert.False(t, success)
	assert.Equal(t, 2, q.Len())

	// Verify remaining orders
	removed := q.RemoveTop()
	assert.Equal(t, "order2", string(removed.OrderID))

	removed = q.RemoveTop()
	assert.Equal(t, "order1", string(removed.OrderID))

	assert.True(t, q.IsEmpty())
}

func TestBuyQueue_Clear(t *testing.T) {
	q := NewBuyQueue()

	// Add multiple orders
	for i := 0; i < 5; i++ {
		order := &types.Order{
			OrderID:   types.OrderID(string(rune('a' + i))),
			Price:     uint256.NewInt(uint64(100 + i)),
			Quantity:  uint256.NewInt(10),
			Timestamp: time.Now().UnixNano() + int64(i),
		}
		q.AddOrder(order)
	}

	assert.Equal(t, 5, q.Len())

	// Clear the queue
	q.Clear()

	assert.Equal(t, 0, q.Len())
	assert.True(t, q.IsEmpty())
	assert.Nil(t, q.Peek())
	assert.Nil(t, q.RemoveTop())
}

func TestBuyQueue_GetOrders(t *testing.T) {
	q := NewBuyQueue()

	// Create test orders
	order1 := &types.Order{
		OrderID:   "order1",
		Price:     uint256.NewInt(100),
		Quantity:  uint256.NewInt(10),
		Timestamp: time.Now().UnixNano(),
	}

	order2 := &types.Order{
		OrderID:   "order2",
		Price:     uint256.NewInt(110),
		Quantity:  uint256.NewInt(20),
		Timestamp: time.Now().UnixNano() + 1,
	}

	order3 := &types.Order{
		OrderID:   "order3",
		Price:     uint256.NewInt(105),
		Quantity:  uint256.NewInt(15),
		Timestamp: time.Now().UnixNano() + 2,
	}

	q.AddOrder(order1)
	q.AddOrder(order2)
	q.AddOrder(order3)

	// Get orders (unordered)
	orders := q.GetOrders()
	assert.Equal(t, 3, len(orders))

	// Verify it's a copy (modifying returned slice shouldn't affect queue)
	orders[0] = nil
	assert.Equal(t, 3, q.Len())
}

func TestBuyQueue_GetOrdersSorted(t *testing.T) {
	q := NewBuyQueue()

	// Create test orders
	order1 := &types.Order{
		OrderID:   "order1",
		Price:     uint256.NewInt(100),
		Quantity:  uint256.NewInt(10),
		Timestamp: time.Now().UnixNano(),
	}

	order2 := &types.Order{
		OrderID:   "order2",
		Price:     uint256.NewInt(110),
		Quantity:  uint256.NewInt(20),
		Timestamp: time.Now().UnixNano() + 1,
	}

	order3 := &types.Order{
		OrderID:   "order3",
		Price:     uint256.NewInt(105),
		Quantity:  uint256.NewInt(15),
		Timestamp: time.Now().UnixNano() + 2,
	}

	q.AddOrder(order1)
	q.AddOrder(order2)
	q.AddOrder(order3)

	// Get sorted orders
	sorted := q.GetOrdersSorted()
	require.Equal(t, 3, len(sorted))

	// Verify correct sorting (highest price first for buy queue)
	assert.Equal(t, "order2", string(sorted[0].OrderID))
	assert.Equal(t, uint256.NewInt(110), sorted[0].Price)

	assert.Equal(t, "order3", string(sorted[1].OrderID))
	assert.Equal(t, uint256.NewInt(105), sorted[1].Price)

	assert.Equal(t, "order1", string(sorted[2].OrderID))
	assert.Equal(t, uint256.NewInt(100), sorted[2].Price)

	// Original queue should remain unchanged
	assert.Equal(t, 3, q.Len())
}

func TestBuyQueue_HeapPropertyMaintained(t *testing.T) {
	q := NewBuyQueue()

	// Add many orders with random prices
	prices := []uint64{105, 95, 110, 100, 120, 85, 115, 90, 125, 80}
	for i, price := range prices {
		order := &types.Order{
			OrderID:   types.OrderID(string(rune('a' + i))),
			Price:     uint256.NewInt(price),
			Quantity:  uint256.NewInt(10),
			Timestamp: time.Now().UnixNano() + int64(i),
		}
		q.AddOrder(order)
	}

	// Remove all orders and verify they come out in correct order
	var lastPrice *uint256.Int
	for !q.IsEmpty() {
		order := q.RemoveTop()
		if lastPrice != nil {
			// Current price should be less than or equal to last price (max heap)
			assert.True(t, order.Price.Cmp(lastPrice) <= 0)
		}
		lastPrice = order.Price
	}
}

func TestBuyQueue_LargeScale(t *testing.T) {
	q := NewBuyQueue()

	// Add 1000 orders
	for i := 0; i < 1000; i++ {
		order := &types.Order{
			OrderID:   types.OrderID(fmt.Sprintf("order%d", i)),
			Price:     uint256.NewInt(uint64(1000 - i)), // Descending prices
			Quantity:  uint256.NewInt(10),
			Timestamp: time.Now().UnixNano() + int64(i),
		}
		q.AddOrder(order)
	}

	assert.Equal(t, 1000, q.Len())

	// Remove half
	for i := 0; i < 500; i++ {
		removed := q.RemoveTop()
		assert.NotNil(t, removed)
		// Should get orders with highest prices first
		assert.Equal(t, uint256.NewInt(uint64(1000-i)), removed.Price)
	}

	assert.Equal(t, 500, q.Len())

	// Clear remaining
	q.Clear()
	assert.True(t, q.IsEmpty())
}

func TestBuyQueue_EdgeCases(t *testing.T) {
	q := NewBuyQueue()

	// Test with nil price (should not panic)
	order := &types.Order{
		OrderID:   "order1",
		Price:     nil,
		Quantity:  uint256.NewInt(10),
		Timestamp: time.Now().UnixNano(),
	}
	q.AddOrder(order)
	assert.Equal(t, 1, q.Len())

	removed := q.RemoveTop()
	assert.Equal(t, "order1", string(removed.OrderID))

	// Test with zero quantity
	order = &types.Order{
		OrderID:   "order2",
		Price:     uint256.NewInt(100),
		Quantity:  uint256.NewInt(0),
		Timestamp: time.Now().UnixNano(),
	}
	q.AddOrder(order)
	assert.Equal(t, 1, q.Len())

	removed = q.RemoveTop()
	assert.Equal(t, "order2", string(removed.OrderID))
	assert.True(t, removed.Quantity.IsZero())
}

func BenchmarkBuyQueue_AddOrder(b *testing.B) {
	q := NewBuyQueue()
	orders := make([]*types.Order, b.N)
	for i := 0; i < b.N; i++ {
		orders[i] = &types.Order{
			OrderID:   types.OrderID(fmt.Sprintf("order%d", i)),
			Price:     uint256.NewInt(uint64(i)),
			Quantity:  uint256.NewInt(10),
			Timestamp: int64(i),
		}
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		q.AddOrder(orders[i])
	}
}

func BenchmarkBuyQueue_RemoveTop(b *testing.B) {
	q := NewBuyQueue()
	for i := 0; i < b.N; i++ {
		order := &types.Order{
			OrderID:   types.OrderID(fmt.Sprintf("order%d", i)),
			Price:     uint256.NewInt(uint64(i)),
			Quantity:  uint256.NewInt(10),
			Timestamp: int64(i),
		}
		q.AddOrder(order)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		q.RemoveTop()
	}
}