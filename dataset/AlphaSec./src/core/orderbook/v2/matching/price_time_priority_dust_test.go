package matching

import (
	"testing"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/book"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
)

// MockMarketValidator for testing dust scenarios
type MockMarketValidator struct {
	lotSize *types.Quantity
}

func NewMockMarketValidator(lotSizeStr string) *MockMarketValidator {
	ls, _ := uint256.FromDecimal(lotSizeStr)
	return &MockMarketValidator{
		lotSize: ls,
	}
}

func (m *MockMarketValidator) ValidateOrder(order *types.Order) error {
	return nil
}

func (m *MockMarketValidator) ValidateOrderPrice(price *types.Price) error {
	return nil
}

func (m *MockMarketValidator) ValidateOrderQuantity(price, quantity *types.Quantity) error {
	return nil
}

func (m *MockMarketValidator) ValidateMinimumOrderValue(price, quantity *types.Quantity) error {
	return nil
}

func (m *MockMarketValidator) ValidateMarketOrder(quantity *types.Quantity, bestPrice *types.Price, side types.OrderSide, orderMode types.OrderMode) error {
	return nil
}

func (m *MockMarketValidator) GetTickSize(price *types.Price) *types.Quantity {
	tickSize, _ := uint256.FromDecimal("1000000000000000") // 0.001 * 10^18
	return tickSize
}

func (m *MockMarketValidator) GetLotSize(price *types.Price) *types.Quantity {
	return m.lotSize
}

func (m *MockMarketValidator) GetMinimumLotSize() *types.Quantity {
	minLot, _ := uint256.FromDecimal("10000000000000") // 0.00001 * 10^18
	return minLot
}

func (m *MockMarketValidator) RoundPriceToTickSize(price *types.Price, roundUp bool) *types.Price {
	return price
}

func (m *MockMarketValidator) RoundQuantityToLotSize(price, quantity *types.Quantity, roundUp bool) *types.Quantity {
	return quantity
}

func (m *MockMarketValidator) RoundDownToLotSize(price, quantity *types.Quantity) (*types.Quantity, bool) {
	if quantity == nil || price == nil {
		return quantity, false
	}

	lotSize := m.GetLotSize(price)
	if lotSize == nil || lotSize.IsZero() {
		return quantity, false
	}

	remainder := new(uint256.Int)
	remainder.Mod(quantity, lotSize)

	if remainder.IsZero() {
		return quantity, false
	}

	// Round down by subtracting remainder
	rounded := new(uint256.Int).Sub(quantity, remainder)
	return rounded, true
}

func (m *MockMarketValidator) IsQuantityDust(quantity, price *types.Quantity) bool {
	if quantity == nil || price == nil {
		return false
	}

	lotSize := m.GetLotSize(price)
	return quantity.Cmp(lotSize) < 0
}

// Helper functions
func createDustTestOrder(orderID string, userID string, side types.OrderSide, orderType types.OrderType, priceStr, quantityStr string) *types.Order {
	var price *uint256.Int
	if priceStr != "0" {
		price, _ = uint256.FromDecimal(priceStr)
	}

	quantity, _ := uint256.FromDecimal(quantityStr)

	order := &types.Order{
		OrderID:   types.OrderID(orderID),
		UserID:    types.UserID(userID),
		Symbol:    "ETH/USDC",
		Side:      side,
		OrderType: orderType,
		Price:     price,
		Quantity:  quantity,
		OrigQty:   quantity.Clone(),
		Status:    types.PENDING,
		Timestamp: types.TimeNow(),
	}

	return order
}

func createDustTestOrderWithTPSL(orderID string, userID string, side types.OrderSide, orderType types.OrderType, priceStr, quantityStr string) *types.Order {
	order := createDustTestOrder(orderID, userID, side, orderType, priceStr, quantityStr)

	// Add TPSL context
	tpPrice, _ := uint256.FromDecimal("2000000000000000000000") // 2000 * 10^18
	slTrigger, _ := uint256.FromDecimal("500000000000000000000") // 500 * 10^18

	order.TPSL = &types.TPSLContext{
		TPLimitPrice:   tpPrice,
		SLTriggerPrice: slTrigger,
	}

	return order
}

// Test Cases

