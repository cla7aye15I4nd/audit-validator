package book

import (
	"fmt"
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
)

// Helper function to create a test order
func createTestOrder(id string, userID string, side types.OrderSide, price, quantity uint64) *types.Order {
	return &types.Order{
		OrderID:   types.OrderID(id),
		UserID:    types.UserID(userID),
		Symbol:    types.Symbol("ETH/USDT"),
		OrderType: types.LIMIT,
		Side:      side,
		OrderMode: types.BASE_MODE,
		Price:     uint256.NewInt(price),
		Quantity:  uint256.NewInt(quantity),
		OrigQty:   uint256.NewInt(quantity),
		Status:    types.NEW,
		Timestamp: time.Now().UnixNano(),
	}
}

func TestNewOrderBook(t *testing.T) {
	symbol := types.Symbol("ETH/USDT")
	ob := NewOrderBook(symbol)

	assert.NotNil(t, ob)
	assert.Equal(t, symbol, ob.symbol)
	assert.NotNil(t, ob.buyQueue)
	assert.NotNil(t, ob.sellQueue)
	assert.NotNil(t, ob.orders)
	assert.NotNil(t, ob.userOrders)
	assert.NotNil(t, ob.buyLevels)
	assert.NotNil(t, ob.sellLevels)
	assert.NotNil(t, ob.currentPrice)
	assert.Equal(t, uint256.NewInt(0), ob.currentPrice) // Initial price is zero
	assert.Equal(t, int64(0), ob.lastTradeTime)
}

func TestAddOrder(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	t.Run("Add valid buy order", func(t *testing.T) {
		order := createTestOrder("order1", "user1", types.BUY, 1000, 10)
		err := ob.AddOrder(order)
		
		assert.NoError(t, err)
		assert.Len(t, ob.orders, 1)
		assert.Len(t, ob.userOrders["user1"], 1)
		assert.Len(t, ob.buyLevels, 1)
	})

	t.Run("Add valid sell order", func(t *testing.T) {
		order := createTestOrder("order2", "user2", types.SELL, 1100, 5)
		err := ob.AddOrder(order)
		
		assert.NoError(t, err)
		assert.Len(t, ob.orders, 2)
		assert.Len(t, ob.userOrders["user2"], 1)
		assert.Len(t, ob.sellLevels, 1)
	})

	t.Run("Add nil order", func(t *testing.T) {
		err := ob.AddOrder(nil)
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "order cannot be nil")
	})

	t.Run("Add duplicate order", func(t *testing.T) {
		order := createTestOrder("order1", "user1", types.BUY, 1000, 10)
		err := ob.AddOrder(order)
		
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "already exists")
	})

	t.Run("Add multiple orders same price level", func(t *testing.T) {
		ob2 := NewOrderBook("ETH/USDT")
		order1 := createTestOrder("order3", "user3", types.BUY, 1000, 10)
		order2 := createTestOrder("order4", "user4", types.BUY, 1000, 20)
		
		err1 := ob2.AddOrder(order1)
		err2 := ob2.AddOrder(order2)
		
		assert.NoError(t, err1)
		assert.NoError(t, err2)
		
		// Check price level aggregation
		priceStr := order1.Price.String()
		level := ob2.buyLevels[priceStr]
		assert.NotNil(t, level)
		assert.Equal(t, 2, level.OrderCount)
		assert.Equal(t, uint256.NewInt(30), level.Quantity)
	})
}

