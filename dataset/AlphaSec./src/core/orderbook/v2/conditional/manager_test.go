package conditional

import (
	"slices"
	"testing"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestManager_TPSL_Flow(t *testing.T) {
	// Create manager
	manager := NewManager()

	// Track orders that go to orderbook
	var orderbookOrders []*types.Order
	var cancelledOrders []types.OrderID

	manager.SetOrderProcessor(func(order *types.Order) error {
		orderbookOrders = append(orderbookOrders, order)
		return nil
	})

	manager.SetOrderCanceller(func(orderID types.OrderID) error {
		cancelledOrders = append(cancelledOrders, orderID)
		return nil
	})

	// Create a filled BUY order with TPSL
	originalOrder := &types.Order{
		OrderID:   "order_1",
		UserID:    "user_1",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		OrderType: types.LIMIT,
		Price:     uint256.NewInt(2000), // Bought at 2000
		Quantity:  uint256.NewInt(1),
		OrigQty:   uint256.NewInt(1),
		Status:    types.FILLED,
		TPSL: &types.TPSLContext{
			TPLimitPrice:   uint256.NewInt(2200), // Take profit at 2200
			SLTriggerPrice: uint256.NewInt(1900), // Stop loss triggers at 1900
			SLLimitPrice:   uint256.NewInt(1890), // Stop loss executes at 1890
		},
	}

	// Activate TPSL for the filled order
	err := manager.CreateTPSLForFilledOrder(originalOrder)
	require.NoError(t, err)

	// Verify TP order was sent to orderbook
	assert.Len(t, orderbookOrders, 1)
	tpOrder := orderbookOrders[0]
	assert.Equal(t, types.SELL, tpOrder.Side) // Opposite side
	assert.Equal(t, uint256.NewInt(2200), tpOrder.Price)
	assert.Equal(t, types.NEW, tpOrder.Status)

	// Test 1: Price rises but not enough to trigger SL
	triggered, toCancel := manager.CheckTriggers(uint256.NewInt(2100))
	assert.Len(t, triggered, 0)
	assert.Len(t, toCancel, 0)

	// Test 2: Price falls to trigger SL
	triggered, returnedCancelled := manager.CheckTriggers(uint256.NewInt(1900))
	assert.Len(t, triggered, 1)
	assert.Len(t, returnedCancelled, 1) // TP order should be cancelled (OCO)

	// Verify SL order details
	slOrder := triggered[0]
	assert.Equal(t, types.SELL, slOrder.Side)
	assert.Equal(t, uint256.NewInt(1890), slOrder.Price)
	assert.Equal(t, types.TRIGGERED, slOrder.Status)

	// Verify TP order was cancelled via callback
	assert.Contains(t, cancelledOrders, tpOrder.OrderID)
	assert.Equal(t, tpOrder.OrderID, returnedCancelled[0])
}

func TestManager_StopOrder(t *testing.T) {
	manager := NewManager()

	// Create a stop order
	stopOrder := &types.StopOrder{
		Order: &types.Order{
			OrderID:   "stop_1",
			UserID:    "user_1",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     uint256.NewInt(2100),
			Quantity:  uint256.NewInt(1),
			OrigQty:   uint256.NewInt(1),
			Status:    types.TRIGGER_WAIT,
		},
		StopPrice:    uint256.NewInt(2050), // Trigger when price >= 2050
		TriggerAbove: true,
		Status:       types.TRIGGER_WAIT,
	}

	// Add stop order
	err := manager.AddStopOrder(stopOrder)
	require.NoError(t, err)

	// Check triggers below stop price
	triggered, _ := manager.CheckTriggers(uint256.NewInt(2000))
	assert.Len(t, triggered, 0)

	// Check triggers at stop price
	triggered, _ = manager.CheckTriggers(uint256.NewInt(2050))
	assert.Len(t, triggered, 1)
	assert.Equal(t, "stop_1", string(triggered[0].OrderID))
}

func TestManager_CancelOrder(t *testing.T) {
	manager := NewManager()

	// Add a stop order
	stopOrder := &types.StopOrder{
		Order: &types.Order{
			OrderID:   "stop_1",
			UserID:    "user_1",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     uint256.NewInt(2100),
			Quantity:  uint256.NewInt(1),
			OrigQty:   uint256.NewInt(1),
			Status:    types.TRIGGER_WAIT,
		},
		StopPrice:    uint256.NewInt(2050),
		TriggerAbove: true,
		Status:       types.TRIGGER_WAIT,
	}

	err := manager.AddStopOrder(stopOrder)
	require.NoError(t, err)

	// Cancel the order
	cancelled, cancelledIds := manager.CancelOrder("stop_1")
	assert.True(t, cancelled)
	assert.True(t, cancelledIds[0] == stopOrder.Order.OrderID)

	// Verify it's no longer triggered
	triggered, _ := manager.CheckTriggers(uint256.NewInt(2050))
	assert.Len(t, triggered, 0)
}

func TestManager_OCO_Behavior(t *testing.T) {
	manager := NewManager()

	var orderbookOrders []*types.Order
	var cancelledOrdersViaCallback []types.OrderID

	manager.SetOrderProcessor(func(order *types.Order) error {
		// Simulate orderbook accepting the order
		orderbookOrders = append(orderbookOrders, order)
		return nil
	})

	manager.SetOrderCanceller(func(orderID types.OrderID) error {
		cancelledOrdersViaCallback = append(cancelledOrdersViaCallback, orderID)
		return nil
	})

	// Create and activate TPSL
	originalOrder := &types.Order{
		OrderID:   "order_1",
		UserID:    "user_1",
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

	err := manager.CreateTPSLForFilledOrder(originalOrder)
	require.NoError(t, err)

	// Verify TPSL was created
	assert.Len(t, orderbookOrders, 1, "TP order should be in orderbook")
	assert.Equal(t, types.GenerateTPOrderID("order_1"), orderbookOrders[0].OrderID)

	// Now simulate TP order being partially filled (after TPSL is fully created)
	tpOrderID := types.GenerateTPOrderID("order_1")
	slOrderID := types.GenerateSLOrderID("order_1")

	// Call HandleOrderFill to simulate partial fill
	cancelledOrders := manager.HandleOrderFill(tpOrderID)

	// Verify SL was cancelled due to TP partial fill (OCO)
	assert.Len(t, cancelledOrders, 1, "Should cancel one order (SL)")
	assert.Equal(t, slOrderID, cancelledOrders[0], "Should cancel SL order")

	// Verify OCO behavior with manual cancellation (OneCancelsOther strategy)
	// Create another TPSL to test manual cancellation
	manager2 := NewManager()
	cancelledOrdersViaCallback = nil
	orderbookOrders = nil
	manager2.SetOrderProcessor(func(order *types.Order) error {
		orderbookOrders = append(orderbookOrders, order)
		return nil
	})
	manager2.SetOrderCanceller(func(orderID types.OrderID) error {
		cancelledOrdersViaCallback = append(cancelledOrdersViaCallback, orderID)
		return nil
	})

	originalOrder2 := &types.Order{
		OrderID:   "order_2",
		UserID:    "user_2",
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

	err = manager2.CreateTPSLForFilledOrder(originalOrder2)
	require.NoError(t, err)

	// Manually cancel the TP order (not a fill)
	tpOrderID2 := types.GenerateTPOrderID("order_2")
	slOrderID2 := types.GenerateSLOrderID("order_2")

	// With OneCancelsOther strategy, manual cancel should also trigger OCO
	cancelled, cancelledIds := manager2.CancelOrder(tpOrderID2)
	assert.True(t, cancelled, "TP order should be tracked in OCO")
	assert.True(t, slices.Contains(cancelledIds, tpOrderID2))
	assert.True(t, slices.Contains(cancelledIds, slOrderID2))
	assert.Equal(t, cancelledOrdersViaCallback[0], tpOrderID2)

	// Check if SL trigger still exists
	_, slExists := manager2.triggerManager.GetTrigger(slOrderID2)
	assert.False(t, slExists, "SL should be removed due to OCO (OneCancelsOther strategy)")
}
