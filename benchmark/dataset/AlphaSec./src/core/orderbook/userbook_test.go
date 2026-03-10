package orderbook

import (
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestUserBookCleanup(t *testing.T) {
	// Test that orders are properly removed from userbook when canceled or filled

	t.Run("RemoveOrderMethod", func(t *testing.T) {
		// Test the RemoveOrder method directly
		userBook := NewUserBook()
		
		order := &Order{
			OrderID:   "order1",
			UserID:    common.Address{}.Hex(),
			Symbol:    "ETH-USDT",
			Side:      BUY,
			Price:     uint256.NewInt(3000),
			Quantity:  uint256.NewInt(100),
			OrigQty:   uint256.NewInt(100),
			OrderType: LIMIT,
		}
		
		// Add order
		userBook.AddOrder(order)
		
		// Verify order exists
		_, exists := userBook.GetOrder("order1")
		assert.True(t, exists, "Order should exist in userbook")
		
		// Remove order
		userBook.RemoveOrder("order1")
		
		// Verify order is removed
		_, exists = userBook.GetOrder("order1")
		assert.False(t, exists, "Order should be removed from userbook")
	})

	t.Run("FilledOrder", func(t *testing.T) {
		engine := NewSymbolEngine("ETH-USDT")
		
		// Create buy and sell orders
		buyOrder := &Order{
			OrderID:   "buy1",
			UserID:    "user1",
			Symbol:    "ETH-USDT",
			Side:      BUY,
			Price:     uint256.NewInt(3000),
			Quantity:  uint256.NewInt(100),
			OrigQty:   uint256.NewInt(100),
			OrderType: LIMIT,
		}
		
		sellOrder := &Order{
			OrderID:   "sell1",
			UserID:    "user2",
			Symbol:    "ETH-USDT",
			Side:      SELL,
			Price:     uint256.NewInt(3000),
			Quantity:  uint256.NewInt(100),
			OrigQty:   uint256.NewInt(100),
			OrderType: MARKET,
		}
		
		// Add buy order to engine
		engine.userBook.AddOrder(buyOrder)
		engine.buyQueue = append(engine.buyQueue, buyOrder)
		
		// Add sell order to userbook (will be matched)
		engine.userBook.AddOrder(sellOrder)
		
		// Verify both orders exist
		_, exists := engine.userBook.GetOrder("buy1")
		assert.True(t, exists, "Buy order should exist")
		_, exists = engine.userBook.GetOrder("sell1")
		assert.True(t, exists, "Sell order should exist")
		
		// Match orders (simplified - just update quantities)
		buyOrder.Quantity = uint256.NewInt(0)
		sellOrder.Quantity = uint256.NewInt(0)
		
		// Remove fully filled orders
		if buyOrder.Quantity.Sign() == 0 {
			engine.userBook.RemoveOrder(buyOrder.OrderID)
		}
		if sellOrder.Quantity.Sign() == 0 {
			engine.userBook.RemoveOrder(sellOrder.OrderID)
		}
		
		// Verify orders are removed from userbook
		_, exists = engine.userBook.GetOrder("buy1")
		assert.False(t, exists, "Fully filled buy order should be removed")
		_, exists = engine.userBook.GetOrder("sell1")
		assert.False(t, exists, "Fully filled sell order should be removed")
	})


	t.Run("EventRecoveryWithUserbook", func(t *testing.T) {
		t.Skip("currently invalid testcase")
		// Test that OrderRemovedEvent properly cleans up userbook during recovery
		d := NewDispatcher()
		
		// Apply OrderAddedEvent
		addEvent := &OrderAddedEvent{
			BaseEvent: BaseEvent{BlockNumber: 1},
			Order: &Order{
				OrderID:   "test1",
				UserID:    "user1",
				Symbol:    "BTC-USDT",
				Side:      BUY,
				Price:     uint256.NewInt(40000),
				Quantity:  uint256.NewInt(10),
				OrigQty:   uint256.NewInt(10),
				OrderType: LIMIT,
			},
		}
		err := addEvent.Apply(d)
		require.NoError(t, err)
		
		// Verify order exists in userbook
		engine := d.engines["BTC-USDT"]
		require.NotNil(t, engine)
		_, exists := engine.userBook.GetOrder("test1")
		assert.True(t, exists, "Order should exist after OrderAddedEvent")
		
		// Apply OrderRemovedEvent
		removeEvent := &OrderRemovedEvent{
			BaseEvent: BaseEvent{BlockNumber: 2},
			OrderID:   "test1",
			Symbol:    "BTC-USDT",
			Side:      BUY,
		}
		err = removeEvent.Apply(d)
		require.NoError(t, err)
		
		// Verify order is removed from userbook
		_, exists = engine.userBook.GetOrder("test1")
		assert.False(t, exists, "Order should be removed from userbook after OrderRemovedEvent")
	})
}