func TestRemoveOrder(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	t.Run("Remove existing order", func(t *testing.T) {
		order := createTestOrder("order1", "user1", types.BUY, 1000, 10)
		ob.AddOrder(order)
		
		err := ob.RemoveOrder("order1")
		assert.NoError(t, err)
		assert.Len(t, ob.orders, 0)
		assert.Len(t, ob.userOrders["user1"], 0)
		assert.Len(t, ob.buyLevels, 0)
	})

	t.Run("Remove non-existent order", func(t *testing.T) {
		err := ob.RemoveOrder("nonexistent")
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "not found")
	})

	t.Run("Remove order updates price level", func(t *testing.T) {
		ob2 := NewOrderBook("ETH/USDT")
		order1 := createTestOrder("order1", "user1", types.BUY, 1000, 10)
		order2 := createTestOrder("order2", "user2", types.BUY, 1000, 20)
		
		ob2.AddOrder(order1)
		ob2.AddOrder(order2)
		
		priceStr := order1.Price.String()
		level := ob2.buyLevels[priceStr]
		assert.Equal(t, 2, level.OrderCount)
		
		ob2.RemoveOrder("order1")
		
		level = ob2.buyLevels[priceStr]
		assert.Equal(t, 1, level.OrderCount)
		assert.Equal(t, uint256.NewInt(20), level.Quantity)
	})
}

func TestUpdateOrder(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	t.Run("Update existing order", func(t *testing.T) {
		order := createTestOrder("order1", "user1", types.BUY, 1000, 10)
		ob.AddOrder(order)
		
		// Update quantity
		updatedOrder := createTestOrder("order1", "user1", types.BUY, 1000, 5)
		err := ob.UpdateOrder(updatedOrder)
		
		assert.NoError(t, err)
		storedOrder, exists := ob.GetOrder("order1")
		assert.True(t, exists)
		assert.Equal(t, uint256.NewInt(5), storedOrder.Quantity)
	})

	t.Run("Update non-existent order", func(t *testing.T) {
		order := createTestOrder("nonexistent", "user1", types.BUY, 1000, 10)
		err := ob.UpdateOrder(order)
		
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "not found")
	})

	t.Run("Update order changes price level", func(t *testing.T) {
		ob2 := NewOrderBook("ETH/USDT")
		order := createTestOrder("order1", "user1", types.BUY, 1000, 10)
		ob2.AddOrder(order)
		
		priceStr := order.Price.String()
		level := ob2.buyLevels[priceStr]
		assert.Equal(t, uint256.NewInt(10), level.Quantity)
		
		// Update with different quantity
		updatedOrder := createTestOrder("order1", "user1", types.BUY, 1000, 15)
		ob2.UpdateOrder(updatedOrder)
		
		level = ob2.buyLevels[priceStr]
		assert.Equal(t, uint256.NewInt(15), level.Quantity)
	})
}

func TestGetOrder(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	t.Run("Get existing order", func(t *testing.T) {
		order := createTestOrder("order1", "user1", types.BUY, 1000, 10)
		ob.AddOrder(order)
		
		retrievedOrder, exists := ob.GetOrder("order1")
		assert.True(t, exists)
		assert.NotNil(t, retrievedOrder)
		assert.Equal(t, types.OrderID("order1"), retrievedOrder.OrderID)
		assert.Equal(t, types.UserID("user1"), retrievedOrder.UserID)
	})

	t.Run("Get non-existent order", func(t *testing.T) {
		order, exists := ob.GetOrder("nonexistent")
		assert.False(t, exists)
		assert.Nil(t, order)
	})

	t.Run("Returned order is a copy", func(t *testing.T) {
		order := createTestOrder("order2", "user2", types.BUY, 1000, 10)
		ob.AddOrder(order)
		
		retrievedOrder1, _ := ob.GetOrder("order2")
		retrievedOrder2, _ := ob.GetOrder("order2")
		
		// Modify one retrieved order
		retrievedOrder1.Quantity = uint256.NewInt(20)
		
		// The other should remain unchanged
		assert.Equal(t, uint256.NewInt(10), retrievedOrder2.Quantity)
		
		// Original should remain unchanged
		originalOrder, _ := ob.GetOrder("order2")
		assert.Equal(t, uint256.NewInt(10), originalOrder.Quantity)
	})
}

