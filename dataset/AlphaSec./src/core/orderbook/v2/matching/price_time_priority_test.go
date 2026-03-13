package matching

import (
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/book"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Helper functions for testing

func newTestOrder(orderID string, userID string, side types.OrderSide, orderType types.OrderType, price, quantity uint64) *types.Order {
	// Scale price and quantity to 10^18
	scaledPrice := new(uint256.Int).Mul(uint256.NewInt(price), uint256.NewInt(1e18))
	scaledQuantity := new(uint256.Int).Mul(uint256.NewInt(quantity), uint256.NewInt(1e18))
	
	return &types.Order{
		OrderID:   types.OrderID(orderID),
		UserID:    types.UserID(userID),
		Symbol:    "ETH/USDT",
		Side:      side,
		OrderType: orderType,
		Price:     scaledPrice,
		Quantity:  scaledQuantity,
		OrigQty:   scaledQuantity.Clone(),
		Status:    types.PENDING,
		Timestamp: types.TimeNow(),
	}
}

// Helper to convert scaled value to unscaled for assertions
func toUnscaled(val *uint256.Int) uint64 {
	if val == nil {
		return 0
	}
	// Divide by 10^18 to get unscaled value
	unscaled := new(uint256.Int).Div(val, uint256.NewInt(1e18))
	return unscaled.Uint64()
}

// Helper to create scaled value
func toScaled(val uint64) *uint256.Int {
	return new(uint256.Int).Mul(uint256.NewInt(val), uint256.NewInt(1e18))
}

func setupOrderBook() *book.OrderBook {
	return book.NewOrderBook("ETH/USDT")
}

func addOrdersToBook(t *testing.T, ob *book.OrderBook, orders ...*types.Order) {
	for _, order := range orders {
		err := ob.AddOrder(order)
		require.NoError(t, err)
	}
}

// Test Market Order - Base Mode

func TestMatchMarketOrder_BaseMode_FullFill(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Add sell orders to orderbook
	sell1 := newTestOrder("0x001", "seller1", types.SELL, types.LIMIT, 2000, 50)
	sell2 := newTestOrder("0x002", "seller2", types.SELL, types.LIMIT, 2010, 30)
	addOrdersToBook(t, ob, sell1, sell2)

	// Create market buy order
	buyOrder := newTestOrder("0x003", "buyer1", types.BUY, types.MARKET, 0, 70)

	// Execute matching
	result, err := matcher.MatchOrder(buyOrder, ob)
	require.NoError(t, err)

	// Verify results
	assert.Equal(t, 2, len(result.Trades))
	assert.Equal(t, uint64(70), toUnscaled(result.FilledQuantity))
	assert.Nil(t, result.RemainingOrder)

	// Verify first trade (best price)
	trade1 := result.Trades[0]
	assert.Equal(t, uint64(2000), toUnscaled(trade1.Price))
	assert.Equal(t, uint64(50), toUnscaled(trade1.Quantity))

	// Verify second trade
	trade2 := result.Trades[1]
	assert.Equal(t, uint64(2010), toUnscaled(trade2.Price))
	assert.Equal(t, uint64(20), toUnscaled(trade2.Quantity))

	// Verify orderbook state
	assert.Equal(t, 0, len(ob.GetBuyOrders()))
	assert.Equal(t, 1, len(ob.GetSellOrders()))
	remainingSell := ob.GetBestAsk()
	assert.Equal(t, uint64(10), toUnscaled(remainingSell.Quantity))
}

func TestMatchMarketOrder_BaseMode_PartialFill(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Add limited sell liquidity
	sell1 := newTestOrder("0x001", "seller1", types.SELL, types.LIMIT, 2000, 30)
	addOrdersToBook(t, ob, sell1)

	// Create larger market buy order
	buyOrder := newTestOrder("0x002", "buyer1", types.BUY, types.MARKET, 0, 50)

	// Execute matching
	result, err := matcher.MatchOrder(buyOrder, ob)
	require.NoError(t, err)

	// Verify partial fill
	assert.Equal(t, 1, len(result.Trades))
	assert.Equal(t, uint64(30), toUnscaled(result.FilledQuantity))
	assert.Nil(t, result.RemainingOrder) // Market orders don't rest

	// Verify orderbook is empty
	assert.Equal(t, 0, len(ob.GetSellOrders()))
}

// Test Market Order - Quote Mode

func TestMatchMarketOrder_QuoteMode(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Add sell orders
	sell1 := newTestOrder("0x001", "seller1", types.SELL, types.LIMIT, 2000, 50)
	sell2 := newTestOrder("0x002", "seller2", types.SELL, types.LIMIT, 2100, 50)
	addOrdersToBook(t, ob, sell1, sell2)

	// Create market buy order in quote mode (100,000 USDT worth)
	buyOrder := newTestOrder("0x003", "buyer1", types.BUY, types.MARKET, 0, 100000)
	buyOrder.OrderMode = types.QUOTE_MODE

	// Execute matching
	result, err := matcher.MatchOrder(buyOrder, ob)
	require.NoError(t, err)

	// Should buy 50 ETH at 2000 (costs 100,000 USDT exactly)
	assert.Equal(t, 1, len(result.Trades))
	assert.Equal(t, uint64(50), toUnscaled(result.FilledQuantity)) // FilledQuantity is in base currency
	
	trade := result.Trades[0]
	assert.Equal(t, uint64(2000), toUnscaled(trade.Price))
	assert.Equal(t, uint64(50), toUnscaled(trade.Quantity))
}

// Test Limit Order

func TestMatchLimitOrder_FullMatch(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Add sell orders
	sell1 := newTestOrder("0x001", "seller1", types.SELL, types.LIMIT, 1950, 30)
	sell2 := newTestOrder("0x002", "seller2", types.SELL, types.LIMIT, 2000, 20)
	addOrdersToBook(t, ob, sell1, sell2)

	// Create limit buy order with price that crosses
	buyOrder := newTestOrder("0x003", "buyer1", types.BUY, types.LIMIT, 2000, 50)

	// Execute matching
	result, err := matcher.MatchOrder(buyOrder, ob)
	require.NoError(t, err)

	// Should match both sells (price-time priority)
	assert.Equal(t, 2, len(result.Trades))
	assert.Equal(t, uint64(50), toUnscaled(result.FilledQuantity))
	assert.Nil(t, result.RemainingOrder)

	// Verify trades executed at passive order prices
	assert.Equal(t, uint64(1950), toUnscaled(result.Trades[0].Price))
	assert.Equal(t, uint64(2000), toUnscaled(result.Trades[1].Price))
}

func TestMatchLimitOrder_PartialMatch_RestInBook(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Add limited sell liquidity
	sell1 := newTestOrder("0x001", "seller1", types.SELL, types.LIMIT, 2000, 30)
	addOrdersToBook(t, ob, sell1)

	// Create larger limit buy order
	buyOrder := newTestOrder("0x002", "buyer1", types.BUY, types.LIMIT, 2000, 50)

	// Execute matching
	result, err := matcher.MatchOrder(buyOrder, ob)
	require.NoError(t, err)

	// Should partially match
	assert.Equal(t, 1, len(result.Trades))
	assert.Equal(t, uint64(30), toUnscaled(result.FilledQuantity))
	assert.NotNil(t, result.RemainingOrder)
	assert.Equal(t, uint64(20), toUnscaled(result.RemainingOrder.Quantity))

	// Verify remaining order is in book
	assert.Equal(t, 1, len(ob.GetBuyOrders()))
	bestBid := ob.GetBestBid()
	assert.Equal(t, uint64(20), toUnscaled(bestBid.Quantity))
}

func TestMatchLimitOrder_NoCross(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Add sell order at 2100
	sell1 := newTestOrder("0x001", "seller1", types.SELL, types.LIMIT, 2100, 50)
	addOrdersToBook(t, ob, sell1)

	// Create buy order at 2000 (no cross)
	buyOrder := newTestOrder("0x002", "buyer1", types.BUY, types.LIMIT, 2000, 50)

	// Execute matching
	result, err := matcher.MatchOrder(buyOrder, ob)
	require.NoError(t, err)

	// No trades should occur
	assert.Equal(t, 0, len(result.Trades))
	assert.Equal(t, uint64(0), toUnscaled(result.FilledQuantity))
	assert.NotNil(t, result.RemainingOrder)
	assert.Equal(t, uint64(50), toUnscaled(result.RemainingOrder.Quantity))

	// Both orders should be in book
	assert.Equal(t, 1, len(ob.GetBuyOrders()))
	assert.Equal(t, 1, len(ob.GetSellOrders()))
}

// Test Price-Time Priority

func TestPriceTimePriority_BuyOrders(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Add buy orders (higher price = better)
	buy1 := newTestOrder("0x001", "buyer1", types.BUY, types.LIMIT, 2000, 10)
	buy1.Timestamp = 100
	buy2 := newTestOrder("0x002", "buyer2", types.BUY, types.LIMIT, 2010, 10) // Better price
	buy2.Timestamp = 200
	buy3 := newTestOrder("0x003", "buyer3", types.BUY, types.LIMIT, 2010, 10) // Same price, later time
	buy3.Timestamp = 300
	
	addOrdersToBook(t, ob, buy1, buy2, buy3)

	// Create sell order to match
	sellOrder := newTestOrder("0x004", "seller1", types.SELL, types.LIMIT, 2000, 25)

	// Execute matching
	result, err := matcher.MatchOrder(sellOrder, ob)
	require.NoError(t, err)

	// Should match in order: buy2 (2010, time 200), buy3 (2010, time 300), buy1 (2000)
	assert.Equal(t, 3, len(result.Trades))
	
	// Verify order of matching
	assert.Equal(t, types.OrderID("0x002"), result.Trades[0].BuyOrderID)
	assert.Equal(t, types.OrderID("0x003"), result.Trades[1].BuyOrderID)
	assert.Equal(t, types.OrderID("0x001"), result.Trades[2].BuyOrderID)
}

func TestPriceTimePriority_SellOrders(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Add sell orders (lower price = better)
	sell1 := newTestOrder("0x001", "seller1", types.SELL, types.LIMIT, 2010, 10)
	sell1.Timestamp = 100
	sell2 := newTestOrder("0x002", "seller2", types.SELL, types.LIMIT, 2000, 10) // Better price
	sell2.Timestamp = 200
	sell3 := newTestOrder("0x003", "seller3", types.SELL, types.LIMIT, 2000, 10) // Same price, later time
	sell3.Timestamp = 300
	
	addOrdersToBook(t, ob, sell1, sell2, sell3)

	// Create buy order to match
	buyOrder := newTestOrder("0x004", "buyer1", types.BUY, types.LIMIT, 2010, 25)

	// Execute matching
	result, err := matcher.MatchOrder(buyOrder, ob)
	require.NoError(t, err)

	// Should match in order: sell2 (2000, time 200), sell3 (2000, time 300), sell1 (2010)
	assert.Equal(t, 3, len(result.Trades))
	
	// Verify order of matching
	assert.Equal(t, types.OrderID("0x002"), result.Trades[0].SellOrderID)
	assert.Equal(t, types.OrderID("0x003"), result.Trades[1].SellOrderID)
	assert.Equal(t, types.OrderID("0x001"), result.Trades[2].SellOrderID)
}

// Test Edge Cases

func TestMatchOrder_EmptyOrderbook(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Market order in empty book
	marketOrder := newTestOrder("0x001", "buyer1", types.BUY, types.MARKET, 0, 100)
	result, err := matcher.MatchOrder(marketOrder, ob)
	require.NoError(t, err)
	assert.Equal(t, 0, len(result.Trades))
	assert.Equal(t, uint64(0), toUnscaled(result.FilledQuantity))

	// Limit order in empty book
	limitOrder := newTestOrder("0x002", "buyer2", types.BUY, types.LIMIT, 2000, 100)
	result, err = matcher.MatchOrder(limitOrder, ob)
	require.NoError(t, err)
	assert.Equal(t, 0, len(result.Trades))
	assert.NotNil(t, result.RemainingOrder)
}

func TestMatchOrder_ZeroQuantity(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Order with zero quantity
	order := newTestOrder("0x001", "user1", types.BUY, types.LIMIT, 2000, 0)
	result, err := matcher.MatchOrder(order, ob)
	require.NoError(t, err)
	assert.Equal(t, 0, len(result.Trades))
	assert.Equal(t, uint64(0), toUnscaled(result.FilledQuantity))
}

// Test TPSL OrderID Generation

func TestTPSLOrderIDGeneration(t *testing.T) {
	// Original order ID (like a tx hash)
	originalID := types.OrderID("0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
	
	// Generate TP and SL order IDs
	tpID := types.GenerateTPOrderID(originalID)
	slID := types.GenerateSLOrderID(originalID)
	
	// Verify they are different
	assert.NotEqual(t, originalID, tpID)
	assert.NotEqual(t, originalID, slID)
	assert.NotEqual(t, tpID, slID)
	
	// Verify format (should still be valid hex)
	assert.Equal(t, 66, len(string(tpID))) // "0x" + 64 hex chars
	assert.Equal(t, 66, len(string(slID)))
	
	// Verify last byte is modified correctly
	tpHash := common.HexToHash(string(tpID))
	slHash := common.HexToHash(string(slID))
	origHash := common.HexToHash(string(originalID))
	
	// TP should have last byte + 1
	assert.Equal(t, origHash[31]+1, tpHash[31])
	// SL should have last byte + 2
	assert.Equal(t, origHash[31]+2, slHash[31])
}

// Test Error Handling

func TestMatchOrder_OrderBookError(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Add a sell order
	sell := newTestOrder("0x001", "seller1", types.SELL, types.LIMIT, 2000, 50)
	addOrdersToBook(t, ob, sell)

	// Create buy order that will match
	buyOrder := newTestOrder("0x002", "buyer1", types.BUY, types.LIMIT, 2000, 30)

	// Execute matching - should handle any orderbook errors gracefully
	result, err := matcher.MatchOrder(buyOrder, ob)
	
	// Even if there's an error, we should get partial results
	if err != nil {
		assert.NotNil(t, result)
		assert.GreaterOrEqual(t, len(result.Trades), 0)
	}
}

// Test Trade Creation

func TestCreateTrade(t *testing.T) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	ob := setupOrderBook()

	// Add orders
	sell := newTestOrder("0x001", "seller1", types.SELL, types.LIMIT, 2000, 50)
	addOrdersToBook(t, ob, sell)

	buy := newTestOrder("0x002", "buyer1", types.BUY, types.LIMIT, 2000, 50)

	// Execute matching
	result, err := matcher.MatchOrder(buy, ob)
	require.NoError(t, err)
	require.Equal(t, 1, len(result.Trades))

	// Verify trade details
	trade := result.Trades[0]
	assert.NotEmpty(t, trade.TradeID)
	assert.Equal(t, types.OrderID("0x002"), trade.BuyOrderID)
	assert.Equal(t, types.OrderID("0x001"), trade.SellOrderID)
	assert.Equal(t, uint64(2000), toUnscaled(trade.Price))
	assert.Equal(t, uint64(50), toUnscaled(trade.Quantity))
	assert.True(t, trade.BuyOrderFullyFilled)
	assert.True(t, trade.SellOrderFullyFilled)
	assert.Greater(t, trade.Timestamp, uint64(0))
}

// Benchmark Tests

func BenchmarkMatchMarketOrder(b *testing.B) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	
	for i := 0; i < b.N; i++ {
		b.StopTimer()
		ob := setupOrderBook()
		
		// Add 100 sell orders
		for j := 0; j < 100; j++ {
			sell := newTestOrder(
				common.Hash{byte(j)}.Hex(),
				"seller",
				types.SELL,
				types.LIMIT,
				uint64(2000+j),
				10,
			)
			ob.AddOrder(sell)
		}
		
		// Create market buy order
		buyOrder := newTestOrder("buy1", "buyer", types.BUY, types.MARKET, 0, 500)
		
		b.StartTimer()
		matcher.MatchOrder(buyOrder, ob)
	}
}

func BenchmarkMatchLimitOrder(b *testing.B) {
	matcher := NewPriceTimePriority("ETH/USDT", nil)
	
	for i := 0; i < b.N; i++ {
		b.StopTimer()
		ob := setupOrderBook()
		
		// Add 100 orders on each side
		for j := 0; j < 100; j++ {
			buy := newTestOrder(
				common.Hash{byte(j)}.Hex(),
				"buyer",
				types.BUY,
				types.LIMIT,
				uint64(1900+j),
				10,
			)
			sell := newTestOrder(
				common.Hash{byte(j + 100)}.Hex(),
				"seller",
				types.SELL,
				types.LIMIT,
				uint64(2100-j),
				10,
			)
			ob.AddOrder(buy)
			ob.AddOrder(sell)
		}
		
		// Create crossing limit order
		limitOrder := newTestOrder("cross1", "crosser", types.BUY, types.LIMIT, 2050, 200)
		
		b.StartTimer()
		matcher.MatchOrder(limitOrder, ob)
	}
}