func TestMatchMarketOrder_PassiveDustRemoval(t *testing.T) {
	// Test that passive orders with dust quantity are removed from orderbook

	// Setup: lot size = 0.1 * 10^18
	validator := NewMockMarketValidator("100000000000000000")
	matcher := NewPriceTimePriority("ETH/USDC", validator)
	orderBook := book.NewOrderBook("ETH/USDC")

	// Add passive sell order with dust quantity (0.05 * 10^18 < 0.1 * 10^18 lot size)
	passiveOrder := createDustTestOrder("sell1", "seller1", types.SELL, types.LIMIT,
		"1000000000000000000000", // price: 1000 * 10^18
		"50000000000000000")      // qty: 0.05 * 10^18
	err := orderBook.AddOrder(passiveOrder)
	assert.NoError(t, err, "Should be able to add order to orderbook")

	// Verify the order is in the orderbook
	checkOrder, exists := orderBook.GetOrder(types.OrderID("sell1"))
	assert.True(t, exists, "Order should exist in orderbook before matching")
	assert.NotNil(t, checkOrder)
	assert.Equal(t, "50000000000000000", checkOrder.Quantity.String())

	// Create market buy order
	marketOrder := createDustTestOrder("buy1", "buyer1", types.BUY, types.MARKET,
		"0",                      // market order has no price
		"1000000000000000000")    // qty: 1.0 * 10^18

	// Execute matching
	result, err := matcher.MatchOrder(marketOrder, orderBook)

	// Assertions
	assert.NoError(t, err)
	assert.Len(t, result.Trades, 0, "No trades should be executed with dust passive order")
	assert.Equal(t, "0", result.FilledQuantity.String(), "No quantity should be filled")

	// Check that dust passive order was removed
	removedOrder, exists := orderBook.GetOrder(types.OrderID("sell1"))
	assert.False(t, exists, "Dust passive order should be removed from orderbook")
	assert.Nil(t, removedOrder, "Removed order should be nil")

	// Verify the passive order status was set to FILLED
	assert.Equal(t, types.FILLED, passiveOrder.Status, "Dust passive order should be marked as FILLED")
}

func TestMatchMarketOrder_PassiveDustRemovalWithTPSL(t *testing.T) {
	// Test that passive orders with TPSL and dust quantity are properly handled

	validator := NewMockMarketValidator("100000000000000000") // 0.1 * 10^18
	matcher := NewPriceTimePriority("ETH/USDC", validator)
	orderBook := book.NewOrderBook("ETH/USDC")

	// Add passive sell order with TPSL and dust quantity
	passiveOrder := createDustTestOrderWithTPSL("sell1", "seller1", types.SELL, types.LIMIT,
		"1000000000000000000000", // price: 1000 * 10^18
		"50000000000000000")      // qty: 0.05 * 10^18 (dust)
	err := orderBook.AddOrder(passiveOrder)
	assert.NoError(t, err)

	// Verify TPSL is set
	assert.NotNil(t, passiveOrder.TPSL, "Order should have TPSL context")
	assert.NotNil(t, passiveOrder.TPSL.TPLimitPrice)
	assert.NotNil(t, passiveOrder.TPSL.SLTriggerPrice)

	// Create market buy order
	marketOrder := createDustTestOrder("buy1", "buyer1", types.BUY, types.MARKET,
		"0",
		"1000000000000000000") // qty: 1.0 * 10^18

	// Execute matching
	result, err := matcher.MatchOrder(marketOrder, orderBook)

	// Assertions
	assert.NoError(t, err)
	assert.Len(t, result.Trades, 0, "No trades should be executed")
	assert.Len(t, result.FilledOrdersWithTPSL, 1, "Dust passive order with TPSL should be included in FilledOrdersWithTPSL")
	assert.Equal(t, types.OrderID("sell1"), result.FilledOrdersWithTPSL[0].OrderID)
	assert.Equal(t, types.FILLED, result.FilledOrdersWithTPSL[0].Status, "Order in TPSL list should be marked FILLED")

	// Check removal from orderbook
	_, exists := orderBook.GetOrder(types.OrderID("sell1"))
	assert.False(t, exists, "Dust passive order should be removed")

	// Verify the original order status
	assert.Equal(t, types.FILLED, passiveOrder.Status, "Original order should be marked as FILLED")
}