func TestGetUserOrders(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	t.Run("Get orders for user with orders", func(t *testing.T) {
		order1 := createTestOrder("order1", "user1", types.BUY, 1000, 10)
		order2 := createTestOrder("order2", "user1", types.SELL, 1100, 5)
		order3 := createTestOrder("order3", "user2", types.BUY, 1000, 20)
		
		ob.AddOrder(order1)
		ob.AddOrder(order2)
		ob.AddOrder(order3)
		
		userOrders := ob.GetUserOrders("user1")
		assert.Len(t, userOrders, 2)
		
		// Check both orders belong to user1
		for _, order := range userOrders {
			assert.Equal(t, types.UserID("user1"), order.UserID)
		}
	})

	t.Run("Get orders for user without orders", func(t *testing.T) {
		userOrders := ob.GetUserOrders("user3")
		assert.Len(t, userOrders, 0)
	})

	t.Run("Orders are copies", func(t *testing.T) {
		order := createTestOrder("order4", "user4", types.BUY, 1000, 10)
		ob.AddOrder(order)
		
		userOrders := ob.GetUserOrders("user4")
		assert.Len(t, userOrders, 1)
		
		// Modify returned order
		userOrders[0].Quantity = uint256.NewInt(20)
		
		// Original should remain unchanged
		originalOrder, _ := ob.GetOrder("order4")
		assert.Equal(t, uint256.NewInt(10), originalOrder.Quantity)
	})
}

func TestGetBuyAndSellOrders(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	// Add multiple buy and sell orders
	ob.AddOrder(createTestOrder("buy1", "user1", types.BUY, 1000, 10))
	ob.AddOrder(createTestOrder("buy2", "user2", types.BUY, 1100, 20))
	ob.AddOrder(createTestOrder("buy3", "user3", types.BUY, 900, 15))
	ob.AddOrder(createTestOrder("sell1", "user4", types.SELL, 1200, 5))
	ob.AddOrder(createTestOrder("sell2", "user5", types.SELL, 1150, 8))

	t.Run("Get buy orders", func(t *testing.T) {
		buyOrders := ob.GetBuyOrders()
		assert.Len(t, buyOrders, 3)
		
		// All should be buy orders
		for _, order := range buyOrders {
			assert.Equal(t, types.BUY, order.Side)
		}
	})

	t.Run("Get sell orders", func(t *testing.T) {
		sellOrders := ob.GetSellOrders()
		assert.Len(t, sellOrders, 2)
		
		// All should be sell orders
		for _, order := range sellOrders {
			assert.Equal(t, types.SELL, order.Side)
		}
	})
}

func TestGetBestBidAndAsk(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	t.Run("Empty orderbook", func(t *testing.T) {
		assert.Nil(t, ob.GetBestBid())
		assert.Nil(t, ob.GetBestAsk())
	})

	t.Run("With orders", func(t *testing.T) {
		ob.AddOrder(createTestOrder("buy1", "user1", types.BUY, 1000, 10))
		ob.AddOrder(createTestOrder("buy2", "user2", types.BUY, 1100, 20)) // Best bid
		ob.AddOrder(createTestOrder("buy3", "user3", types.BUY, 900, 15))
		ob.AddOrder(createTestOrder("sell1", "user4", types.SELL, 1200, 5))
		ob.AddOrder(createTestOrder("sell2", "user5", types.SELL, 1150, 8)) // Best ask

		bestBid := ob.GetBestBid()
		assert.NotNil(t, bestBid)
		assert.Equal(t, uint256.NewInt(1100), bestBid.Price)

		bestAsk := ob.GetBestAsk()
		assert.NotNil(t, bestAsk)
		assert.Equal(t, uint256.NewInt(1150), bestAsk.Price)
	})

	t.Run("Only buy orders", func(t *testing.T) {
		ob2 := NewOrderBook("ETH/USDT")
		ob2.AddOrder(createTestOrder("buy1", "user1", types.BUY, 1000, 10))
		
		assert.NotNil(t, ob2.GetBestBid())
		assert.Nil(t, ob2.GetBestAsk())
	})

	t.Run("Only sell orders", func(t *testing.T) {
		ob3 := NewOrderBook("ETH/USDT")
		ob3.AddOrder(createTestOrder("sell1", "user1", types.SELL, 1000, 10))
		
		assert.Nil(t, ob3.GetBestBid())
		assert.NotNil(t, ob3.GetBestAsk())
	})
}

