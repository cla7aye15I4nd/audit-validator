package dispatcher

import (
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/mocks"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestOrderCacheMemoryLeak tests that fully filled orders are properly removed from cache
func TestOrderCacheMemoryLeak(t *testing.T) {
	// Test data
	symbol := types.Symbol("ETH/USDT")

	t.Run("FullyFilledOrdersRemoved", func(t *testing.T) {
		// Setup dispatcher for this test
		dispatcher := NewDispatcher(nil)
		dispatcher.Start()
		defer dispatcher.Stop()

		// Create mock state DB
		mockStateDB := mocks.NewMockStateDB()
		user1 := common.HexToAddress("0x1")
		user2 := common.HexToAddress("0x2")
		// Set token balances with 18 decimals
		usdtBalance := new(uint256.Int).Mul(uint256.NewInt(1000000), uint256.NewInt(1e18))
		ethBalance := new(uint256.Int).Mul(uint256.NewInt(1000), uint256.NewInt(1e18))
		mockStateDB.SetTokenBalance(user1, "USDT", usdtBalance)
		mockStateDB.SetTokenBalance(user2, "ETH", ethBalance)
		// Create matching buy and sell orders
		// Price: 1000 USDT per ETH (with 18 decimals)
		price := new(uint256.Int).Mul(uint256.NewInt(1000), uint256.NewInt(1e18))
		// Quantity: 10 ETH (with 18 decimals)
		quantity := new(uint256.Int).Mul(uint256.NewInt(10), uint256.NewInt(1e18))

		buyOrder := &types.Order{
			OrderID:   types.OrderID("buy_full_1"),
			UserID:    types.UserID(user1.Hex()), // Use address as UserID
			Symbol:    symbol,
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     price,
			Quantity:  quantity,
			OrigQty:   quantity,
			Timestamp: time.Now().Unix(),
		}

		sellOrder := &types.Order{
			OrderID:   types.OrderID("sell_full_1"),
			UserID:    types.UserID(user2.Hex()), // Use address as UserID
			Symbol:    symbol,
			Side:      types.SELL,
			OrderType: types.LIMIT,
			Price:     price,
			Quantity:  quantity,
			OrigQty:   quantity,
			Timestamp: time.Now().Unix() + 1,
		}

		// Place buy order
		buyReq := interfaces.NewOrderRequest(buyOrder, mockStateDB, nil)
		dispatcher.DispatchReq(buyReq)
		buyResp := <-buyReq.ResponseChannel()
		if err := buyResp.Error(); err != nil {
			t.Fatalf("Failed to place buy order: %v", err)
		}

		// Check buy order is in cache
		assert.NotNil(t, dispatcher.GetCachedOrder("buy_full_1"), "Buy order should be cached")

		// Place matching sell order
		sellReq := interfaces.NewOrderRequest(sellOrder, mockStateDB, nil)
		dispatcher.DispatchReq(sellReq)
		sellResp := <-sellReq.ResponseChannel()
		require.NoError(t, sellResp.Error())

		// Wait for async processing
		time.Sleep(100 * time.Millisecond)

		// Both orders should be removed from cache after full match
		assert.Nil(t, dispatcher.GetCachedOrder("buy_full_1"), "Fully filled buy order should not be in cache")
		assert.Nil(t, dispatcher.GetCachedOrder("sell_full_1"), "Fully filled sell order should not be in cache")

		// Verify trades were created
		orderResp := sellResp.(*interfaces.OrderResponse)
		assert.NotEmpty(t, orderResp.Trades, "Trades should be generated")
	})

	t.Run("PartiallyFilledOrdersRemain", func(t *testing.T) {
		// Setup dispatcher for this test
		dispatcher := NewDispatcher(nil)
		dispatcher.Start()
		defer dispatcher.Stop()

		// Create mock state DB
		mockStateDB := mocks.NewMockStateDB()
		user1 := common.HexToAddress("0x1")
		user2 := common.HexToAddress("0x2")
		usdtBalance := new(uint256.Int).Mul(uint256.NewInt(1000000), uint256.NewInt(1e18))
		ethBalance := new(uint256.Int).Mul(uint256.NewInt(1000), uint256.NewInt(1e18))
		mockStateDB.SetTokenBalance(user1, "USDT", usdtBalance)
		mockStateDB.SetTokenBalance(user2, "ETH", ethBalance)
		// Price: 1000 USDT per ETH (with 18 decimals)
		price := new(uint256.Int).Mul(uint256.NewInt(1000), uint256.NewInt(1e18))
		// Large quantity: 50 ETH
		largeQty := new(uint256.Int).Mul(uint256.NewInt(50), uint256.NewInt(1e18))
		// Small quantity: 10 ETH
		smallQty := new(uint256.Int).Mul(uint256.NewInt(10), uint256.NewInt(1e18))

		// Large buy order
		buyOrder := &types.Order{
			OrderID:   types.OrderID("buy_partial_1"),
			UserID:    types.UserID(user1.Hex()),
			Symbol:    symbol,
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     price,
			Quantity:  largeQty,
			OrigQty:   largeQty,
			Timestamp: time.Now().Unix(),
		}

		// Small sell order
		sellOrder := &types.Order{
			OrderID:   types.OrderID("sell_partial_1"),
			UserID:    types.UserID(user2.Hex()),
			Symbol:    symbol,
			Side:      types.SELL,
			OrderType: types.LIMIT,
			Price:     price,
			Quantity:  smallQty,
			OrigQty:   smallQty,
			Timestamp: time.Now().Unix() + 1,
		}

		// Place orders
		buyReq := interfaces.NewOrderRequest(buyOrder, mockStateDB, nil)
		dispatcher.DispatchReq(buyReq)
		<-buyReq.ResponseChannel()

		sellReq := interfaces.NewOrderRequest(sellOrder, mockStateDB, nil)
		dispatcher.DispatchReq(sellReq)
		<-sellReq.ResponseChannel()

		// Wait for processing
		time.Sleep(100 * time.Millisecond)

		// Buy order should remain (partially filled), sell order should be removed (fully filled)
		assert.NotNil(t, dispatcher.GetCachedOrder("buy_partial_1"), "Partially filled order should remain in cache")
		assert.Nil(t, dispatcher.GetCachedOrder("sell_partial_1"), "Fully filled order should be removed")
	})

	t.Run("MarketOrdersAlwaysRemoved", func(t *testing.T) {
		// Setup dispatcher for this test
		dispatcher := NewDispatcher(nil)
		dispatcher.Start()
		defer dispatcher.Stop()

		// Create mock state DB
		mockStateDB := mocks.NewMockStateDB()
		user1 := common.HexToAddress("0x1")
		usdtBalance := new(uint256.Int).Mul(uint256.NewInt(1000000), uint256.NewInt(1e18))
		mockStateDB.SetTokenBalance(user1, "USDT", usdtBalance)
		// Quantity: 10 ETH (with 18 decimals)
		quantity := new(uint256.Int).Mul(uint256.NewInt(10), uint256.NewInt(1e18))

		// Market order without any liquidity
		marketOrder := &types.Order{
			OrderID:   types.OrderID("market_1"),
			UserID:    types.UserID(user1.Hex()),
			Symbol:    symbol,
			Side:      types.BUY,
			OrderType: types.MARKET,
			Quantity:  quantity,
			OrigQty:   quantity,
			Timestamp: time.Now().Unix(),
		}

		// Place market order
		marketReq := interfaces.NewOrderRequest(marketOrder, mockStateDB, nil)
		dispatcher.DispatchReq(marketReq)
		<-marketReq.ResponseChannel()

		// Wait for processing
		time.Sleep(100 * time.Millisecond)

		// Market order should always be removed
		assert.Nil(t, dispatcher.GetCachedOrder("market_1"), "Market order should always be removed from cache")
	})

	t.Run("ModifyOrderCacheUpdate", func(t *testing.T) {
		// Setup dispatcher for this test
		dispatcher := NewDispatcher(nil)
		dispatcher.Start()
		defer dispatcher.Stop()

		// Create mock state DB
		mockStateDB := mocks.NewMockStateDB()
		user1 := common.HexToAddress("0x1")
		user2 := common.HexToAddress("0x2")
		usdtBalance := new(uint256.Int).Mul(uint256.NewInt(1000000), uint256.NewInt(1e18))
		ethBalance := new(uint256.Int).Mul(uint256.NewInt(1000), uint256.NewInt(1e18))
		mockStateDB.SetTokenBalance(user1, "USDT", usdtBalance)
		mockStateDB.SetTokenBalance(user2, "ETH", ethBalance)
		// Prices with 18 decimals
		lowPrice := new(uint256.Int).Mul(uint256.NewInt(900), uint256.NewInt(1e18))
		highPrice := new(uint256.Int).Mul(uint256.NewInt(1000), uint256.NewInt(1e18))
		// Quantity: 10 ETH (with 18 decimals)
		quantity := new(uint256.Int).Mul(uint256.NewInt(10), uint256.NewInt(1e18))

		// Place initial order
		order := &types.Order{
			OrderID:   types.OrderID("modify_old"),
			UserID:    types.UserID(user1.Hex()),
			Symbol:    symbol,
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     lowPrice,
			Quantity:  quantity,
			OrigQty:   quantity,
			Timestamp: time.Now().Unix(),
		}

		orderReq := interfaces.NewOrderRequest(order, mockStateDB, nil)
		dispatcher.DispatchReq(orderReq)
		<-orderReq.ResponseChannel()

		// Place sell order at higher price
		sellOrder := &types.Order{
			OrderID:   types.OrderID("sell_modify"),
			UserID:    types.UserID(user2.Hex()),
			Symbol:    symbol,
			Side:      types.SELL,
			OrderType: types.LIMIT,
			Price:     highPrice,
			Quantity:  quantity,
			OrigQty:   quantity,
			Timestamp: time.Now().Unix() + 1,
		}

		sellReq := interfaces.NewOrderRequest(sellOrder, mockStateDB, nil)
		dispatcher.DispatchReq(sellReq)
		<-sellReq.ResponseChannel()

		// Modify buy order to match
		modifyArgs := &types.ModifyArgs{
			OrderID:     "modify_old",
			NewOrderID:  "modify_new",
			NewPrice:    highPrice,
			NewQuantity: quantity,
		}
		modifyReq := interfaces.NewModifyRequest(modifyArgs, mockStateDB, nil)
		dispatcher.DispatchReq(modifyReq)
		<-modifyReq.ResponseChannel()

		// Wait for processing
		time.Sleep(100 * time.Millisecond)

		// Old order removed, new order removed (fully filled), sell order removed (fully filled)
		assert.Nil(t, dispatcher.GetCachedOrder("modify_old"), "Old order ID should be removed")
		assert.Nil(t, dispatcher.GetCachedOrder("modify_new"), "Modified order should be removed after full fill")
		assert.Nil(t, dispatcher.GetCachedOrder("sell_modify"), "Matched sell order should be removed")
	})

	t.Run("CancelOrderRemovesFromCache", func(t *testing.T) {
		// Setup dispatcher for this test
		dispatcher := NewDispatcher(nil)
		dispatcher.Start()
		defer dispatcher.Stop()

		// Create mock state DB
		mockStateDB := mocks.NewMockStateDB()
		user1 := common.HexToAddress("0x1")
		usdtBalance := new(uint256.Int).Mul(uint256.NewInt(1000000), uint256.NewInt(1e18))
		mockStateDB.SetTokenBalance(user1, "USDT", usdtBalance)
		// Price and quantity with 18 decimals
		price := new(uint256.Int).Mul(uint256.NewInt(1000), uint256.NewInt(1e18))
		quantity := new(uint256.Int).Mul(uint256.NewInt(10), uint256.NewInt(1e18))

		// Place order
		order := &types.Order{
			OrderID:   types.OrderID("cancel_1"),
			UserID:    types.UserID(user1.Hex()),
			Symbol:    symbol,
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     price,
			Quantity:  quantity,
			OrigQty:   quantity,
			Timestamp: time.Now().Unix(),
		}

		orderReq := interfaces.NewOrderRequest(order, mockStateDB, nil)
		dispatcher.DispatchReq(orderReq)
		<-orderReq.ResponseChannel()

		// Verify in cache
		assert.NotNil(t, dispatcher.GetCachedOrder("cancel_1"), "Order should be in cache")

		// Cancel order
		cancelReq := interfaces.NewCancelRequest("cancel_1", mockStateDB, nil)
		dispatcher.DispatchReq(cancelReq)
		<-cancelReq.ResponseChannel()

		// Wait for processing
		time.Sleep(100 * time.Millisecond)

		// Order should be removed
		assert.Nil(t, dispatcher.GetCachedOrder("cancel_1"), "Cancelled order should be removed from cache")
	})

	t.Run("CancelAllRemovesAllOrders", func(t *testing.T) {
		// Setup dispatcher for this test
		dispatcher := NewDispatcher(nil)
		dispatcher.Start()
		defer dispatcher.Stop()

		// Create mock state DB
		mockStateDB := mocks.NewMockStateDB()
		user3 := common.HexToAddress("0x3")
		userID := user3.Hex()
		// Set balance for user3
		usdtBalance := new(uint256.Int).Mul(uint256.NewInt(1000000), uint256.NewInt(1e18))
		mockStateDB.SetTokenBalance(user3, "USDT", usdtBalance)

		// Base quantity with 18 decimals
		quantity := new(uint256.Int).Mul(uint256.NewInt(10), uint256.NewInt(1e18))

		// Place multiple orders
		for i := 1; i <= 3; i++ {
			// Different prices for each order (900, 910, 920 with 18 decimals)
			price := new(uint256.Int).Mul(uint256.NewInt(uint64(900+i*10)), uint256.NewInt(1e18))

			order := &types.Order{
				OrderID:   types.OrderID(string("multi_") + string(rune('0'+i))),
				UserID:    types.UserID(userID),
				Symbol:    symbol,
				Side:      types.BUY,
				OrderType: types.LIMIT,
				Price:     price,
				Quantity:  quantity,
				OrigQty:   quantity,
				Timestamp: time.Now().Unix() + int64(i),
			}

			orderReq := interfaces.NewOrderRequest(order, mockStateDB, nil)
			dispatcher.DispatchReq(orderReq)
			<-orderReq.ResponseChannel()
		}

		// Verify all in cache
		assert.NotNil(t, dispatcher.GetCachedOrder("multi_1"))
		assert.NotNil(t, dispatcher.GetCachedOrder("multi_2"))
		assert.NotNil(t, dispatcher.GetCachedOrder("multi_3"))

		// Cancel all
		cancelAllReq := interfaces.NewCancelAllRequest(userID, mockStateDB, nil)
		dispatcher.DispatchReq(cancelAllReq)
		<-cancelAllReq.ResponseChannel()

		// Wait for processing
		time.Sleep(100 * time.Millisecond)

		// All should be removed
		assert.Nil(t, dispatcher.GetCachedOrder("multi_1"), "All orders should be removed")
		assert.Nil(t, dispatcher.GetCachedOrder("multi_2"), "All orders should be removed")
		assert.Nil(t, dispatcher.GetCachedOrder("multi_3"), "All orders should be removed")
	})

	t.Run("BalanceLocksProperlyRemoved", func(t *testing.T) {
		// Setup dispatcher for this test
		dispatcher := NewDispatcher(nil)
		dispatcher.Start()
		defer dispatcher.Stop()

		// Create mock state DB
		mockStateDB := mocks.NewMockStateDB()
		user1 := common.HexToAddress("0x1")
		user2 := common.HexToAddress("0x2")
		// Set token balances with 18 decimals
		usdtBalance := new(uint256.Int).Mul(uint256.NewInt(1000000), uint256.NewInt(1e18))
		ethBalance := new(uint256.Int).Mul(uint256.NewInt(1000), uint256.NewInt(1e18))
		mockStateDB.SetTokenBalance(user1, "USDT", usdtBalance)
		mockStateDB.SetTokenBalance(user2, "ETH", ethBalance)

		// Price and quantity with 18 decimals
		price := new(uint256.Int).Mul(uint256.NewInt(1000), uint256.NewInt(1e18))
		quantity := new(uint256.Int).Mul(uint256.NewInt(10), uint256.NewInt(1e18))

		// Place matching orders
		buyOrder := &types.Order{
			OrderID:   types.OrderID("buy_lock_1"),
			UserID:    types.UserID(user1.Hex()),
			Symbol:    symbol,
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     price,
			Quantity:  quantity,
			OrigQty:   quantity,
			Timestamp: time.Now().Unix(),
		}

		sellOrder := &types.Order{
			OrderID:   types.OrderID("sell_lock_1"),
			UserID:    types.UserID(user2.Hex()),
			Symbol:    symbol,
			Side:      types.SELL,
			OrderType: types.LIMIT,
			Price:     price,
			Quantity:  quantity,
			OrigQty:   quantity,
			Timestamp: time.Now().Unix() + 1,
		}

		// Place buy order
		buyReq := interfaces.NewOrderRequest(buyOrder, mockStateDB, nil)
		dispatcher.DispatchReq(buyReq)
		<-buyReq.ResponseChannel()

		// Verify balance lock exists for buy order
		hasLock := dispatcher.balanceManager.HasLock("buy_lock_1")
		assert.True(t, hasLock, "Buy order should have balance lock")

		// Place matching sell order
		sellReq := interfaces.NewOrderRequest(sellOrder, mockStateDB, nil)
		dispatcher.DispatchReq(sellReq)
		<-sellReq.ResponseChannel()

		// Wait for processing
		time.Sleep(100 * time.Millisecond)

		// Both orders should be removed from cache (fully filled)
		assert.Nil(t, dispatcher.GetCachedOrder("buy_lock_1"), "Fully filled buy order should not be in cache")
		assert.Nil(t, dispatcher.GetCachedOrder("sell_lock_1"), "Fully filled sell order should not be in cache")

		// Balance locks should also be removed
		hasLock = dispatcher.balanceManager.HasLock("buy_lock_1")
		assert.False(t, hasLock, "Balance lock should be removed for fully filled buy order")

		hasLock = dispatcher.balanceManager.HasLock("sell_lock_1")
		assert.False(t, hasLock, "Balance lock should be removed for fully filled sell order")
	})

	t.Run("PartialFillKeepsBalanceLock", func(t *testing.T) {
		// Setup dispatcher for this test
		dispatcher := NewDispatcher(nil)
		dispatcher.Start()
		defer dispatcher.Stop()

		// Create mock state DB
		mockStateDB := mocks.NewMockStateDB()
		user1 := common.HexToAddress("0x1")
		user2 := common.HexToAddress("0x2")
		// Set token balances
		usdtBalance := new(uint256.Int).Mul(uint256.NewInt(1000000), uint256.NewInt(1e18))
		ethBalance := new(uint256.Int).Mul(uint256.NewInt(1000), uint256.NewInt(1e18))
		mockStateDB.SetTokenBalance(user1, "USDT", usdtBalance)
		mockStateDB.SetTokenBalance(user2, "ETH", ethBalance)

		// Price and quantities
		price := new(uint256.Int).Mul(uint256.NewInt(1000), uint256.NewInt(1e18))
		largeQty := new(uint256.Int).Mul(uint256.NewInt(50), uint256.NewInt(1e18))
		smallQty := new(uint256.Int).Mul(uint256.NewInt(10), uint256.NewInt(1e18))

		// Large buy order
		buyOrder := &types.Order{
			OrderID:   types.OrderID("buy_partial_lock"),
			UserID:    types.UserID(user1.Hex()),
			Symbol:    symbol,
			Side:      types.BUY,
			OrderType: types.LIMIT,
			Price:     price,
			Quantity:  largeQty,
			OrigQty:   largeQty,
			Timestamp: time.Now().Unix(),
		}

		// Small sell order
		sellOrder := &types.Order{
			OrderID:   types.OrderID("sell_partial_lock"),
			UserID:    types.UserID(user2.Hex()),
			Symbol:    symbol,
			Side:      types.SELL,
			OrderType: types.LIMIT,
			Price:     price,
			Quantity:  smallQty,
			OrigQty:   smallQty,
			Timestamp: time.Now().Unix() + 1,
		}

		// Place orders
		buyReq := interfaces.NewOrderRequest(buyOrder, mockStateDB, nil)
		dispatcher.DispatchReq(buyReq)
		<-buyReq.ResponseChannel()

		sellReq := interfaces.NewOrderRequest(sellOrder, mockStateDB, nil)
		dispatcher.DispatchReq(sellReq)
		<-sellReq.ResponseChannel()

		// Wait for processing
		time.Sleep(100 * time.Millisecond)

		// Buy order should remain (partially filled)
		assert.NotNil(t, dispatcher.GetCachedOrder("buy_partial_lock"), "Partially filled order should remain in cache")
		// Sell order should be removed (fully filled)
		assert.Nil(t, dispatcher.GetCachedOrder("sell_partial_lock"), "Fully filled order should be removed")

		// Balance lock should remain for partially filled order
		hasLock := dispatcher.balanceManager.HasLock("buy_partial_lock")
		assert.True(t, hasLock, "Balance lock should remain for partially filled order")

		// Balance lock should be removed for fully filled order
		hasLock = dispatcher.balanceManager.HasLock("sell_partial_lock")
		assert.False(t, hasLock, "Balance lock should be removed for fully filled order")
	})
}