func TestMatchLimitOrder_AggressiveDustHandling(t *testing.T) {
	// Test that aggressive limit orders with dust remainder are marked as FILLED

	validator := NewMockMarketValidator("100000000000000000") // 0.1 * 10^18
	matcher := NewPriceTimePriority("ETH/USDC", validator)
	orderBook := book.NewOrderBook("ETH/USDC")

	// Add passive sell order with quantity 1.0
	passiveOrder := createDustTestOrder("sell1", "seller1", types.SELL, types.LIMIT,
		"1000000000000000000000",  // price: 1000 * 10^18
		"1000000000000000000")     // qty: 1.0 * 10^18
	orderBook.AddOrder(passiveOrder)

	// Create limit buy order with quantity 1.05 (will have 0.05 dust remainder)
	limitOrder := createDustTestOrder("buy1", "buyer1", types.BUY, types.LIMIT,
		"1000000000000000000000",  // price: 1000 * 10^18
		"1050000000000000000")     // qty: 1.05 * 10^18

	// Execute matching
	result, err := matcher.MatchOrder(limitOrder, orderBook)

	// Assertions
	assert.NoError(t, err)
	assert.Len(t, result.Trades, 1, "One trade should be executed")
	assert.Equal(t, "1000000000000000000", result.Trades[0].Quantity.String(), "Trade quantity should be 1.0")
	assert.Equal(t, types.FILLED, limitOrder.Status, "Aggressive order with dust remainder should be FILLED")
	assert.Nil(t, result.RemainingOrder, "No remaining order should be added to orderbook for dust")
}

func TestMatchLimitOrder_AggressiveDustWithTPSL(t *testing.T) {
	// Test that aggressive limit orders with TPSL and dust remainder are properly handled

	validator := NewMockMarketValidator("100000000000000000") // 0.1 * 10^18
	matcher := NewPriceTimePriority("ETH/USDC", validator)
	orderBook := book.NewOrderBook("ETH/USDC")

	// Add passive sell order
	passiveOrder := createDustTestOrder("sell1", "seller1", types.SELL, types.LIMIT,
		"1000000000000000000000",
		"1000000000000000000") // qty: 1.0 * 10^18
	orderBook.AddOrder(passiveOrder)

	// Create limit buy order with TPSL and quantity that will leave dust
	limitOrder := createDustTestOrderWithTPSL("buy1", "buyer1", types.BUY, types.LIMIT,
		"1000000000000000000000",
		"1050000000000000000") // qty: 1.05 * 10^18

	// Execute matching
	result, err := matcher.MatchOrder(limitOrder, orderBook)

	// Assertions
	assert.NoError(t, err)
	assert.Len(t, result.FilledOrdersWithTPSL, 1, "Aggressive order with TPSL and dust should be in FilledOrdersWithTPSL")
	assert.Equal(t, types.OrderID("buy1"), result.FilledOrdersWithTPSL[0].OrderID, "Should be the aggressive order")
	assert.Equal(t, types.FILLED, limitOrder.Status, "Aggressive order should be marked as FILLED")
	assert.Nil(t, result.RemainingOrder, "No remaining order should be added to orderbook")
}

func TestMatchMarketQuoteMode_PassiveDustRemoval(t *testing.T) {
	// Test dust removal in quote mode market orders

	validator := NewMockMarketValidator("100000000000000000") // 0.1 * 10^18
	matcher := NewPriceTimePriority("ETH/USDC", validator)
	orderBook := book.NewOrderBook("ETH/USDC")

	// Add passive sell order with dust quantity
	passiveOrder := createDustTestOrder("sell1", "seller1", types.SELL, types.LIMIT,
		"1000000000000000000000",  // price: 1000 * 10^18
		"50000000000000000")       // qty: 0.05 * 10^18 (dust)
	orderBook.AddOrder(passiveOrder)

	// Create market buy order in quote mode (spending 1000 USDC)
	marketOrder := createDustTestOrder("buy1", "buyer1", types.BUY, types.MARKET,
		"0",
		"1000000000000000000000") // quote amount: 1000 * 10^18
	marketOrder.OrderMode = types.QUOTE_MODE

	// Execute matching
	result, err := matcher.MatchOrder(marketOrder, orderBook)

	// Assertions
	assert.NoError(t, err)
	assert.Len(t, result.Trades, 0, "No trades should be executed with dust passive order")

	// Check removal
	_, exists := orderBook.GetOrder(types.OrderID("sell1"))
	assert.False(t, exists, "Dust passive order should be removed")
}