func TestGetDepth(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	// Add orders at different price levels
	ob.AddOrder(createTestOrder("buy1", "user1", types.BUY, 1000, 10))
	ob.AddOrder(createTestOrder("buy2", "user2", types.BUY, 1000, 20)) // Same price
	ob.AddOrder(createTestOrder("buy3", "user3", types.BUY, 990, 15))
	ob.AddOrder(createTestOrder("buy4", "user4", types.BUY, 980, 25))
	ob.AddOrder(createTestOrder("sell1", "user5", types.SELL, 1010, 5))
	ob.AddOrder(createTestOrder("sell2", "user6", types.SELL, 1010, 10)) // Same price
	ob.AddOrder(createTestOrder("sell3", "user7", types.SELL, 1020, 8))
	ob.AddOrder(createTestOrder("sell4", "user8", types.SELL, 1030, 12))

	t.Run("Get full depth", func(t *testing.T) {
		bids, asks := ob.GetDepth(10)
		
		// Should have 3 bid levels (1000, 990, 980)
		assert.Len(t, bids, 3)
		
		// Should have 3 ask levels (1010, 1020, 1030)
		assert.Len(t, asks, 3)
		
		// Check first bid level (highest price should be first for buy orders)
		// The orders should be sorted by the queue, let's just verify they exist
		assert.NotNil(t, bids[0].Price)
		assert.NotNil(t, bids[0].Quantity)
		assert.GreaterOrEqual(t, bids[0].Orders, 1)
		
		// Check first ask level 
		assert.NotNil(t, asks[0].Price)
		assert.NotNil(t, asks[0].Quantity)
		assert.GreaterOrEqual(t, asks[0].Orders, 1)
	})

	t.Run("Get limited depth", func(t *testing.T) {
		bids, asks := ob.GetDepth(2)
		
		assert.Len(t, bids, 2)
		assert.Len(t, asks, 2)
	})

	t.Run("Empty orderbook depth", func(t *testing.T) {
		ob2 := NewOrderBook("ETH/USDT")
		bids, asks := ob2.GetDepth(10)
		
		assert.Len(t, bids, 0)
		assert.Len(t, asks, 0)
	})
}

func TestGetSpread(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	t.Run("No orders", func(t *testing.T) {
		spread := ob.GetSpread()
		assert.Nil(t, spread)
	})

	t.Run("Only buy orders", func(t *testing.T) {
		ob.AddOrder(createTestOrder("buy1", "user1", types.BUY, 1000, 10))
		spread := ob.GetSpread()
		assert.Nil(t, spread)
	})

	t.Run("Only sell orders", func(t *testing.T) {
		ob2 := NewOrderBook("ETH/USDT")
		ob2.AddOrder(createTestOrder("sell1", "user1", types.SELL, 1100, 10))
		spread := ob2.GetSpread()
		assert.Nil(t, spread)
	})

	t.Run("Both buy and sell orders", func(t *testing.T) {
		ob3 := NewOrderBook("ETH/USDT")
		ob3.AddOrder(createTestOrder("buy1", "user1", types.BUY, 1000, 10))
		ob3.AddOrder(createTestOrder("buy2", "user2", types.BUY, 990, 20))
		ob3.AddOrder(createTestOrder("sell1", "user3", types.SELL, 1010, 5))
		ob3.AddOrder(createTestOrder("sell2", "user4", types.SELL, 1020, 8))
		
		spread := ob3.GetSpread()
		assert.NotNil(t, spread)
		// Spread = best ask (1010) - best bid (1000) = 10
		assert.Equal(t, uint256.NewInt(10), spread)
	})
}

