package engine

import (
	"fmt"
	"math/rand"
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ============================================================
// Test Helper Functions
// ============================================================

// Helper to scale a uint64 to 18 decimals
func scale18(n uint64) *uint256.Int {
	return new(uint256.Int).Mul(uint256.NewInt(n), uint256.NewInt(1e18))
}

// mockBalanceManager implements the balance manager interface needed by SymbolEngine
type mockBalanceManager struct{}

func (m *mockBalanceManager) Lock(orderID string, user common.Address, token string, amount *uint256.Int) error {
	return nil
}

func (m *mockBalanceManager) GetLock(orderID string) (*types.LockInfo, bool) {
	return nil, false
}

func (m *mockBalanceManager) RegisterTPSLAlias(originalOrderID types.OrderID) {
	// Mock implementation
}

func (m *mockBalanceManager) Unlock(orderID string) error {
	return nil
}

func (m *mockBalanceManager) UpdateLockForTriggeredMarketOrder(order *types.Order) error {
	return nil
}

// Helper function to create a test engine
func createTestEngine() *SymbolEngine {
	mockBM := &mockBalanceManager{}
	engine := NewSymbolEngine("ETH/USDT", mockBM)
	engine.SetBlockContext(1000)
	return engine
}

// Helper to create a limit order
func createLimitOrder(orderID, userID string, side types.OrderSide, price, qty uint64) *types.Order {
	// Scale price and quantity to 18 decimals
	scaledPrice := scale18(price)
	scaledQty := scale18(qty)

	return &types.Order{
		OrderID:   types.OrderID(orderID),
		UserID:    types.UserID(userID),
		Symbol:    "ETH/USDT",
		OrderType: types.LIMIT,
		Side:      side,
		Price:     scaledPrice,
		Quantity:  scaledQty,
		OrigQty:   scaledQty,
		Status:    types.NEW,
		Timestamp: types.TimeNow(),
	}
}

// Helper to create a market order
func createMarketOrder(orderID, userID string, side types.OrderSide, qty uint64) *types.Order {
	// Scale quantity to 18 decimals
	scaledQty := scale18(qty)

	return &types.Order{
		OrderID:   types.OrderID(orderID),
		UserID:    types.UserID(userID),
		Symbol:    "ETH/USDT",
		OrderType: types.MARKET,
		Side:      side,
		Quantity:  scaledQty,
		OrigQty:   scaledQty,
		Status:    types.NEW,
		Timestamp: types.TimeNow(),
	}
}

// Helper to create an order with TPSL
func createOrderWithTPSL(orderID, userID string, side types.OrderSide, price, qty, tpPrice, slTrigger, slLimit uint64) *types.Order {
	order := createLimitOrder(orderID, userID, side, price, qty)
	// Scale TPSL prices to 18 decimals
	order.TPSL = &types.TPSLContext{
		TPLimitPrice:   scale18(tpPrice),
		SLTriggerPrice: scale18(slTrigger),
		SLLimitPrice:   scale18(slLimit),
	}
	return order
}

// Helper to create a stop order
func createStopOrder(orderID, userID string, side types.OrderSide, limitPrice, triggerPrice uint64, triggerAbove bool) *types.StopOrder {
	// Scale all prices and quantities to 18 decimals
	scaledQty := scale18(10)

	return &types.StopOrder{
		Order: &types.Order{
			OrderID:   types.OrderID(orderID),
			UserID:    types.UserID(userID),
			Symbol:    "ETH/USDT",
			OrderType: types.STOP_LIMIT,
			Side:      side,
			Price:     scale18(limitPrice),
			Quantity:  scaledQty,
			OrigQty:   scaledQty,
			Status:    types.TRIGGER_WAIT,
			Timestamp: types.TimeNow(),
		},
		StopPrice:    scale18(triggerPrice),
		TriggerAbove: triggerAbove,
	}
}

// Helper to assert order exists in orderbook
func assertOrderInBook(t *testing.T, engine *SymbolEngine, orderID string) {
	order, exists := engine.orderBook.GetOrder(types.OrderID(orderID))
	assert.True(t, exists, "Order %s should exist in orderbook", orderID)
	assert.NotNil(t, order)
}

// Helper to assert order doesn't exist in orderbook
func assertOrderNotInBook(t *testing.T, engine *SymbolEngine, orderID string) {
	_, exists := engine.orderBook.GetOrder(types.OrderID(orderID))
	assert.False(t, exists, "Order %s should not exist in orderbook", orderID)
}

// ============================================================
// 1. Regular Order Tests
// ============================================================

func TestSymbolEngine_ProcessOrder_Basic(t *testing.T) {
	engine := createTestEngine()

	t.Run("Basic Limit Buy Order", func(t *testing.T) {
		buyOrder := createLimitOrder("buy1", "user1", types.BUY, 2000, 10)

		results, err := engine.ProcessOrder(buyOrder)
		require.NoError(t, err)
		require.Len(t, results, 1)

		result := results[0]
		assert.Equal(t, types.PENDING, result.Status)
		assert.Equal(t, scale18(0), result.FilledQuantity)

		assertOrderInBook(t, engine, "buy1")
	})

	t.Run("Basic Limit Sell Order", func(t *testing.T) {
		sellOrder := createLimitOrder("sell1", "user2", types.SELL, 3000, 5)

		results, err := engine.ProcessOrder(sellOrder)
		require.NoError(t, err)
		require.Len(t, results, 1)

		result := results[0]
		assert.Equal(t, types.PENDING, result.Status)

		assertOrderInBook(t, engine, "sell1")
	})

	t.Run("Matching Orders", func(t *testing.T) {

		engine.ProcessOrder(createLimitOrder("buy2", "user1", types.BUY, 2500, 10))

		// This sell order should match with existing buy order
		sellOrder := createLimitOrder("sell2", "user3", types.SELL, 2500, 8)

		results, err := engine.ProcessOrder(sellOrder)
		require.NoError(t, err)
		require.Len(t, results, 1)

		result := results[0]
		assert.Equal(t, types.FILLED, result.Status)
		assert.Equal(t, scale18(8), result.FilledQuantity)
		assert.Len(t, result.Trades, 1)

		// Check trade details
		trade := result.Trades[0]
		assert.Equal(t, scale18(2500), trade.Price)
		assert.Equal(t, scale18(8), trade.Quantity)

		// Original buy order should be partially filled
		buyOrder, exists := engine.orderBook.GetOrder("buy2")
		assert.True(t, exists)
		assert.Equal(t, scale18(2), buyOrder.Quantity) // 10 - 8 = 2
	})
}

func TestSymbolEngine_ProcessOrder_MarketOrder(t *testing.T) {
	engine := createTestEngine()

	// Setup orderbook with limit orders
	engine.ProcessOrder(createLimitOrder("sell1", "user1", types.SELL, 2010, 5))
	engine.ProcessOrder(createLimitOrder("sell2", "user2", types.SELL, 2020, 10))
	engine.ProcessOrder(createLimitOrder("buy1", "user3", types.BUY, 1990, 7))
	engine.ProcessOrder(createLimitOrder("buy2", "user4", types.BUY, 1980, 8))

	t.Run("Market Buy Order", func(t *testing.T) {
		marketBuy := createMarketOrder("market_buy1", "user5", types.BUY, 12)

		results, err := engine.ProcessOrder(marketBuy)
		require.NoError(t, err)
		require.Len(t, results, 1)

		result := results[0]
		assert.Equal(t, types.FILLED, result.Status)
		assert.Equal(t, scale18(12), result.FilledQuantity)

		// Should have consumed sell1 (5) and part of sell2 (7)
		assert.Len(t, result.Trades, 2)
		assert.Equal(t, scale18(5), result.Trades[0].Quantity)
		assert.Equal(t, scale18(7), result.Trades[1].Quantity)
	})

	t.Run("Market Sell Order", func(t *testing.T) {
		marketSell := createMarketOrder("market_sell1", "user6", types.SELL, 10)

		results, err := engine.ProcessOrder(marketSell)
		require.NoError(t, err)
		require.Len(t, results, 1)

		result := results[0]
		assert.Equal(t, types.FILLED, result.Status)
		assert.Equal(t, scale18(10), result.FilledQuantity)

		// Should have consumed buy1 (7) and part of buy2 (3)
		assert.Len(t, result.Trades, 2)
	})
}

func TestSymbolEngine_ProcessOrder_PartialFill(t *testing.T) {
	engine := createTestEngine()

	// Place a large buy order
	buyOrder := createLimitOrder("buy_large", "user1", types.BUY, 2000, 100)
	results, err := engine.ProcessOrder(buyOrder)

	require.NoError(t, err)
	require.Len(t, results, 1)
	result := results[0]
	assert.Equal(t, types.PENDING, result.Status)

	// Sell small amounts to partially fill
	sell1 := createLimitOrder("sell1", "user2", types.SELL, 2000, 30)
	result1s, err := engine.ProcessOrder(sell1)

	require.NoError(t, err)

	require.Len(t, result1s, 1)

	result1 := result1s[0]
	require.NoError(t, err)
	assert.Equal(t, types.FILLED, result1.Status)

	// Check buy order is partially filled
	order, exists := engine.orderBook.GetOrder("buy_large")
	assert.True(t, exists)
	assert.Equal(t, types.PARTIALLY_FILLED, order.Status)
	assert.Equal(t, scale18(70), order.Quantity) // 100 - 30

	// Fill more
	sell2 := createLimitOrder("sell2", "user3", types.SELL, 2000, 70)
	result2s, err := engine.ProcessOrder(sell2)

	require.NoError(t, err)

	require.Len(t, result2s, 1)

	result2 := result2s[0]
	require.NoError(t, err)
	assert.Equal(t, types.FILLED, result2.Status)

	// Buy order should now be fully filled and removed
	assertOrderNotInBook(t, engine, "buy_large")
}

// ============================================================
// 2. Order with TPSL Tests
// ============================================================

func TestSymbolEngine_ProcessOrder_WithTPSL(t *testing.T) {
	engine := createTestEngine()

	t.Run("Buy Order with TPSL", func(t *testing.T) {
		// Create buy order with TPSL
		buyOrder := createOrderWithTPSL("buy_tpsl", "user1", types.BUY,
			2000, 10, // price, quantity
			2200, // TP at 2200
			1900, // SL trigger at 1900
			1890) // SL limit at 1890

		results, err := engine.ProcessOrder(buyOrder)
		require.NoError(t, err)
		require.Len(t, results, 1)

		result := results[0]
		assert.Equal(t, types.PENDING, result.Status)

		// Order should be in orderbook
		assertOrderInBook(t, engine, "buy_tpsl")

		// Now fill the order by placing a matching sell
		sellOrder := createLimitOrder("sell1", "user2", types.SELL, 2000, 10)
		result2s, err := engine.ProcessOrder(sellOrder)
		require.NoError(t, err)
		require.Len(t, result2s, 2) // TPSL creates 2 results

		result2 := result2s[0]
		require.NoError(t, err)
		assert.Equal(t, types.FILLED, result2.Status)

		// Debug: Check if the buy order was filled
		buyOrderAfter, exists := engine.orderBook.GetOrder("buy_tpsl")
		if exists {
			t.Logf("Buy order still in book, status: %v, quantity: %v", buyOrderAfter.Status, buyOrderAfter.Quantity)
		} else {
			t.Logf("Buy order removed from book (filled)")
		}

		// Check if there were any TPSL errors
		if len(result2.TPSLErrors) > 0 {
			t.Logf("TPSL errors: %v", result2.TPSLErrors)
		}

		// Check that TPSL was created (through conditional manager)
		assert.True(t, engine.HasTPSL("buy_tpsl"), "TPSL should be active after order fill")

		// TP/SL orders are conditional orders, not in the regular orderbook
		// They will only be added to orderbook when triggered
	})

	t.Run("Sell Order with TPSL", func(t *testing.T) {
		engine2 := createTestEngine()

		// Create sell order with TPSL
		sellOrder := createOrderWithTPSL("sell_tpsl", "user3", types.SELL,
			3000, 5, // price, quantity
			2800, // TP at 2800 (lower for sell)
			3100, // SL trigger at 3100 (higher for sell)
			3110) // SL limit at 3110

		results, err := engine2.ProcessOrder(sellOrder)
		require.NoError(t, err)
		require.Len(t, results, 1)
		result := results[0]
		assert.Equal(t, types.PENDING, result.Status)

		// Fill the order
		buyOrder := createLimitOrder("buy1", "user4", types.BUY, 3000, 5)
		result2s, err := engine2.ProcessOrder(buyOrder)
		require.NoError(t, err)
		require.Len(t, result2s, 2) // TPSL creates 2 results
		result2 := result2s[0]
		assert.Equal(t, types.FILLED, result2.Status)

		// Check that TPSL was created (through conditional manager)
		assert.True(t, engine2.HasTPSL("sell_tpsl"), "TPSL should be active after order fill")
	})
}

func TestSymbolEngine_TPSL_OCOBehavior(t *testing.T) {
	t.Run("TP Fill Cancels SL", func(t *testing.T) {
		engine := createTestEngine()

		// Setup: Create and fill an order with TPSL
		// First place a sell order to match against
		sellOrder := createLimitOrder("sell1", "user2", types.SELL, 2000, 10)
		engine.ProcessOrder(sellOrder)

		// Now place buy order with TPSL that will fill
		buyOrder := createOrderWithTPSL("buy1", "user1", types.BUY,
			2000, 10, 2200, 1900, 1890)
		results, err := engine.ProcessOrder(buyOrder)
		require.NoError(t, err)
		require.Len(t, results, 2) // TPSL creates 2 results

		result := results[0]
		assert.Equal(t, types.FILLED, result.Status)

		// TPSL should be active
		assert.True(t, engine.HasTPSL("buy1"))

		// Verify TP order is in the orderbook (sell at 2200)
		tpOrderID := types.GenerateTPOrderID("buy1")
		tpOrder, exists := engine.orderBook.GetOrder(tpOrderID)
		require.True(t, exists, "TP order should be in orderbook")
		assert.Equal(t, types.SELL, tpOrder.Side)
		assert.Equal(t, scale18(2200), tpOrder.Price)
		assert.Equal(t, scale18(10), tpOrder.Quantity)

		// Verify SL is registered as a conditional order (not in orderbook yet)
		slOrderID := types.GenerateSLOrderID("buy1")
		_, exists = engine.orderBook.GetOrder(slOrderID)
		assert.False(t, exists, "SL order should NOT be in orderbook (it's conditional)")

		// Now fill the TP order by placing a buy at 2200
		buyAtTP := createLimitOrder("buy2", "user3", types.BUY, 2200, 10)
		result2s, err := engine.ProcessOrder(buyAtTP)

		require.NoError(t, err)

		require.Len(t, result2s, 1)

		result2 := result2s[0]
		require.NoError(t, err)
		assert.Equal(t, types.FILLED, result2.Status)

		// TP order should be filled and removed
		_, exists = engine.orderBook.GetOrder(tpOrderID)
		assert.False(t, exists, "TP order should be removed after fill")

		// SL should be cancelled (OCO behavior)
		// Try to trigger SL - it should not activate
		currentPrice := scale18(1850) // Below SL trigger
		triggeredOrders, cancelledOrders := engine.conditionalManager.CheckTriggers(currentPrice)
		assert.Empty(t, triggeredOrders, "SL should not trigger after TP filled")
		assert.Empty(t, cancelledOrders, "No orders should be cancelled by trigger")

		// Verify TPSL is no longer active
		assert.False(t, engine.HasTPSL("buy1"), "TPSL should be inactive after TP fill")
	})

	t.Run("SL Trigger Cancels TP", func(t *testing.T) {
		engine := createTestEngine()

		// Setup: Create and fill an order with TPSL
		sellOrder := createLimitOrder("sell1", "user2", types.SELL, 2000, 10)
		engine.ProcessOrder(sellOrder)

		buyOrder := createOrderWithTPSL("buy1", "user1", types.BUY,
			2000, 10, 2200, 1900, 1890)
		results, err := engine.ProcessOrder(buyOrder)
		require.NoError(t, err)
		require.Len(t, results, 2) // TPSL creates 2 results

		result := results[0]
		assert.Equal(t, types.FILLED, result.Status)

		// Verify initial state
		tpOrderID := types.GenerateTPOrderID("buy1")
		_, exists := engine.orderBook.GetOrder(tpOrderID)
		require.True(t, exists, "TP order should be in orderbook")

		// Trigger SL by price drop
		currentPrice := scale18(1850) // Below SL trigger of 1900
		triggeredOrders, cancelledOrders := engine.conditionalManager.CheckTriggers(currentPrice)

		// SL should trigger and create a sell order
		require.Len(t, triggeredOrders, 1, "SL should trigger")
		slOrder := triggeredOrders[0]
		assert.Equal(t, types.SELL, slOrder.Side)
		assert.Equal(t, scale18(1890), slOrder.Price) // SL limit price

		// TP order should be cancelled (OCO behavior)
		assert.Contains(t, cancelledOrders, tpOrderID, "TP order should be cancelled when SL triggers")

		// Process the triggered SL order
		_, err = engine.ProcessOrder(slOrder)
		require.NoError(t, err)

		// TP order should be removed from orderbook
		_, exists = engine.orderBook.GetOrder(tpOrderID)
		assert.False(t, exists, "TP order should be removed after SL trigger")

		// TPSL should no longer be active
		assert.False(t, engine.HasTPSL("buy1"), "TPSL should be inactive after SL trigger")
	})

	t.Run("Cancel TP Removes Both TP and SL", func(t *testing.T) {
		engine := createTestEngine()

		// Setup: Create and fill an order with TPSL
		sellOrder := createLimitOrder("sell1", "user2", types.SELL, 2000, 10)
		engine.ProcessOrder(sellOrder)

		buyOrder := createOrderWithTPSL("buy1", "user1", types.BUY,
			2000, 10, 2200, 1900, 1890)
		results, err := engine.ProcessOrder(buyOrder)

		require.NoError(t, err)
		require.Len(t, results, 2) // TPSL creates 2 results

		result := results[0]
		assert.Equal(t, types.FILLED, result.Status)

		// Verify TPSL is active
		assert.True(t, engine.HasTPSL("buy1"))

		tpOrderID := types.GenerateTPOrderID("buy1")
		slOrderID := types.GenerateSLOrderID("buy1")

		// Cancel TP order
		cancelResult, err := engine.CancelOrder(tpOrderID)
		require.NoError(t, err)
		assert.True(t, cancelResult.Cancelled, "Cancel should succeed")
		assert.True(t, slices.Contains(cancelResult.CancelledOrderIds, tpOrderID))
		assert.True(t, slices.Contains(cancelResult.CancelledOrderIds, slOrderID), "SL should be cancelled via OCO")

		// Both TP and SL should be cancelled (OCO behavior)
		_, exists := engine.orderBook.GetOrder(tpOrderID)
		assert.False(t, exists, "TP order should be removed")

		// Try to trigger SL - it should not work
		currentPrice := scale18(1850)
		triggeredOrders, _ := engine.conditionalManager.CheckTriggers(currentPrice)
		assert.Empty(t, triggeredOrders, "SL should not trigger after TP cancelled")

		// TPSL should be inactive
		assert.False(t, engine.HasTPSL("buy1"), "TPSL should be inactive after cancellation")
	})

	t.Run("Cancel SL Removes Both SL and TP", func(t *testing.T) {
		engine := createTestEngine()

		// Setup: Create and fill an order with TPSL
		sellOrder := createLimitOrder("sell1", "user2", types.SELL, 2000, 10)
		engine.ProcessOrder(sellOrder)

		buyOrder := createOrderWithTPSL("buy1", "user1", types.BUY,
			2000, 10, 2200, 1900, 1890)
		results, err := engine.ProcessOrder(buyOrder)
		require.NoError(t, err)
		require.Len(t, results, 2) // TPSL creates 2 results

		result := results[0]
		assert.Equal(t, types.FILLED, result.Status)

		// Verify TPSL is active
		assert.True(t, engine.HasTPSL("buy1"))

		tpOrderID := types.GenerateTPOrderID("buy1")
		slOrderID := types.GenerateSLOrderID("buy1")

		// Verify TP is in orderbook
		_, exists := engine.orderBook.GetOrder(tpOrderID)
		require.True(t, exists, "TP order should be in orderbook initially")

		// Cancel SL order (which is a conditional order)
		cancelResult, err := engine.CancelOrder(slOrderID)
		require.NoError(t, err)
		assert.True(t, cancelResult.Cancelled, "SL cancel should succeed")
		assert.True(t, slices.Contains(cancelResult.CancelledOrderIds, tpOrderID))
		assert.True(t, slices.Contains(cancelResult.CancelledOrderIds, slOrderID))

		// TP order should also be cancelled (OCO behavior)
		_, exists = engine.orderBook.GetOrder(tpOrderID)
		assert.False(t, exists, "TP order should be removed when SL is cancelled")

		// Try to trigger SL - it should not work
		currentPrice := scale18(1850)
		triggeredOrders, _ := engine.conditionalManager.CheckTriggers(currentPrice)
		assert.Empty(t, triggeredOrders, "SL should not trigger after being cancelled")

		// Try to fill TP - order should not exist
		buyAtTP := createLimitOrder("buy2", "user3", types.BUY, 2200, 10)
		result2s, err := engine.ProcessOrder(buyAtTP)
		require.NoError(t, err)
		require.Len(t, result2s, 1)

		result2 := result2s[0]
		require.NoError(t, err)
		assert.Equal(t, types.PENDING, result2.Status, "Buy order should rest in book as TP is gone")

		// TPSL should be inactive
		assert.False(t, engine.HasTPSL("buy1"), "TPSL should be inactive after SL cancellation")
	})

	t.Run("Sell Order TPSL OCO", func(t *testing.T) {
		engine := createTestEngine()

		// For SELL orders, TP is lower and SL is higher
		buyOrder := createLimitOrder("buy1", "user2", types.BUY, 3000, 5)
		engine.ProcessOrder(buyOrder)

		sellOrder := createOrderWithTPSL("sell1", "user1", types.SELL,
			3000, 5,
			2800, // TP at 2800 (profit when price drops)
			3100, // SL trigger at 3100 (loss when price rises)
			3110) // SL limit at 3110

		results, err := engine.ProcessOrder(sellOrder)
		require.NoError(t, err)
		require.Len(t, results, 2) // TPSL creates 2 results

		result := results[0]
		assert.Equal(t, types.FILLED, result.Status)

		// Verify TPSL is active
		assert.True(t, engine.HasTPSL("sell1"))

		// TP order should be a BUY at 2800
		tpOrderID := types.GenerateTPOrderID("sell1")
		tpOrder, exists := engine.orderBook.GetOrder(tpOrderID)
		require.True(t, exists, "TP order should be in orderbook")
		assert.Equal(t, types.BUY, tpOrder.Side, "Sell TP should create BUY order")
		assert.Equal(t, scale18(2800), tpOrder.Price)

		// Fill TP order
		sellAtTP := createLimitOrder("sell2", "user3", types.SELL, 2800, 5)
		result2s, err := engine.ProcessOrder(sellAtTP)
		require.NoError(t, err)
		require.Len(t, result2s, 1)

		result2 := result2s[0]
		require.NoError(t, err)
		assert.Equal(t, types.FILLED, result2.Status)

		// SL should be cancelled (OCO)
		currentPrice := scale18(3150) // Above SL trigger
		triggeredOrders, _ := engine.conditionalManager.CheckTriggers(currentPrice)
		assert.Empty(t, triggeredOrders, "SL should not trigger after TP filled")

		// TPSL should be inactive
		assert.False(t, engine.HasTPSL("sell1"), "TPSL should be inactive after TP fill")
	})
}

func TestSymbolEngine_TPSL_PriceValidation(t *testing.T) {
	t.Run("Invalid Buy TPSL - TP too low", func(t *testing.T) {
		engine := createTestEngine()

		buyOrder := createOrderWithTPSL("buy1", "user1", types.BUY,
			2000, 10,
			1950, // TP lower than price (invalid)
			1900, // SL
			1890)

		// Order placement should succeed but TPSL validation should fail during activation
		results, err := engine.ProcessOrder(buyOrder)
		require.NoError(t, err)
		require.Len(t, results, 1)

		result := results[0]
		assert.Equal(t, types.PENDING, result.Status)
	})

	t.Run("Invalid Sell TPSL - TP too high", func(t *testing.T) {
		engine := createTestEngine()

		sellOrder := createOrderWithTPSL("sell1", "user2", types.SELL,
			2000, 10,
			2100, // TP higher than price (invalid for sell)
			1900, // SL lower than price (invalid for sell)
			1890)

		results, err := engine.ProcessOrder(sellOrder)
		require.NoError(t, err)
		require.Len(t, results, 1)

		result := results[0]
		assert.Equal(t, types.PENDING, result.Status)
	})
}

// ============================================================
// 3. Stop Order Tests
// ============================================================

func TestSymbolEngine_ProcessStopOrder_Basic(t *testing.T) {
	engine := createTestEngine()

	t.Run("Stop-Limit Buy Order", func(t *testing.T) {
		stopBuy := createStopOrder("stop_buy1", "user1", types.BUY,
			2100, // limit price
			2050, // trigger price
			true) // trigger when price >= 2050

		err := engine.ProcessStopOrder(stopBuy)
		require.NoError(t, err)

		// Should be added to conditional manager, not orderbook
		assertOrderNotInBook(t, engine, "stop_buy1")

		// Verify it's tracked (can check by trying to cancel it)
		cancelled, cancelledIDs := engine.conditionalManager.CancelOrder(types.OrderID("stop_buy1"))
		assert.True(t, cancelled, "Stop order should have been in conditional manager")
		assert.True(t, slices.Contains(cancelledIDs, types.OrderID("stop_buy1")), "Stop order should have been in cancelled IDs")
	})

	t.Run("Stop-Limit Sell Order", func(t *testing.T) {
		stopSell := createStopOrder("stop_sell1", "user2", types.SELL,
			1900,  // limit price
			1950,  // trigger price
			false) // trigger when price <= 1950

		err := engine.ProcessStopOrder(stopSell)
		require.NoError(t, err)

		assertOrderNotInBook(t, engine, "stop_sell1")
	})
}

func TestSymbolEngine_StopOrder_Triggering(t *testing.T) {
	t.Run("Trigger Stop Buy", func(t *testing.T) {
		engine := createTestEngine()

		// First set an initial price by making a trade
		buyInit := createLimitOrder("buy_init", "user_init", types.BUY, 2000, 1)
		sellInit := createLimitOrder("sell_init", "user_init2", types.SELL, 2000, 1)
		engine.ProcessOrder(buyInit)
		results, _ := engine.ProcessOrder(sellInit)
		require.Len(t, results, 1)
		result := results[0]
		require.Equal(t, types.FILLED, result.Status, "Initial trade should be filled to set price")

		// Add stop buy order (will trigger when price rises to 2050 or above)
		stopBuy := createStopOrder("stop_buy", "user1", types.BUY, 2100, 2050, true)
		err := engine.ProcessStopOrder(stopBuy)
		require.NoError(t, err)

		// Verify stop order is NOT in orderbook initially
		_, exists := engine.orderBook.GetOrder("stop_buy")
		assert.False(t, exists, "Stop order should not be in orderbook before trigger")

		// Place order that sets price above trigger
		sellOrder := createLimitOrder("sell1", "user3", types.SELL, 2060, 5)
		engine.ProcessOrder(sellOrder)

		// Place buy order to match and set price to 2060
		// This should trigger the stop buy at 2050 automatically
		buyOrder := createLimitOrder("buy1", "user4", types.BUY, 2060, 5)
		results2, err := engine.ProcessOrder(buyOrder)
		require.NoError(t, err)
		require.Len(t, results2, 2) // Buy order result + triggered stop order result
		result2 := results2[0]
		assert.Equal(t, types.FILLED, result2.Status)

		// The engine should have automatically triggered and processed the stop buy
		// Verify stop buy is now in orderbook
		stopBuyOrder, exists := engine.orderBook.GetOrder("stop_buy")
		assert.True(t, exists, "Stop buy should be in orderbook after automatic trigger")
		if exists {
			assert.Equal(t, scale18(2100), stopBuyOrder.Price)
			assert.Equal(t, types.BUY, stopBuyOrder.Side)
			assert.Equal(t, scale18(10), stopBuyOrder.Quantity) // Stop order was created with quantity 10
		}
	})

	t.Run("Trigger Stop Sell", func(t *testing.T) {
		engine := createTestEngine()

		// First set an initial price by making a trade
		buyInit := createLimitOrder("buy_init", "user_init", types.BUY, 2000, 1)
		sellInit := createLimitOrder("sell_init", "user_init2", types.SELL, 2000, 1)
		engine.ProcessOrder(buyInit)
		results, _ := engine.ProcessOrder(sellInit)
		require.Len(t, results, 1)
		result := results[0]
		require.Equal(t, types.FILLED, result.Status, "Initial trade should be filled to set price")

		// Add stop sell order (will trigger when price drops to 1950 or below)
		stopSell := createStopOrder("stop_sell", "user2", types.SELL, 1900, 1950, false)
		err := engine.ProcessStopOrder(stopSell)
		require.NoError(t, err)

		// Verify stop order is NOT in orderbook initially
		_, exists := engine.orderBook.GetOrder("stop_sell")
		assert.False(t, exists, "Stop order should not be in orderbook before trigger")

		// Place orders to set price to 1940
		buyOrder := createLimitOrder("buy2", "user5", types.BUY, 1940, 5)
		engine.ProcessOrder(buyOrder)

		// This should trigger the stop sell at 1950 automatically
		sellOrder := createLimitOrder("sell2", "user6", types.SELL, 1940, 5)
		results2, err := engine.ProcessOrder(sellOrder)
		require.NoError(t, err)
		require.Len(t, results2, 2) // Sell order result + triggered stop order result
		result2 := results2[0]
		assert.Equal(t, types.FILLED, result2.Status)

		// The engine should have automatically triggered and processed the stop sell
		// Verify stop sell is now in orderbook
		stopSellOrder, exists := engine.orderBook.GetOrder("stop_sell")
		assert.True(t, exists, "Stop sell should be in orderbook after automatic trigger")
		if exists {
			assert.Equal(t, scale18(1900), stopSellOrder.Price)
			assert.Equal(t, types.SELL, stopSellOrder.Side)
			assert.Equal(t, scale18(10), stopSellOrder.Quantity) // Stop order was created with quantity 10
		}
	})
}

// ============================================================
// 4. Modify Order Tests
// ============================================================

func TestSymbolEngine_ModifyOrder_Price(t *testing.T) {
	engine := createTestEngine()

	// Place an order
	buyOrder := createLimitOrder("buy1", "user1", types.BUY, 2000, 10)
	results, err := engine.ProcessOrder(buyOrder)

	require.NoError(t, err)

	require.Len(t, results, 1)

	result := results[0]
	assert.Equal(t, types.PENDING, result.Status)

	t.Run("Modify Price Only", func(t *testing.T) {

		// Modify price from 2000 to 2100
		modifyResult, err := engine.ModifyOrder("buy1", "buy1_mod", scale18(2100), nil)
		require.NoError(t, err)
		assert.NotNil(t, modifyResult)
		assert.NotNil(t, modifyResult.NewOrder)
		assert.Equal(t, scale18(2100), modifyResult.NewOrder.Price)
		assert.Equal(t, scale18(10), modifyResult.NewOrder.Quantity)

		// Old order should be cancelled, new order should exist
		_, exists := engine.orderBook.GetOrder("buy1")
		assert.False(t, exists)
		order, exists := engine.orderBook.GetOrder("buy1_mod")
		assert.True(t, exists)
		assert.Equal(t, scale18(2100), order.Price)

	})
}

func TestSymbolEngine_ModifyOrder_Quantity(t *testing.T) {
	engine := createTestEngine()

	// Place and partially fill an order
	buyOrder := createLimitOrder("buy1", "user1", types.BUY, 2000, 20)
	engine.ProcessOrder(buyOrder)

	// Partially fill it
	sellOrder := createLimitOrder("sell1", "user2", types.SELL, 2000, 5)
	engine.ProcessOrder(sellOrder)

	t.Run("Modify Quantity - Valid", func(t *testing.T) {
		// Modify quantity from 20 to 25 (filled = 5, so new remaining = 20)
		modifyResult, err := engine.ModifyOrder("buy1", "buy1_mod", nil, scale18(25))
		require.NoError(t, err)
		assert.NotNil(t, modifyResult)
		assert.NotNil(t, modifyResult.NewOrder)
		assert.Equal(t, scale18(25), modifyResult.NewOrder.OrigQty)
		assert.Equal(t, scale18(20), modifyResult.NewOrder.Quantity) // 25 - 5 filled

		// Check new order has correct remaining quantity
		_, exists := engine.orderBook.GetOrder("buy1")
		assert.False(t, exists)
		order, exists := engine.orderBook.GetOrder("buy1_mod")
		assert.True(t, exists)
		assert.Equal(t, scale18(20), order.Quantity) // 25 - 5 filled
		assert.Equal(t, scale18(25), order.OrigQty)
	})

	t.Run("Modify Quantity - Invalid (less than filled)", func(t *testing.T) {
		// Try to modify to quantity less than already filled (buy1 is now buy1_mod from previous test)
		_, err := engine.ModifyOrder("buy1_mod", "buy1_mod2", nil, scale18(4))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "greater than already filled")
	})
}