func TestMatchOrder_NoDustRemovalForValidQuantity(t *testing.T) {
	// Test that valid (non-dust) passive orders are NOT removed

	validator := NewMockMarketValidator("100000000000000000") // 0.1 * 10^18
	matcher := NewPriceTimePriority("ETH/USDC", validator)
	orderBook := book.NewOrderBook("ETH/USDC")

	// Add passive sell order with valid quantity (0.2, which is >= lot size)
	passiveOrder := createDustTestOrder("sell1", "seller1", types.SELL, types.LIMIT,
		"1000000000000000000000",  // price: 1000 * 10^18
		"200000000000000000")      // qty: 0.2 * 10^18 (valid, not dust)
	orderBook.AddOrder(passiveOrder)

	// Create small market buy order that can't fully execute (dust taker)
	marketOrder := createDustTestOrder("buy1", "buyer1", types.BUY, types.MARKET,
		"0",
		"50000000000000000") // qty: 0.05 * 10^18 (dust)

	// Execute matching
	result, err := matcher.MatchOrder(marketOrder, orderBook)

	// Assertions
	assert.NoError(t, err)
	assert.Len(t, result.Trades, 0, "No trades due to dust taker quantity")

	// Check that valid passive order is still there
	remainingOrder, exists := orderBook.GetOrder(types.OrderID("sell1"))
	assert.True(t, exists, "Valid passive order should NOT be removed")
	assert.NotNil(t, remainingOrder, "Valid passive order should still exist")
	assert.Equal(t, "200000000000000000", remainingOrder.Quantity.String(), "Quantity should be unchanged")
}

func TestMatchLimitOrder_MultiplePassiveOrders(t *testing.T) {
	// Test matching with multiple passive orders, some with dust

	validator := NewMockMarketValidator("100000000000000000") // 0.1 * 10^18
	matcher := NewPriceTimePriority("ETH/USDC", validator)
	orderBook := book.NewOrderBook("ETH/USDC")

	// Add multiple passive sell orders
	dustOrder := createDustTestOrder("sell1", "seller1", types.SELL, types.LIMIT,
		"1000000000000000000000",  // price: 1000 * 10^18
		"50000000000000000")       // qty: 0.05 * 10^18 (dust)

	validOrder := createDustTestOrder("sell2", "seller2", types.SELL, types.LIMIT,
		"1001000000000000000000",  // price: 1001 * 10^18
		"200000000000000000")      // qty: 0.2 * 10^18

	orderBook.AddOrder(dustOrder)
	orderBook.AddOrder(validOrder)

	// Create limit buy order
	limitOrder := createDustTestOrder("buy1", "buyer1", types.BUY, types.LIMIT,
		"1002000000000000000000",  // price: 1002 * 10^18
		"300000000000000000")      // qty: 0.3 * 10^18

	// Execute matching
	result, err := matcher.MatchOrder(limitOrder, orderBook)

	// Assertions
	assert.NoError(t, err)

	// Dust order should be removed without trade
	_, dustExists := orderBook.GetOrder(types.OrderID("sell1"))
	assert.False(t, dustExists, "Dust order should be removed")

	// Valid order should be traded
	assert.Len(t, result.Trades, 1, "One trade with valid order")
	assert.Equal(t, types.OrderID("sell2"), result.Trades[0].MakerOrderID, "Trade should be with valid order")
	assert.Equal(t, "200000000000000000", result.Trades[0].Quantity.String(), "Trade quantity should be 0.2")
}

func TestMatchLimitOrder_PartialFillBecomingDust(t *testing.T) {
	// Test scenario where passive order becomes dust after partial execution

	validator := NewMockMarketValidator("100000000000000000") // 0.1 * 10^18
	matcher := NewPriceTimePriority("ETH/USDC", validator)
	orderBook := book.NewOrderBook("ETH/USDC")

	// Add passive sell order with quantity 0.15 (valid initially)
	passiveOrder := createDustTestOrder("sell1", "seller1", types.SELL, types.LIMIT,
		"1000000000000000000000",  // price: 1000 * 10^18
		"150000000000000000")      // qty: 0.15 * 10^18
	err := orderBook.AddOrder(passiveOrder)
	assert.NoError(t, err)
	assert.Equal(t, types.PENDING, passiveOrder.Status)

	// First trade: buy 0.1, leaving 0.05 (dust)
	limitOrder1 := createDustTestOrder("buy1", "buyer1", types.BUY, types.LIMIT,
		"1000000000000000000000",
		"100000000000000000") // qty: 0.1 * 10^18

	result1, err := matcher.MatchOrder(limitOrder1, orderBook)
	assert.NoError(t, err)
	assert.Len(t, result1.Trades, 1, "First trade should execute")
	assert.Equal(t, "100000000000000000", result1.Trades[0].Quantity.String())
	assert.Equal(t, types.FILLED, limitOrder1.Status, "First buy order should be filled")

	// Check passive order still exists with dust quantity
	remainingOrder, exists := orderBook.GetOrder(types.OrderID("sell1"))
	assert.True(t, exists, "Passive order should still exist after partial fill")
	assert.Equal(t, "50000000000000000", remainingOrder.Quantity.String(), "Should have 0.05 remaining")
	assert.Equal(t, types.PARTIALLY_FILLED, remainingOrder.Status, "Should be partially filled")

	// Second trade attempt: should remove dust passive order
	limitOrder2 := createDustTestOrder("buy2", "buyer2", types.BUY, types.LIMIT,
		"1000000000000000000000",
		"100000000000000000") // qty: 0.1 * 10^18

	result2, err := matcher.MatchOrder(limitOrder2, orderBook)
	assert.NoError(t, err)
	assert.Len(t, result2.Trades, 0, "No trade with dust passive order")

	// Dust passive order should be removed
	_, exists = orderBook.GetOrder(types.OrderID("sell1"))
	assert.False(t, exists, "Dust passive order should be removed")

	// The second buy order should remain in orderbook as it couldn't match
	assert.NotNil(t, result2.RemainingOrder, "Buy order should remain")
	assert.Equal(t, "100000000000000000", result2.RemainingOrder.Quantity.String(), "Full quantity should remain")
}