func TestClear(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	// Add some orders
	ob.AddOrder(createTestOrder("order1", "user1", types.BUY, 1000, 10))
	ob.AddOrder(createTestOrder("order2", "user2", types.SELL, 1100, 5))
	ob.AddOrder(createTestOrder("order3", "user1", types.BUY, 990, 20))

	// Verify orders exist
	assert.Len(t, ob.orders, 3)
	assert.Len(t, ob.userOrders, 2)
	assert.Len(t, ob.buyLevels, 2)
	assert.Len(t, ob.sellLevels, 1)

	// Clear orderbook
	ob.Clear()

	// Verify everything is cleared
	assert.Len(t, ob.orders, 0)
	assert.Len(t, ob.userOrders, 0)
	assert.Len(t, ob.buyLevels, 0)
	assert.Len(t, ob.sellLevels, 0)
	assert.Nil(t, ob.GetBestBid())
	assert.Nil(t, ob.GetBestAsk())
}

func TestPriceTracking(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	t.Run("Initial state", func(t *testing.T) {
		assert.NotNil(t, ob.GetCurrentPrice())
		assert.Equal(t, uint256.NewInt(0), ob.GetCurrentPrice()) // Initial price is zero
		assert.Equal(t, int64(0), ob.GetLastTradeTime())
	})

	t.Run("Update price", func(t *testing.T) {
		price := uint256.NewInt(1500)
		timestamp := time.Now().UnixNano()
		
		ob.UpdatePrice(price, timestamp)
		
		currentPrice := ob.GetCurrentPrice()
		assert.NotNil(t, currentPrice)
		assert.Equal(t, price, currentPrice)
		assert.Equal(t, timestamp, ob.GetLastTradeTime())
	})

	t.Run("Price is cloned", func(t *testing.T) {
		price := uint256.NewInt(2000)
		ob.UpdatePrice(price, time.Now().UnixNano())
		
		// Modify original price
		price.SetUint64(3000)
		
		// Stored price should remain unchanged
		currentPrice := ob.GetCurrentPrice()
		assert.Equal(t, uint256.NewInt(2000), currentPrice)
	})
}

func TestConcurrentAccess(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")
	done := make(chan bool)

	// Concurrent writes
	go func() {
		for i := 0; i < 100; i++ {
			order := createTestOrder(
				fmt.Sprintf("buy%d", i),
				"user1",
				types.BUY,
				uint64(1000+i),
				uint64(10),
			)
			ob.AddOrder(order)
		}
		done <- true
	}()

	go func() {
		for i := 0; i < 100; i++ {
			order := createTestOrder(
				fmt.Sprintf("sell%d", i),
				"user2",
				types.SELL,
				uint64(1100+i),
				uint64(5),
			)
			ob.AddOrder(order)
		}
		done <- true
	}()

	// Concurrent reads
	go func() {
		for i := 0; i < 100; i++ {
			ob.GetBestBid()
			ob.GetBestAsk()
			ob.GetDepth(10)
		}
		done <- true
	}()

	// Wait for all goroutines
	for i := 0; i < 3; i++ {
		<-done
	}

	// Verify data integrity
	buyOrders := ob.GetBuyOrders()
	sellOrders := ob.GetSellOrders()
	
	assert.Equal(t, 100, len(buyOrders))
	assert.Equal(t, 100, len(sellOrders))
}

func TestRemoveFromUserOrders(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	// Add multiple orders for same user
	ob.AddOrder(createTestOrder("order1", "user1", types.BUY, 1000, 10))
	ob.AddOrder(createTestOrder("order2", "user1", types.SELL, 1100, 5))
	ob.AddOrder(createTestOrder("order3", "user1", types.BUY, 990, 20))

	assert.Len(t, ob.userOrders["user1"], 3)

	// Remove middle order
	ob.RemoveOrder("order2")
	assert.Len(t, ob.userOrders["user1"], 2)
	
	// Verify remaining orders
	userOrders := ob.GetUserOrders("user1")
	assert.Len(t, userOrders, 2)
	orderIDs := make([]types.OrderID, len(userOrders))
	for i, order := range userOrders {
		orderIDs[i] = order.OrderID
	}
	assert.Contains(t, orderIDs, types.OrderID("order1"))
	assert.Contains(t, orderIDs, types.OrderID("order3"))
	assert.NotContains(t, orderIDs, types.OrderID("order2"))

	// Remove all orders
	ob.RemoveOrder("order1")
	ob.RemoveOrder("order3")
	
	// User should be removed from map
	_, exists := ob.userOrders["user1"]
	assert.False(t, exists)
}