func TestSymbolEngine_ModifyOrder_Both(t *testing.T) {
	engine := createTestEngine()

	buyOrder := createLimitOrder("buy1", "user1", types.BUY, 2000, 10)
	engine.ProcessOrder(buyOrder)

	t.Run("Modify Both Price and Quantity", func(t *testing.T) {
		modifyResult, err := engine.ModifyOrder("buy1", "buy1_mod3",
			scale18(2100), // new price
			scale18(15))   // new quantity

		require.NoError(t, err)
		assert.NotNil(t, modifyResult)
		assert.NotNil(t, modifyResult.NewOrder)
		assert.Equal(t, scale18(2100), modifyResult.NewOrder.Price)
		assert.Equal(t, scale18(15), modifyResult.NewOrder.Quantity)

		// Verify new order exists
		_, exists := engine.orderBook.GetOrder("buy1")
		assert.False(t, exists)
		order, exists := engine.orderBook.GetOrder("buy1_mod3")
		assert.True(t, exists)
		assert.Equal(t, scale18(2100), order.Price)
		assert.Equal(t, scale18(15), order.Quantity)
	})
}

func TestSymbolEngine_ModifyOrder_Validations(t *testing.T) {
	engine := createTestEngine()

	t.Run("Cannot Modify TPSL Order", func(t *testing.T) {
		tpslOrder := createOrderWithTPSL("tpsl1", "user1", types.BUY,
			2000, 10, 2200, 1900, 1890)
		engine.ProcessOrder(tpslOrder)

		_, err := engine.ModifyOrder("tpsl1", "tpsl1_mod", scale18(2100), nil)
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "cannot modify order with TPSL")
	})

	t.Run("Cannot Modify Non-Existent Order", func(t *testing.T) {
		_, err := engine.ModifyOrder("non_existent", "non_existent_mod", scale18(2000), nil)
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "not found")
	})

	t.Run("Cannot Modify Filled Order", func(t *testing.T) {
		// Create and fill an order
		buyOrder := createLimitOrder("buy1", "user2", types.BUY, 3000, 5)
		engine.ProcessOrder(buyOrder)

		sellOrder := createLimitOrder("sell1", "user3", types.SELL, 3000, 5)
		engine.ProcessOrder(sellOrder)

		// Try to modify the filled order
		_, err := engine.ModifyOrder("buy1", "buy1_mod4", scale18(3100), nil)
		assert.Error(t, err)
	})
}

