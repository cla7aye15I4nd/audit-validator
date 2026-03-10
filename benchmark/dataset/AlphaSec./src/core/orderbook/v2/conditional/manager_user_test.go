package conditional

import (
	"testing"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestManager_CancelUserOrders(t *testing.T) {
	manager := NewManager()

	// Track cancelled orders
	var cancelledInOrderbook []types.OrderID

	manager.SetOrderProcessor(func(order *types.Order) error {
		// Simulate adding to orderbook
		return nil
	})

	manager.SetOrderCanceller(func(orderID types.OrderID) error {
		cancelledInOrderbook = append(cancelledInOrderbook, orderID)
		return nil
	})

	// Add stop orders for different users
	stopOrder1 := &types.StopOrder{
		Order: &types.Order{
			OrderID:   "user1_stop1",
			UserID:    "user1",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     uint256.NewInt(2000),
			Quantity:  uint256.NewInt(1),
			OrigQty:   uint256.NewInt(1),
			Status:    types.TRIGGER_WAIT,
		},
		StopPrice:    uint256.NewInt(1950),
		TriggerAbove: false,
	}

	stopOrder2 := &types.StopOrder{
		Order: &types.Order{
			OrderID:   "user1_stop2",
			UserID:    "user1",
			Symbol:    "ETH/USDT",
			Side:      types.SELL,
			OrderType: types.LIMIT,
			Price:     uint256.NewInt(2100),
			Quantity:  uint256.NewInt(1),
			OrigQty:   uint256.NewInt(1),
			Status:    types.TRIGGER_WAIT,
		},
		StopPrice:    uint256.NewInt(2050),
		TriggerAbove: true,
	}

	stopOrder3 := &types.StopOrder{
		Order: &types.Order{
			OrderID:   "user2_stop1",
			UserID:    "user2",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     uint256.NewInt(2000),
			Quantity:  uint256.NewInt(1),
			OrigQty:   uint256.NewInt(1),
			Status:    types.TRIGGER_WAIT,
		},
		StopPrice:    uint256.NewInt(1950),
		TriggerAbove: false,
	}

	// Add all stop orders
	require.NoError(t, manager.AddStopOrder(stopOrder1))
	require.NoError(t, manager.AddStopOrder(stopOrder2))
	require.NoError(t, manager.AddStopOrder(stopOrder3))

	// Cancel all orders for user1
	cancelled := manager.CancelUserOrders("user1")

	// Should have cancelled 2 orders (user1's stop orders)
	assert.Len(t, cancelled, 2)
	assert.Contains(t, cancelled, types.OrderID("user1_stop1"))
	assert.Contains(t, cancelled, types.OrderID("user1_stop2"))

	// Verify user2's order is still active
	triggered, _ := manager.CheckTriggers(uint256.NewInt(1900))
	assert.Len(t, triggered, 1)
	assert.Equal(t, "user2_stop1", string(triggered[0].OrderID))
}

func TestManager_CancelUserOrders_WithTPSL(t *testing.T) {
	manager := NewManager()

	var orderbookOrders []*types.Order
	var cancelledInOrderbook []types.OrderID

	manager.SetOrderProcessor(func(order *types.Order) error {
		orderbookOrders = append(orderbookOrders, order)
		return nil
	})

	manager.SetOrderCanceller(func(orderID types.OrderID) error {
		cancelledInOrderbook = append(cancelledInOrderbook, orderID)
		return nil
	})

	// Create TPSL for user1
	filledOrder := &types.Order{
		OrderID:   "user1_order1",
		UserID:    "user1",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		OrderType: types.LIMIT,
		Price:     uint256.NewInt(2000),
		Quantity:  uint256.NewInt(1),
		OrigQty:   uint256.NewInt(1),
		Status:    types.FILLED,
		TPSL: &types.TPSLContext{
			TPLimitPrice:   uint256.NewInt(2200),
			SLTriggerPrice: uint256.NewInt(1900),
			SLLimitPrice:   uint256.NewInt(1890),
		},
	}

	// Activate TPSL
	err := manager.CreateTPSLForFilledOrder(filledOrder)
	require.NoError(t, err)

	// Verify TP order was created
	assert.Len(t, orderbookOrders, 1)
	tpOrderID := orderbookOrders[0].OrderID

	// Add a regular stop order for user1
	stopOrder := &types.StopOrder{
		Order: &types.Order{
			OrderID:   "user1_stop1",
			UserID:    "user1",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     uint256.NewInt(2050),
			Quantity:  uint256.NewInt(1),
			OrigQty:   uint256.NewInt(1),
			Status:    types.TRIGGER_WAIT,
		},
		StopPrice:    uint256.NewInt(2030),
		TriggerAbove: true,
	}
	require.NoError(t, manager.AddStopOrder(stopOrder))

	// Cancel all orders for user1
	cancelled := manager.CancelUserOrders("user1")

	// Should have cancelled: SL (conditional), stop order, and possibly TP via OCO
	// The exact count depends on OCO implementation
	assert.GreaterOrEqual(t, len(cancelled), 2) // At least SL and stop order

	// SL order ID should be in cancelled list
	slOrderID := types.GenerateSLOrderID("user1_order1")
	assert.Contains(t, cancelled, slOrderID)

	// Stop order should be cancelled
	assert.Contains(t, cancelled, types.OrderID("user1_stop1"))

	// Note: TP order cancellation would be handled by SymbolEngine
	// as it's in the orderbook, not in conditional manager
	t.Logf("Cancelled orders: %v", cancelled)
	t.Logf("TP order ID: %v (should be cancelled by SymbolEngine)", tpOrderID)
}
