package book

import (
	"testing"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestOrderBook_Level2_GetDiff_Basic(t *testing.T) {
	ob := NewOrderBook("KAIA/USDT")

	// Add initial orders
	order1 := &types.Order{
		OrderID:  "order1",
		UserID:   "user1",
		Symbol:   "KAIA/USDT",
		Side:     types.BUY,
		Price:    types.MustParsePrice("100.0"),
		Quantity: types.MustParseQuantity("10.0"),
		OrigQty:  types.MustParseQuantity("10.0"),
	}

	order2 := &types.Order{
		OrderID:  "order2",
		UserID:   "user1",
		Symbol:   "KAIA/USDT",
		Side:     types.BUY,
		Price:    types.MustParsePrice("99.0"),
		Quantity: types.MustParseQuantity("5.0"),
		OrigQty:  types.MustParseQuantity("5.0"),
	}

	order3 := &types.Order{
		OrderID:  "order3",
		UserID:   "user2",
		Symbol:   "KAIA/USDT",
		Side:     types.SELL,
		Price:    types.MustParsePrice("101.0"),
		Quantity: types.MustParseQuantity("7.0"),
		OrigQty:  types.MustParseQuantity("7.0"),
	}

	// Add orders - this should mark prices as dirty
	require.NoError(t, ob.AddOrder(order1))
	require.NoError(t, ob.AddOrder(order2))
	require.NoError(t, ob.AddOrder(order3))

	// Get diff - should return all changed prices
	bidDiff, askDiff := ob.GetLevel2Diff()

	// Check bid diff
	assert.Len(t, bidDiff, 2, "Should have 2 bid changes")
	// Bids should be sorted descending (higher price first)
	assert.Equal(t, "100", bidDiff[0][0], "First bid price")
	assert.Equal(t, "10", bidDiff[0][1], "First bid quantity")
	assert.Equal(t, "99", bidDiff[1][0], "Second bid price")
	assert.Equal(t, "5", bidDiff[1][1], "Second bid quantity")

	// Check ask diff
	assert.Len(t, askDiff, 1, "Should have 1 ask change")
	assert.Equal(t, "101", askDiff[0][0], "Ask price")
	assert.Equal(t, "7", askDiff[0][1], "Ask quantity")

	// Get diff again - should be empty (dirty flags reset)
	bidDiff2, askDiff2 := ob.GetLevel2Diff()
	assert.Empty(t, bidDiff2, "Bid diff should be empty after reset")
	assert.Empty(t, askDiff2, "Ask diff should be empty after reset")
}

func TestOrderBook_Level2_GetDiff_PriceAggregation(t *testing.T) {
	ob := NewOrderBook("KAIA/USDT")

	// Add multiple orders at same price
	order1 := &types.Order{
		OrderID:  "order1",
		UserID:   "user1",
		Symbol:   "KAIA/USDT",
		Side:     types.BUY,
		Price:    types.MustParsePrice("100.0"),
		Quantity: types.MustParseQuantity("10.0"),
		OrigQty:  types.MustParseQuantity("10.0"),
	}

	order2 := &types.Order{
		OrderID:  "order2",
		UserID:   "user2",
		Symbol:   "KAIA/USDT",
		Side:     types.BUY,
		Price:    types.MustParsePrice("100.0"), // Same price
		Quantity: types.MustParseQuantity("15.0"),
		OrigQty:  types.MustParseQuantity("15.0"),
	}

	require.NoError(t, ob.AddOrder(order1))
	require.NoError(t, ob.AddOrder(order2))

	// Get diff
	bidDiff, _ := ob.GetLevel2Diff()

	// Should have aggregated quantity at price 100
	assert.Len(t, bidDiff, 1, "Should have 1 price level")
	assert.Equal(t, "100", bidDiff[0][0], "Price")
	assert.Equal(t, "25", bidDiff[0][1], "Aggregated quantity (10+15)")
}

func TestOrderBook_Level2_GetDiff_RemoveOrder(t *testing.T) {
	ob := NewOrderBook("KAIA/USDT")

	// Add orders
	order1 := &types.Order{
		OrderID:  "order1",
		UserID:   "user1",
		Symbol:   "KAIA/USDT",
		Side:     types.BUY,
		Price:    types.MustParsePrice("100.0"),
		Quantity: types.MustParseQuantity("10.0"),
		OrigQty:  types.MustParseQuantity("10.0"),
	}

	order2 := &types.Order{
		OrderID:  "order2",
		UserID:   "user2",
		Symbol:   "KAIA/USDT",
		Side:     types.BUY,
		Price:    types.MustParsePrice("100.0"),
		Quantity: types.MustParseQuantity("5.0"),
		OrigQty:  types.MustParseQuantity("5.0"),
	}

	require.NoError(t, ob.AddOrder(order1))
	require.NoError(t, ob.AddOrder(order2))

	// Clear diff
	ob.GetLevel2Diff()

	// Remove one order - should update the price level
	require.NoError(t, ob.RemoveOrder("order1"))

	bidDiff, _ := ob.GetLevel2Diff()
	assert.Len(t, bidDiff, 1, "Should have 1 change")
	assert.Equal(t, "100", bidDiff[0][0], "Price")
	assert.Equal(t, "5", bidDiff[0][1], "Remaining quantity after removal")

	// Remove last order at this price - should send 0 quantity
	require.NoError(t, ob.RemoveOrder("order2"))

	bidDiff, _ = ob.GetLevel2Diff()
	assert.Len(t, bidDiff, 1, "Should have 1 change")
	assert.Equal(t, "100", bidDiff[0][0], "Price")
	assert.Equal(t, "0", bidDiff[0][1], "Quantity should be 0 (price level removed)")
}

func TestOrderBook_Level2_GetSnapshot(t *testing.T) {
	ob := NewOrderBook("KAIA/USDT")

	// Add orders at various prices
	orders := []*types.Order{
		{
			OrderID:  "b1",
			UserID:   "user1",
			Symbol:   "KAIA/USDT",
			Side:     types.BUY,
			Price:    types.MustParsePrice("100.0"),
			Quantity: types.MustParseQuantity("10.0"),
			OrigQty:  types.MustParseQuantity("10.0"),
		},
		{
			OrderID:  "b2",
			UserID:   "user1",
			Symbol:   "KAIA/USDT",
			Side:     types.BUY,
			Price:    types.MustParsePrice("99.5"),
			Quantity: types.MustParseQuantity("20.0"),
			OrigQty:  types.MustParseQuantity("20.0"),
		},
		{
			OrderID:  "b3",
			UserID:   "user1",
			Symbol:   "KAIA/USDT",
			Side:     types.BUY,
			Price:    types.MustParsePrice("99.0"),
			Quantity: types.MustParseQuantity("15.0"),
			OrigQty:  types.MustParseQuantity("15.0"),
		},
		{
			OrderID:  "s1",
			UserID:   "user2",
			Symbol:   "KAIA/USDT",
			Side:     types.SELL,
			Price:    types.MustParsePrice("101.0"),
			Quantity: types.MustParseQuantity("8.0"),
			OrigQty:  types.MustParseQuantity("8.0"),
		},
		{
			OrderID:  "s2",
			UserID:   "user2",
			Symbol:   "KAIA/USDT",
			Side:     types.SELL,
			Price:    types.MustParsePrice("101.5"),
			Quantity: types.MustParseQuantity("12.0"),
			OrigQty:  types.MustParseQuantity("12.0"),
		},
	}

	for _, order := range orders {
		require.NoError(t, ob.AddOrder(order))
	}

	// Get snapshot
	snapshot := ob.GetLevel2Snapshot()

	// Check snapshot structure
	assert.Equal(t, "KAIA/USDT", snapshot.Symbol)
	assert.Len(t, snapshot.Bids, 3, "Should have 3 bid levels")
	assert.Len(t, snapshot.Asks, 2, "Should have 2 ask levels")

	// Check bid ordering (descending)
	assert.Equal(t, "100", snapshot.Bids[0][0])
	assert.Equal(t, "10", snapshot.Bids[0][1])
	assert.Equal(t, "99.5", snapshot.Bids[1][0])
	assert.Equal(t, "20", snapshot.Bids[1][1])
	assert.Equal(t, "99", snapshot.Bids[2][0])
	assert.Equal(t, "15", snapshot.Bids[2][1])

	// Check ask ordering (ascending)
	assert.Equal(t, "101", snapshot.Asks[0][0])
	assert.Equal(t, "8", snapshot.Asks[0][1])
	assert.Equal(t, "101.5", snapshot.Asks[1][0])
	assert.Equal(t, "12", snapshot.Asks[1][1])
}

func TestOrderBook_Level2_DirtyReset(t *testing.T) {
	ob := NewOrderBook("KAIA/USDT")

	// Simulate Block 1
	order1 := &types.Order{
		OrderID:  "order1",
		UserID:   "user1",
		Symbol:   "KAIA/USDT",
		Side:     types.BUY,
		Price:    types.MustParsePrice("100.0"),
		Quantity: types.MustParseQuantity("10.0"),
		OrigQty:  types.MustParseQuantity("10.0"),
	}
	require.NoError(t, ob.AddOrder(order1))

	// Get diff for Block 1
	bidDiff1, _ := ob.GetLevel2Diff()
	assert.Len(t, bidDiff1, 1, "Block 1 should have 1 change")
	assert.Equal(t, "100", bidDiff1[0][0])
	assert.Equal(t, "10", bidDiff1[0][1])

	// Simulate Block 2 - add another order at different price
	order2 := &types.Order{
		OrderID:  "order2",
		UserID:   "user1",
		Symbol:   "KAIA/USDT",
		Side:     types.BUY,
		Price:    types.MustParsePrice("99.0"),
		Quantity: types.MustParseQuantity("5.0"),
		OrigQty:  types.MustParseQuantity("5.0"),
	}
	require.NoError(t, ob.AddOrder(order2))

	// Get diff for Block 2 - should only show new change
	bidDiff2, _ := ob.GetLevel2Diff()
	assert.Len(t, bidDiff2, 1, "Block 2 should have 1 change")
	assert.Equal(t, "99", bidDiff2[0][0], "Only new price")
	assert.Equal(t, "5", bidDiff2[0][1])

	// Simulate Block 3 - modify existing price
	order3 := &types.Order{
		OrderID:  "order3",
		UserID:   "user1",
		Symbol:   "KAIA/USDT",
		Side:     types.BUY,
		Price:    types.MustParsePrice("100.0"), // Same as order1
		Quantity: types.MustParseQuantity("15.0"),
		OrigQty:  types.MustParseQuantity("15.0"),
	}
	require.NoError(t, ob.AddOrder(order3))

	// Get diff for Block 3 - should only show modified price
	bidDiff3, _ := ob.GetLevel2Diff()
	assert.Len(t, bidDiff3, 1, "Block 3 should have 1 change")
	assert.Equal(t, "100", bidDiff3[0][0])
	assert.Equal(t, "25", bidDiff3[0][1], "Updated total (10+15)")
}

func TestOrderBook_Level2_CompleteRemoval(t *testing.T) {
	ob := NewOrderBook("KAIA/USDT")

	// Add single order
	order := &types.Order{
		OrderID:  "order1",
		UserID:   "user1",
		Symbol:   "KAIA/USDT",
		Side:     types.SELL,
		Price:    types.MustParsePrice("101.0"),
		Quantity: types.MustParseQuantity("10.0"),
		OrigQty:  types.MustParseQuantity("10.0"),
	}
	require.NoError(t, ob.AddOrder(order))

	// Clear initial diff
	ob.GetLevel2Diff()

	// Remove the order - price level should be completely removed
	require.NoError(t, ob.RemoveOrder("order1"))

	// Get diff - should show quantity 0 for removed price
	_, askDiff := ob.GetLevel2Diff()
	assert.Len(t, askDiff, 1)
	assert.Equal(t, "101", askDiff[0][0], "Removed price")
	assert.Equal(t, "0", askDiff[0][1], "Quantity 0 means price level removed")

	// Snapshot should not include removed price
	snapshot := ob.GetLevel2Snapshot()
	assert.Empty(t, snapshot.Asks, "Snapshot should have no asks after removal")
}

func TestOrderBook_Level2_EmptyBook(t *testing.T) {
	ob := NewOrderBook("KAIA/USDT")

	// Get diff from empty book
	bidDiff, askDiff := ob.GetLevel2Diff()
	assert.Empty(t, bidDiff, "Empty book should have no bid diff")
	assert.Empty(t, askDiff, "Empty book should have no ask diff")

	// Get snapshot from empty book
	snapshot := ob.GetLevel2Snapshot()
	assert.Equal(t, "KAIA/USDT", snapshot.Symbol)
	assert.Empty(t, snapshot.Bids, "Empty book should have no bids")
	assert.Empty(t, snapshot.Asks, "Empty book should have no asks")
}

func TestOrderBook_Level2_PartialFill(t *testing.T) {
	ob := NewOrderBook("KAIA/USDT")

	// Add initial order
	order := &types.Order{
		OrderID:  "order1",
		UserID:   "user1",
		Symbol:   "KAIA/USDT",
		Side:     types.BUY,
		Price:    types.MustParsePrice("100.0"),
		Quantity: types.MustParseQuantity("10.0"),
		OrigQty:  types.MustParseQuantity("10.0"),
	}
	require.NoError(t, ob.AddOrder(order))

	// Clear initial diff
	ob.GetLevel2Diff()

	// Simulate partial fill by modifying the order directly and re-adding
	// (In real usage, the matcher would handle this)
	require.NoError(t, ob.RemoveOrder("order1"))
	order.Quantity = types.MustParseQuantity("7.0") // Simulate 3 filled
	require.NoError(t, ob.AddOrder(order))

	// Get diff - should show updated quantity
	bidDiff, _ := ob.GetLevel2Diff()
	assert.Len(t, bidDiff, 1)
	assert.Equal(t, "100", bidDiff[0][0])
	assert.Equal(t, "7", bidDiff[0][1], "Quantity reduced to 7")
}

func TestOrderBook_Level2_MixedOperations(t *testing.T) {
	ob := NewOrderBook("KAIA/USDT")

	// Block 1: Add initial orders
	orders := []*types.Order{
		{
			OrderID:  "b1",
			UserID:   "user1",
			Symbol:   "KAIA/USDT",
			Side:     types.BUY,
			Price:    types.MustParsePrice("100.0"),
			Quantity: types.MustParseQuantity("10.0"),
			OrigQty:  types.MustParseQuantity("10.0"),
		},
		{
			OrderID:  "b2",
			UserID:   "user1",
			Symbol:   "KAIA/USDT",
			Side:     types.BUY,
			Price:    types.MustParsePrice("99.0"),
			Quantity: types.MustParseQuantity("20.0"),
			OrigQty:  types.MustParseQuantity("20.0"),
		},
		{
			OrderID:  "s1",
			UserID:   "user2",
			Symbol:   "KAIA/USDT",
			Side:     types.SELL,
			Price:    types.MustParsePrice("101.0"),
			Quantity: types.MustParseQuantity("15.0"),
			OrigQty:  types.MustParseQuantity("15.0"),
		},
	}

	for _, order := range orders {
		require.NoError(t, ob.AddOrder(order))
	}

	bidDiff, askDiff := ob.GetLevel2Diff()
	assert.Len(t, bidDiff, 2, "Initial bid changes")
	assert.Len(t, askDiff, 1, "Initial ask changes")

	// Block 2: Mixed operations
	// 1. Add new order at existing price
	newOrder := &types.Order{
		OrderID:  "b3",
		UserID:   "user3",
		Symbol:   "KAIA/USDT",
		Side:     types.BUY,
		Price:    types.MustParsePrice("100.0"),
		Quantity: types.MustParseQuantity("5.0"),
		OrigQty:  types.MustParseQuantity("5.0"),
	}
	require.NoError(t, ob.AddOrder(newOrder))

	// 2. Remove order from different price
	require.NoError(t, ob.RemoveOrder("b2"))

	// 3. Simulate partial fill on sell side
	require.NoError(t, ob.RemoveOrder("s1"))
	orders[2].Quantity = types.MustParseQuantity("10.0") // Reduced from 15
	require.NoError(t, ob.AddOrder(orders[2]))

	// Get diff for Block 2
	bidDiff, askDiff = ob.GetLevel2Diff()
	
	// Check bid changes
	assert.Len(t, bidDiff, 2, "Two bid prices changed")
	// Find the changes
	var change100, change99 []string
	for _, change := range bidDiff {
		if change[0] == "100" {
			change100 = change
		} else if change[0] == "99" {
			change99 = change
		}
	}
	assert.Equal(t, "15", change100[1], "Price 100: 10+5")
	assert.Equal(t, "0", change99[1], "Price 99: removed")

	// Check ask changes
	assert.Len(t, askDiff, 1, "One ask price changed")
	assert.Equal(t, "101", askDiff[0][0])
	assert.Equal(t, "10", askDiff[0][1], "Quantity reduced from 15 to 10")

	// Final snapshot check
	snapshot := ob.GetLevel2Snapshot()
	assert.Len(t, snapshot.Bids, 1, "Only 1 bid price remains")
	assert.Equal(t, "100", snapshot.Bids[0][0])
	assert.Equal(t, "15", snapshot.Bids[0][1])
	assert.Len(t, snapshot.Asks, 1, "1 ask price")
	assert.Equal(t, "101", snapshot.Asks[0][0])
	assert.Equal(t, "10", snapshot.Asks[0][1])
}