// ============================================================
// 5. Cancel Order Tests
// ============================================================

func TestSymbolEngine_CancelOrder_Basic(t *testing.T) {
	engine := createTestEngine()

	// Place orders
	buyOrder := createLimitOrder("buy1", "user1", types.BUY, 2000, 10)
	engine.ProcessOrder(buyOrder)

	sellOrder := createLimitOrder("sell1", "user2", types.SELL, 2100, 5)
	engine.ProcessOrder(sellOrder)

	t.Run("Cancel Buy Order", func(t *testing.T) {

		cancelResult, err := engine.CancelOrder("buy1")
		require.NoError(t, err)
		assert.True(t, cancelResult.Cancelled)
		assert.True(t, slices.Contains(cancelResult.CancelledOrderIds, "buy1"))

		// Order should be removed from book
		assertOrderNotInBook(t, engine, "buy1")

	})

	t.Run("Cancel Sell Order", func(t *testing.T) {

		cancelResult, err := engine.CancelOrder("sell1")
		require.NoError(t, err)
		assert.True(t, cancelResult.Cancelled)
		assert.True(t, slices.Contains(cancelResult.CancelledOrderIds, "sell1"))

		assertOrderNotInBook(t, engine, "sell1")
	})

	t.Run("Cancel Non-Existent Order", func(t *testing.T) {
		_, err := engine.CancelOrder("non_existent")
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "not found")
	})
}

