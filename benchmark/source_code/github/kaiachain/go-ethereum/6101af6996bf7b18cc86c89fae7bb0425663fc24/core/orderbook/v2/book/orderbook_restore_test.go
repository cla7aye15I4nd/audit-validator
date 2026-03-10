package book

import (
	"testing"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestOrderBook_RestoreUserOrders(t *testing.T) {
	// Create orderbook
	ob := NewOrderBook(types.Symbol("ETH/USDT"))
	
	// Create test orders from different users
	user1 := types.UserID("user1")
	user2 := types.UserID("user2")
	
	order1 := &types.Order{
		OrderID:   types.OrderID("order1"),
		UserID:    user1,
		Symbol:    types.Symbol("ETH/USDT"),
		OrderType: types.LIMIT,
		Side:      types.BUY,
		Price:     types.NewPrice(1000), // $10.00
		Quantity:  types.NewQuantity(100), // 1.00
		OrigQty:   types.NewQuantity(100),
		Status:    types.PENDING,
	}
	
	order2 := &types.Order{
		OrderID:   types.OrderID("order2"),
		UserID:    user1,
		Symbol:    types.Symbol("ETH/USDT"),
		OrderType: types.LIMIT,
		Side:      types.SELL,
		Price:     types.NewPrice(1100), // $11.00
		Quantity:  types.NewQuantity(150), // 1.50
		OrigQty:   types.NewQuantity(150),
		Status:    types.PENDING,
	}
	
	order3 := &types.Order{
		OrderID:   types.OrderID("order3"),
		UserID:    user2,
		Symbol:    types.Symbol("ETH/USDT"),
		OrderType: types.LIMIT,
		Side:      types.BUY,
		Price:     types.NewPrice(950), // $9.50
		Quantity:  types.NewQuantity(200), // 2.00
		OrigQty:   types.NewQuantity(200),
		Status:    types.PENDING,
	}
	
	// Add orders
	require.NoError(t, ob.AddOrder(order1))
	require.NoError(t, ob.AddOrder(order2))
	require.NoError(t, ob.AddOrder(order3))
	
	// Verify userOrders is populated
	user1Orders := ob.GetUserOrders(user1)
	assert.Len(t, user1Orders, 2, "User1 should have 2 orders")
	// Check order IDs
	user1OrderIDs := make([]types.OrderID, 0, len(user1Orders))
	for _, o := range user1Orders {
		user1OrderIDs = append(user1OrderIDs, o.OrderID)
	}
	assert.Contains(t, user1OrderIDs, types.OrderID("order1"))
	assert.Contains(t, user1OrderIDs, types.OrderID("order2"))
	
	user2Orders := ob.GetUserOrders(user2)
	assert.Len(t, user2Orders, 1, "User2 should have 1 order")
	// Check order IDs
	user2OrderIDs := make([]types.OrderID, 0, len(user2Orders))
	for _, o := range user2Orders {
		user2OrderIDs = append(user2OrderIDs, o.OrderID)
	}
	assert.Contains(t, user2OrderIDs, types.OrderID("order3"))
	
	// Get all orders (simulating snapshot)
	allOrders := ob.GetAllOrders()
	assert.Len(t, allOrders, 3, "Should have 3 orders total")
	
	// Create new orderbook (simulating recovery)
	ob2 := NewOrderBook(types.Symbol("ETH/USDT"))
	
	// Restore orders (simulating recovery from snapshot)
	for _, order := range allOrders {
		require.NoError(t, ob2.AddOrder(order))
	}
	
	// Verify userOrders is properly rebuilt
	user1OrdersRestored := ob2.GetUserOrders(user1)
	assert.Len(t, user1OrdersRestored, 2, "Restored User1 should have 2 orders")
	// Check order IDs
	user1OrderIDsRestored := make([]types.OrderID, 0, len(user1OrdersRestored))
	for _, o := range user1OrdersRestored {
		user1OrderIDsRestored = append(user1OrderIDsRestored, o.OrderID)
	}
	assert.Contains(t, user1OrderIDsRestored, types.OrderID("order1"))
	assert.Contains(t, user1OrderIDsRestored, types.OrderID("order2"))
	
	user2OrdersRestored := ob2.GetUserOrders(user2)
	assert.Len(t, user2OrdersRestored, 1, "Restored User2 should have 1 order")
	// Check order IDs
	user2OrderIDsRestored := make([]types.OrderID, 0, len(user2OrdersRestored))
	for _, o := range user2OrdersRestored {
		user2OrderIDsRestored = append(user2OrderIDsRestored, o.OrderID)
	}
	assert.Contains(t, user2OrderIDsRestored, types.OrderID("order3"))
	
	// Verify order queues are also rebuilt
	buyOrders := ob2.GetBuyOrders()
	assert.Len(t, buyOrders, 2, "Should have 2 buy orders")
	
	sellOrders := ob2.GetSellOrders()
	assert.Len(t, sellOrders, 1, "Should have 1 sell order")
}