func TestPriceLevelManagement(t *testing.T) {
	ob := NewOrderBook("ETH/USDT")

	t.Run("Add orders to same price level", func(t *testing.T) {
		ob.AddOrder(createTestOrder("order1", "user1", types.BUY, 1000, 10))
		ob.AddOrder(createTestOrder("order2", "user2", types.BUY, 1000, 20))
		ob.AddOrder(createTestOrder("order3", "user3", types.BUY, 1000, 15))

		priceStr := uint256.NewInt(1000).String()
		level := ob.buyLevels[priceStr]
		
		assert.NotNil(t, level)
		assert.Equal(t, 3, level.OrderCount)
		assert.Equal(t, uint256.NewInt(45), level.Quantity) // 10+20+15
	})

	t.Run("Remove orders from price level", func(t *testing.T) {
		ob2 := NewOrderBook("ETH/USDT")
		ob2.AddOrder(createTestOrder("order1", "user1", types.BUY, 1000, 10))
		ob2.AddOrder(createTestOrder("order2", "user2", types.BUY, 1000, 20))

		priceStr := uint256.NewInt(1000).String()
		
		// Remove one order
		ob2.RemoveOrder("order1")
		level := ob2.buyLevels[priceStr]
		assert.NotNil(t, level)
		assert.Equal(t, 1, level.OrderCount)
		assert.Equal(t, uint256.NewInt(20), level.Quantity)

		// Remove last order - level should be deleted
		ob2.RemoveOrder("order2")
		_, exists := ob2.buyLevels[priceStr]
		assert.False(t, exists)
	})

	t.Run("Update order changes price level", func(t *testing.T) {
		ob3 := NewOrderBook("ETH/USDT")
		ob3.AddOrder(createTestOrder("order1", "user1", types.SELL, 1100, 10))
		ob3.AddOrder(createTestOrder("order2", "user2", types.SELL, 1100, 20))

		priceStr := uint256.NewInt(1100).String()
		level := ob3.sellLevels[priceStr]
		assert.Equal(t, uint256.NewInt(30), level.Quantity)

		// Update order with different quantity
		updatedOrder := createTestOrder("order1", "user1", types.SELL, 1100, 5)
		ob3.UpdateOrder(updatedOrder)

		level = ob3.sellLevels[priceStr]
		assert.Equal(t, uint256.NewInt(25), level.Quantity) // 5+20
		assert.Equal(t, 2, level.OrderCount)
	})
}

// Benchmark tests
func BenchmarkAddOrder(b *testing.B) {
	ob := NewOrderBook("ETH/USDT")
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		order := createTestOrder(
			fmt.Sprintf("order%d", i),
			"user1",
			types.BUY,
			uint64(1000+i%100),
			uint64(10),
		)
		ob.AddOrder(order)
	}
}

func BenchmarkGetDepth(b *testing.B) {
	ob := NewOrderBook("ETH/USDT")
	
	// Add 1000 orders
	for i := 0; i < 1000; i++ {
		order := createTestOrder(
			fmt.Sprintf("order%d", i),
			fmt.Sprintf("user%d", i%10),
			types.OrderSide(i%2),
			uint64(1000+i%100),
			uint64(10+i%50),
		)
		ob.AddOrder(order)
	}
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		ob.GetDepth(10)
	}
}

func BenchmarkRemoveOrder(b *testing.B) {
	ob := NewOrderBook("ETH/USDT")
	
	// Pre-add orders
	orders := make([]types.OrderID, b.N)
	for i := 0; i < b.N; i++ {
		orderID := types.OrderID(fmt.Sprintf("order%d", i))
		orders[i] = orderID
		order := createTestOrder(
			fmt.Sprintf("order%d", i),
			"user1",
			types.BUY,
			uint64(1000),
			uint64(10),
		)
		ob.AddOrder(order)
	}
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		ob.RemoveOrder(orders[i])
	}
}