func TestSymbolEngine_CancelOrder_WithTPSL(t *testing.T) {
	engine := createTestEngine()

	// First place a sell order to match against
	sellOrder := createLimitOrder("sell1", "user2", types.SELL, 2000, 10)
	engine.ProcessOrder(sellOrder)

	// Create and fill order with TPSL
	buyOrder := createOrderWithTPSL("buy1", "user1", types.BUY,
		2000, 10, 2200, 1900, 1890)
	results, err := engine.ProcessOrder(buyOrder)
	require.NoError(t, err)
	require.Len(t, results, 2) // TPSL creates 2 results

	result := results[0]
	assert.Equal(t, types.FILLED, result.Status)

	// TPSL should be active
	assert.True(t, engine.HasTPSL("buy1"))

	// Both TP and SL are conditional orders
	tpOrderID := types.GenerateTPOrderID("buy1")
	slOrderID := types.GenerateSLOrderID("buy1")

	t.Run("Cancel TP Order via Conditional Manager", func(t *testing.T) {
		// Cancel TP through conditional manager
		cancelled, cancelledIDs := engine.conditionalManager.CancelOrder(tpOrderID)
		assert.True(t, cancelled, "TP order should have been cancelled")
		assert.True(t, slices.Contains(cancelledIDs, tpOrderID), "TP order should have been cancelled")

		// Due to OCO, SL should also be cancelled
		cancelledSL, cancelledSLIDs := engine.conditionalManager.CancelOrder(slOrderID)
		assert.False(t, cancelledSL, "SL should have been cancelled by OCO")
		assert.Empty(t, cancelledSLIDs, "SL should not have been cancelled by OCO")

		// TPSL should no longer be active
		assert.False(t, engine.HasTPSL("buy1"))
	})
}