// Additional edge case tests

func TestMatchOrder_ExactLotSize(t *testing.T) {
	// Test with exact lot size (boundary condition)

	validator := NewMockMarketValidator("100000000000000000") // 0.1 * 10^18
	matcher := NewPriceTimePriority("ETH/USDC", validator)
	orderBook := book.NewOrderBook("ETH/USDC")

	// Add passive order with exact lot size
	passiveOrder := createDustTestOrder("sell1", "seller1", types.SELL, types.LIMIT,
		"1000000000000000000000",  // price: 1000 * 10^18
		"100000000000000000")      // qty: 0.1 * 10^18 (exact lot size)
	err := orderBook.AddOrder(passiveOrder)
	assert.NoError(t, err)

	// Create market buy order
	marketOrder := createDustTestOrder("buy1", "buyer1", types.BUY, types.MARKET,
		"0",
		"100000000000000000") // qty: 0.1 * 10^18

	// Execute matching - should work normally
	result, err := matcher.MatchOrder(marketOrder, orderBook)
	assert.NoError(t, err)
	assert.Len(t, result.Trades, 1, "Trade should execute with exact lot size")
	assert.Equal(t, "100000000000000000", result.Trades[0].Quantity.String())

	// Passive order should be removed (fully filled)
	_, exists := orderBook.GetOrder(types.OrderID("sell1"))
	assert.False(t, exists, "Fully filled order should be removed")
}

func TestMatchOrder_JustAboveDust(t *testing.T) {
	// Test with quantity just above dust threshold

	validator := NewMockMarketValidator("100000000000000000") // 0.1 * 10^18
	matcher := NewPriceTimePriority("ETH/USDC", validator)
	orderBook := book.NewOrderBook("ETH/USDC")

	// Add passive order with 2 lot sizes (0.2)
	passiveOrder := createDustTestOrder("sell1", "seller1", types.SELL, types.LIMIT,
		"1000000000000000000000",  // price: 1000 * 10^18
		"200000000000000000")      // qty: 0.2 * 10^18 (2 lot sizes)
	err := orderBook.AddOrder(passiveOrder)
	assert.NoError(t, err)

	// Create market buy order with 0.11 (will round down to 0.1)
	marketOrder := createDustTestOrder("buy1", "buyer1", types.BUY, types.MARKET,
		"0",
		"110000000000000000") // qty: 0.11 * 10^18

	// Execute matching - should round down to 0.1
	result, err := matcher.MatchOrder(marketOrder, orderBook)
	assert.NoError(t, err)
	assert.Len(t, result.Trades, 1, "Trade should execute")
	assert.Equal(t, "100000000000000000", result.Trades[0].Quantity.String(), "Should round down to lot size")

	// Check remaining - should have 0.1 left (valid)
	remaining, exists := orderBook.GetOrder(types.OrderID("sell1"))
	assert.True(t, exists, "Order should still exist with valid remainder")
	assert.Equal(t, "100000000000000000", remaining.Quantity.String(), "Should have 0.1 remaining (valid)")
}

func TestMatchOrder_DustZeroQuantity(t *testing.T) {
	// Test with zero quantity (edge case)

	validator := NewMockMarketValidator("100000000000000000") // 0.1 * 10^18
	matcher := NewPriceTimePriority("ETH/USDC", validator)
	orderBook := book.NewOrderBook("ETH/USDC")

	// Try to create order with zero quantity
	zeroOrder := createDustTestOrder("buy1", "buyer1", types.BUY, types.MARKET,
		"0",
		"0") // qty: 0

	// Execute matching - should handle gracefully
	result, err := matcher.MatchOrder(zeroOrder, orderBook)
	assert.NoError(t, err)
	assert.Len(t, result.Trades, 0, "No trades with zero quantity")
	assert.Equal(t, "0", result.FilledQuantity.String())
}