func TestSymbolEngine_CancelOrder_Conditional(t *testing.T) {
	engine := createTestEngine()

	// Add stop order
	stopOrder := createStopOrder("stop1", "user1", types.BUY, 2100, 2050, true)
	engine.ProcessStopOrder(stopOrder)

	t.Run("Cancel Stop Order", func(t *testing.T) {
		cancelResult, err := engine.CancelOrder("stop1")
		require.NoError(t, err)
		assert.True(t, cancelResult.Cancelled)

		// Should be removed from conditional manager (verify it's gone)
		cancelledAgain, cancelledIDs := engine.conditionalManager.CancelOrder("stop1")
		assert.False(t, cancelledAgain, "Stop order should have been removed")
		assert.Nil(t, cancelledIDs)
	})
}

// ============================================================
// 6. CancelAll Tests
// ============================================================

func TestSymbolEngine_CancelAllOrders_Basic(t *testing.T) {
	engine := createTestEngine()

	// Place multiple orders for user1
	engine.ProcessOrder(createLimitOrder("buy1", "user1", types.BUY, 2000, 10))
	engine.ProcessOrder(createLimitOrder("buy2", "user1", types.BUY, 1990, 5))
	engine.ProcessOrder(createLimitOrder("sell1", "user1", types.SELL, 2100, 8))

	// Place orders for user2
	engine.ProcessOrder(createLimitOrder("buy3", "user2", types.BUY, 1980, 3))

	t.Run("Cancel All Orders for User1", func(t *testing.T) {

		cancelResult, err := engine.CancelAllOrders("user1")
		require.NoError(t, err)
		assert.Len(t, cancelResult.CancelledOrderIds, 3)

		// User1 orders should be removed
		assertOrderNotInBook(t, engine, "buy1")
		assertOrderNotInBook(t, engine, "buy2")
		assertOrderNotInBook(t, engine, "sell1")

		// User2 order should remain
		assertOrderInBook(t, engine, "buy3")

	})
}

func TestSymbolEngine_CancelAllOrders_Mixed(t *testing.T) {
	engine := createTestEngine()

	// Place regular orders
	engine.ProcessOrder(createLimitOrder("buy1", "user1", types.BUY, 2000, 10))

	// Place order with TPSL and fill it
	// First place a sell order to match against
	sellOrder := createLimitOrder("sell1", "user2", types.SELL, 2100, 5)
	engine.ProcessOrder(sellOrder)

	// Now place buy order with TPSL that will fill
	tpslOrder := createOrderWithTPSL("buy2", "user1", types.BUY,
		2100, 5, 2300, 2000, 1990)
	results, err := engine.ProcessOrder(tpslOrder)

	require.NoError(t, err)

	require.Len(t, results, 2) // TPSL creates 2 results

	result := results[0]
	assert.Equal(t, types.FILLED, result.Status)

	// Verify TPSL is active
	assert.True(t, engine.HasTPSL("buy2"))

	// Place stop order
	stopOrder := createStopOrder("stop1", "user1", types.BUY, 2200, 2150, true)
	engine.ProcessStopOrder(stopOrder)

	t.Run("Cancel All Mixed Order Types", func(t *testing.T) {
		_, err := engine.CancelAllOrders("user1")
		require.NoError(t, err)

		// Should cancel regular order
		assertOrderNotInBook(t, engine, "buy1")

		// TPSL should be cancelled (check that it's no longer active)
		assert.False(t, engine.HasTPSL("buy2"), "TPSL should have been cancelled")

		// Verify TP/SL are both cancelled via conditional manager
		tpOrderID := types.GenerateTPOrderID("buy2")
		slOrderID := types.GenerateSLOrderID("buy2")
		cancelledTP, cancelledIDs1 := engine.conditionalManager.CancelOrder(tpOrderID)
		cancelledSL, cancelledIDs2 := engine.conditionalManager.CancelOrder(slOrderID)
		assert.False(t, cancelledTP, "TP should have been cancelled with all orders")
		assert.False(t, cancelledSL, "SL should have been cancelled with all orders")
		assert.Empty(t, cancelledIDs1)
		assert.Empty(t, cancelledIDs2)

		// Should cancel stop order
		cancelledStop, cancelledIDs3 := engine.conditionalManager.CancelOrder("stop1")
		assert.False(t, cancelledStop, "Stop order should have been cancelled with all orders")
		assert.Empty(t, cancelledIDs3)

	})
}

func TestSymbolEngine_CancelAllOrders_MultipleUsers(t *testing.T) {
	engine := createTestEngine()

	// Place orders for multiple users
	users := []string{"user1", "user2", "user3"}
	for i, user := range users {
		for j := 0; j < 3; j++ {
			orderID := fmt.Sprintf("%s_order%d", user, j)
			price := uint64(2000 + i*10 + j)
			engine.ProcessOrder(createLimitOrder(orderID, user, types.BUY, price, 5))
		}
	}

	t.Run("Cancel Only Target User Orders", func(t *testing.T) {
		// Cancel user2 orders
		cancelResult, err := engine.CancelAllOrders("user2")
		require.NoError(t, err)
		assert.Len(t, cancelResult.CancelledOrderIds, 3)

		// User2 orders should be removed
		for i := 0; i < 3; i++ {
			assertOrderNotInBook(t, engine, fmt.Sprintf("user2_order%d", i))
		}

		// Other users' orders should remain
		for i := 0; i < 3; i++ {
			assertOrderInBook(t, engine, fmt.Sprintf("user1_order%d", i))
			assertOrderInBook(t, engine, fmt.Sprintf("user3_order%d", i))
		}
	})
}

// ============================================================
// Integration Tests
// ============================================================

func TestSymbolEngine_Integration_OrderLifecycle(t *testing.T) {
	engine := createTestEngine()

	t.Run("Full Order Lifecycle", func(t *testing.T) {
		// 1. Place order
		order := createLimitOrder("order1", "user1", types.BUY, 2000, 20)
		result1s, err := engine.ProcessOrder(order)
		require.NoError(t, err)
		require.Len(t, result1s, 1)

		result1 := result1s[0]
		require.NoError(t, err)
		assert.Equal(t, types.PENDING, result1.Status)

		// 2. Modify price
		modResult, err := engine.ModifyOrder("order1", "order1_mod1", scale18(2010), nil)
		require.NoError(t, err)
		assert.NotNil(t, modResult)

		// 3. Partial fill
		sell1 := createLimitOrder("sell1", "user2", types.SELL, 2010, 5)
		result2s, err := engine.ProcessOrder(sell1)
		require.NoError(t, err)
		require.Len(t, result2s, 1)

		result2 := result2s[0]
		require.NoError(t, err)
		assert.Equal(t, types.FILLED, result2.Status)

		// 4. Modify quantity
		modResult2, err := engine.ModifyOrder("order1_mod1", "order1_mod2", nil, scale18(25))
		require.NoError(t, err)
		assert.NotNil(t, modResult2)

		// 5. Cancel (order1 has been modified to order1_mod2)
		cancelResult, err := engine.CancelOrder("order1_mod2")
		require.NoError(t, err)
		assert.True(t, cancelResult.Cancelled)
		assert.True(t, slices.Contains(cancelResult.CancelledOrderIds, "order1_mod2"))

		// Order should be completely removed
		assertOrderNotInBook(t, engine, "order1_mod2")
	})
}

func TestSymbolEngine_Integration_ComplexScenario(t *testing.T) {
	engine := createTestEngine()

	t.Run("Complex Trading Scenario", func(t *testing.T) {
		// Setup initial orderbook
		engine.ProcessOrder(createLimitOrder("sell1", "mm1", types.SELL, 2010, 100))
		engine.ProcessOrder(createLimitOrder("sell2", "mm2", types.SELL, 2020, 200))
		engine.ProcessOrder(createLimitOrder("buy1", "mm3", types.BUY, 1990, 150))
		engine.ProcessOrder(createLimitOrder("buy2", "mm4", types.BUY, 1980, 250))

		// User places buy with TPSL
		userOrder := createOrderWithTPSL("user_buy", "trader1", types.BUY,
			2010, 50, 2100, 1950, 1940)
		results, err := engine.ProcessOrder(userOrder)
		require.NoError(t, err)
		require.Len(t, results, 2) // TPSL creates 2 results

		result := results[0]
		// Should match with sell1
		assert.Equal(t, types.FILLED, result.Status)
		assert.Equal(t, scale18(50), result.FilledQuantity)

		// TPSL should be activated
		assert.True(t, engine.HasTPSL("user_buy"), "TPSL should be active")

		// TP and SL are conditional orders, not in the regular orderbook
		// They would be triggered by price movements in a real scenario

		// Place stop order
		stopSell := createStopOrder("stop_sell", "trader1", types.SELL, 1970, 1975, false)
		err = engine.ProcessStopOrder(stopSell)
		require.NoError(t, err)

		// Cancel all orders for a market maker
		cancelResult, err := engine.CancelAllOrders("mm2")
		require.NoError(t, err)
		assert.Len(t, cancelResult.CancelledOrderIds, 1)
	})
}

// ============================================================
// OCO and TPSL Internal Tests (from symbol_engine_test.go)
// ============================================================

func TestSymbolEngine_OCOProcessing(t *testing.T) {
	mockBM := &mockBalanceManager{}
	engine := NewSymbolEngine("ETH/USDT", mockBM)

	// Track events
	var capturedEvents []interface{}
	engine.conditionalManager.SetOrderProcessor(func(order *types.Order) error {
		capturedEvents = append(capturedEvents, map[string]interface{}{
			"type":    "order_processed",
			"orderID": order.OrderID,
		})
		return nil
	})

	engine.conditionalManager.SetOrderCanceller(func(orderID types.OrderID) error {
		capturedEvents = append(capturedEvents, map[string]interface{}{
			"type":    "order_cancelled",
			"orderID": orderID,
		})
		return nil
	})

	// Create and process an order with TPSL
	buyOrder := &types.Order{
		OrderID:   "buy1",
		UserID:    "user1",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		OrderType: types.LIMIT,
		Price:     scale18(2000),
		Quantity:  scale18(10),
		OrigQty:   scale18(10),
		Status:    types.NEW,
		TPSL: &types.TPSLContext{
			TPLimitPrice:   scale18(2200), // Take profit at 2200
			SLTriggerPrice: scale18(1900), // Stop loss trigger at 1900
			SLLimitPrice:   scale18(1890), // Stop loss limit at 1890
		},
	}

	// Process the order
	results, err := engine.ProcessOrder(buyOrder)
	require.NoError(t, err)
	require.Len(t, results, 1)

	result := results[0]
	assert.Equal(t, types.PENDING, result.Status)

	// Simulate order being filled
	buyOrder.Status = types.FILLED

	// Create TPSL for the filled order
	err = engine.conditionalManager.CreateTPSLForFilledOrder(buyOrder)
	require.NoError(t, err)

	// Verify TP order was processed (added to queue)
	tpProcessed := false
	for _, event := range capturedEvents {
		if e, ok := event.(map[string]interface{}); ok {
			if e["type"] == "order_processed" {
				if orderID, ok := e["orderID"].(types.OrderID); ok {
					if orderID == types.GenerateTPOrderID(buyOrder.OrderID) {
						tpProcessed = true
						break
					}
				}
			}
		}
	}
	assert.True(t, tpProcessed, "TP order should have been processed")
}

func TestSymbolEngine_ProcessTPOrderFills(t *testing.T) {
	mockBM := &mockBalanceManager{}
	engine := NewSymbolEngine("ETH/USDT", mockBM)

	// Setup TPSL first
	originalOrder := &types.Order{
		OrderID:   "order1",
		UserID:    "user1",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		OrderType: types.LIMIT,
		Price:     scale18(2000),
		Quantity:  scale18(10),
		OrigQty:   scale18(10),
		Status:    types.FILLED,
		TPSL: &types.TPSLContext{
			TPLimitPrice:   scale18(2200),
			SLTriggerPrice: scale18(1900),
			SLLimitPrice:   scale18(1890),
		},
	}

	// Create TPSL
	err := engine.conditionalManager.CreateTPSLForFilledOrder(originalOrder)
	require.NoError(t, err)

	// Simulate TP order being partially filled
	tpOrderID := types.GenerateTPOrderID(originalOrder.OrderID)
	slOrderID := types.GenerateSLOrderID(originalOrder.OrderID)

	// Call HandleOrderFill for partial fill
	cancelledOrders := engine.conditionalManager.HandleOrderFill(tpOrderID)

	// SL should be cancelled due to OCO
	assert.Contains(t, cancelledOrders, slOrderID, "SL order should be cancelled when TP is filled")

	// After OCO triggers, TPSL is no longer active (even for partial fill)
	// This is correct behavior - once one side triggers, the other is cancelled
	assert.False(t, engine.conditionalManager.HasTPSL(originalOrder.OrderID),
		"TPSL should be inactive after OCO triggers")

	// Now test full fill
	mockBM2 := &mockBalanceManager{}
	engine2 := NewSymbolEngine("ETH/USDT", mockBM2)

	// Create another TPSL
	err = engine2.conditionalManager.CreateTPSLForFilledOrder(originalOrder)
	require.NoError(t, err)

	// Call HandleOrderFill for full fill
	cancelledOrders2 := engine2.conditionalManager.HandleOrderFill(tpOrderID)

	// SL should be cancelled
	assert.Contains(t, cancelledOrders2, slOrderID, "SL order should be cancelled when TP is fully filled")

	// After OCO triggers, TPSL is no longer active
	assert.False(t, engine2.conditionalManager.HasTPSL(originalOrder.OrderID),
		"TPSL should be inactive after OCO triggers")
}

func TestSymbolEngine_OCOEventGeneration(t *testing.T) {
	mockBM := &mockBalanceManager{}
	engine := NewSymbolEngine("ETH/USDT", mockBM)

	// Create sell order to match against
	sellOrder := &types.Order{
		OrderID:   "sell1",
		UserID:    "user2",
		Symbol:    "ETH/USDT",
		Side:      types.SELL,
		OrderType: types.LIMIT,
		Price:     scale18(2000),
		Quantity:  scale18(10),
		OrigQty:   scale18(10),
		Status:    types.NEW,
	}

	// Add sell order to book
	_, err := engine.ProcessOrder(sellOrder)
	require.NoError(t, err)

	// Create buy order with TPSL
	buyOrder := &types.Order{
		OrderID:   "buy1",
		UserID:    "user1",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		OrderType: types.LIMIT,
		Price:     scale18(2000),
		Quantity:  scale18(10),
		OrigQty:   scale18(10),
		Status:    types.NEW,
		TPSL: &types.TPSLContext{
			TPLimitPrice:   scale18(2200),
			SLTriggerPrice: scale18(1900),
			SLLimitPrice:   scale18(1890),
		},
	}

	// Process buy order (will match and fill)
	results, err := engine.ProcessOrder(buyOrder)
	require.NoError(t, err)
	require.Len(t, results, 2) // TPSL creates 2 results

	result := results[0]

	// Should be filled
	assert.Equal(t, types.FILLED, result.Status)

	// Should have events

	// Check if any TPSL errors occurred
	if len(result.TPSLErrors) > 0 {
		t.Logf("TPSL errors (expected in test): %v", result.TPSLErrors)
	}
}

func TestProcessOrderSlowdown(t *testing.T) {
	mockBM := &mockBalanceManager{}
	engine := NewSymbolEngine("2/3", mockBM)

	var symbol types.Symbol = "2/3"

	users := make([]types.UserID, 0, 100)
	for i := 0; i < 100; i++ {
		users = append(users, types.UserID(fmt.Sprintf("user%d", i)))
	}

	start := time.Now()
	for i := 0; i < 1000000; i++ {
		user := users[rand.Intn(len(users))]
		q := uint64(10 + rand.Intn(10))
		buyOrder := &types.Order{
			OrderID:   types.OrderID(fmt.Sprintf("%d_buy_%s", i, user)),
			UserID:    user,
			Symbol:    symbol,
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     scale18(uint64(100)),
			Quantity:  scale18(q),
			OrigQty:   scale18(q),
			Status:    types.NEW,
		}
		results, err := engine.ProcessOrder(buyOrder)
		require.NoError(t, err)
		require.Len(t, results, 1)

		if (i+1)%1000 == 0 {
			elapsed := time.Since(start)
			t.Logf("[iteration %d] Processing 1000 orders took %v", (i+1)/1000, elapsed)
			start = time.Now() // Reset timer
			assert.Less(t, elapsed, 100*time.Millisecond)
		}
	}
}

func TestGetDepthSlowdown(t *testing.T) {
	mockBM := &mockBalanceManager{}
	engine := NewSymbolEngine("2/3", mockBM)

	var symbol types.Symbol = "2/3"

	numUsers := 1000
	users := make([]types.UserID, 0, numUsers)
	for i := 0; i < numUsers; i++ {
		users = append(users, types.UserID(fmt.Sprintf("user%d", i)))
	}

	// Worker pattern implementation with 16 workers
	const numWorkers = 16
	const batchSize = 100000
	const totalJobs = batchSize * 10

	// Job represents a single order processing task
	type Job struct {
		ID       int
		UserID   types.UserID
		JobType  string // "buy1", "buy2", "sell2", "cancelall"
		BatchNum int
	}

	// Result represents the outcome of a job
	type Result struct {
		JobID    int
		BatchNum int
		Success  bool
		Error    error
		Duration time.Duration
	}

	// Create channels
	jobs := make(chan Job, numWorkers*2)       // Buffered job queue
	results := make(chan Result, numWorkers*2) // Buffered result queue
	done := make(chan bool, numWorkers)        // Worker completion signals

	// Start workers
	for w := 0; w < numWorkers; w++ {
		go func(workerID int) {
			defer func() { done <- true }()

			for job := range jobs {
				startTime := time.Now()
				var err error
				var success bool = true

				// Process the job based on type
				switch job.JobType {
				case "buy1":
					tx := &types.Order{
						OrderID:   types.OrderID(fmt.Sprintf("%d_buy_%s_w%d", job.ID, job.UserID, workerID)),
						UserID:    job.UserID,
						Symbol:    symbol,
						Side:      types.BUY,
						Price:     scale18(1),
						OrderType: types.LIMIT,
						Quantity:  scale18(1),
						OrigQty:   scale18(1),
						Status:    types.NEW,
					}
					_, err = engine.ProcessOrder(tx)
					if err != nil {
						success = false
					}

				case "buy2":
					tx := &types.Order{
						OrderID:   types.OrderID(fmt.Sprintf("%d_buy_%s_w%d", job.ID, job.UserID, workerID)),
						UserID:    job.UserID,
						Symbol:    symbol,
						Side:      types.BUY,
						Price:     scale18(2),
						OrderType: types.LIMIT,
						Quantity:  scale18(1),
						OrigQty:   scale18(1),
						Status:    types.NEW,
					}
					_, err = engine.ProcessOrder(tx)
					if err != nil {
						success = false
					}

				case "sell2":
					tx := &types.Order{
						OrderID:   types.OrderID(fmt.Sprintf("%d_sell_%s_w%d", job.ID, job.UserID, workerID)),
						UserID:    job.UserID,
						Symbol:    symbol,
						Side:      types.SELL,
						Price:     scale18(2),
						OrderType: types.LIMIT,
						Quantity:  scale18(1),
						OrigQty:   scale18(1),
						Status:    types.NEW,
					}
					_, err = engine.ProcessOrder(tx)
					if err != nil {
						success = false
					}

				case "cancelall":
					engine.CancelAllOrders(job.UserID)
				}

				// Send result
				results <- Result{
					JobID:    job.ID,
					BatchNum: job.BatchNum,
					Success:  success,
					Error:    err,
					Duration: time.Since(startTime),
				}
			}
		}(w)
	}

	// Result collector goroutine
	batchResults := make(map[int][]Result)
	var batchMutex sync.Mutex

	go func() {
		for result := range results {
			batchMutex.Lock()
			if batchResults[result.BatchNum] == nil {
				batchResults[result.BatchNum] = make([]Result, 0, batchSize)
			}
			batchResults[result.BatchNum] = append(batchResults[result.BatchNum], result)

			// Check if batch is complete and log results
			if len(batchResults[result.BatchNum]) == batchSize {
				batch := batchResults[result.BatchNum]

				// Calculate batch statistics
				var totalDuration time.Duration
				var successCount int
				var errorCount int

				for _, r := range batch {
					totalDuration += r.Duration
					if r.Success {
						successCount++
					} else {
						errorCount++
					}
				}

				avgDuration := totalDuration / time.Duration(len(batch))
				t.Logf("[batch %d] Processed %d orders: %d success, %d errors, avg time %v, total batch time %v",
					result.BatchNum, len(batch), successCount, errorCount, avgDuration, totalDuration)
				assert.Less(t, avgDuration, 1*time.Millisecond)

				// Clean up processed batch
				delete(batchResults, result.BatchNum)
			}
			batchMutex.Unlock()
		}
	}()

	// Producer: Generate jobs
	go func() {
		defer close(jobs)

		for i := 0; i < totalJobs; i++ {
			batchNum := i / batchSize

			user := users[i%numUsers]
			randNum := rand.Intn(100)

			var jobType string
			switch {
			case randNum < 50:
				jobType = "buy1"
			case randNum < 72:
				jobType = "buy2"
			case randNum < 95:
				jobType = "sell2"
			default:
				jobType = "cancelall"
			}

			jobs <- Job{
				ID:       i,
				UserID:   user,
				JobType:  jobType,
				BatchNum: batchNum,
			}
		}
	}()

	// Wait for all workers to complete
	for i := 0; i < numWorkers; i++ {
		<-done
	}

	// Close results channel and wait for result collector to finish
	close(results)
	time.Sleep(100 * time.Millisecond) // Give result collector time to finish

	t.Logf("Completed processing %d orders with %d workers", totalJobs, numWorkers)
}
