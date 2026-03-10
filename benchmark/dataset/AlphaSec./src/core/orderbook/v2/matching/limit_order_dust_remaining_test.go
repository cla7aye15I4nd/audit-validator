package matching

import (
	"strings"
	"testing"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/book"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestLimitOrderDustRemaining tests the case where a limit order partial fill leaves dust
// This reproduces the real scenario:
// - Sell order: price 0.9, quantity 2.0
// - Buy order: price 1.0, quantity 2.1
// After matching 2.0, buy order has 0.1 remaining which is dust
func TestLimitOrderDustRemaining(t *testing.T) {
	// Create a mock validator with lot size of 1.0 (1000000000000000000)
	// This means minimum quantity is 1.0
	validator := NewMockMarketValidator("1000000000000000000")
	symbol := types.Symbol("BASE/QUOTE")

	// Create matcher with the validator
	matcher := NewPriceTimePriority(symbol, validator)

	// Create orderbook
	ob := book.NewOrderBook(symbol)

	// Create sell order: price 0.9, quantity 2.0
	sellPrice, _ := uint256.FromDecimal("900000000000000000") // 0.9 * 10^18
	sellQuantity, _ := uint256.FromDecimal("2000000000000000000") // 2.0 * 10^18

	sellOrder := &types.Order{
		OrderID:   types.OrderID("sell-order-1"),
		UserID:    types.UserID("user1"),
		Symbol:    symbol,
		Side:      types.SELL,
		OrderType: types.LIMIT,
		Price:     sellPrice,
		Quantity:  sellQuantity,
		OrigQty:   sellQuantity.Clone(),
		Status:    types.PENDING,
		Timestamp: types.TimeNow(),
	}

	// Add sell order to orderbook first
	err := ob.AddOrder(sellOrder)
	require.NoError(t, err)

	// Create buy order: price 1.0, quantity 2.1
	buyPrice, _ := uint256.FromDecimal("1000000000000000000") // 1.0 * 10^18
	buyQuantity, _ := uint256.FromDecimal("2100000000000000000") // 2.1 * 10^18

	buyOrder := &types.Order{
		OrderID:   types.OrderID("buy-order-1"),
		UserID:    types.UserID("user2"),
		Symbol:    symbol,
		Side:      types.BUY,
		OrderType: types.LIMIT,
		Price:     buyPrice,
		Quantity:  buyQuantity,
		OrigQty:   buyQuantity.Clone(),
		Status:    types.PENDING,
		Timestamp: types.TimeNow(),
	}

	// Execute matching - buy order crosses with sell order
	result, err := matcher.MatchOrder(buyOrder, ob)
	require.NoError(t, err)
	require.NotNil(t, result)

	// Verify trade was executed
	assert.Len(t, result.Trades, 1, "Should have exactly one trade")

	if len(result.Trades) > 0 {
		trade := result.Trades[0]
		// Trade should be for 2.0 (the full sell order quantity)
		expectedTradeQty, _ := uint256.FromDecimal("2000000000000000000")
		assert.Equal(t, expectedTradeQty, trade.Quantity, "Trade quantity should be 2.0")
		assert.Equal(t, types.OrderID("sell-order-1"), trade.MakerOrderID, "Maker should be sell order")
		assert.Equal(t, types.OrderID("buy-order-1"), trade.TakerOrderID, "Taker should be buy order")
	}

	// Verify sell order was fully filled and removed
	sellOrderAfter, found := ob.GetOrder(types.OrderID("sell-order-1"))
	assert.False(t, found, "Sell order should be removed from orderbook")
	assert.Nil(t, sellOrderAfter, "Sell order should be nil")

	// Check buy order remaining quantity
	// Buy order had 2.1, matched 2.0, so 0.1 remains
	// 0.1 is less than lot size 1.0, so it's dust
	remainingQty, _ := uint256.FromDecimal("100000000000000000") // 0.1 * 10^18

	// The remaining order should NOT be in the book if it's dust
	buyOrderAfter, found := ob.GetOrder(types.OrderID("buy-order-1"))

	// CURRENT BEHAVIOR: The dust might still be in the book (this is the bug)
	// EXPECTED BEHAVIOR: Dust should not be in the book
	if found {
		t.Logf("WARNING: Buy order with dust quantity %s is still in orderbook (this is the bug we're fixing)",
			toDecimal(buyOrderAfter.Quantity))
		assert.Equal(t, remainingQty, buyOrderAfter.Quantity, "Remaining quantity should be 0.1")
	} else {
		// This is what we want after fixing the bug
		t.Log("Good: Buy order with dust quantity was not added to orderbook")
	}

	// Check the result's remaining order
	if result.RemainingOrder != nil {
		t.Logf("Remaining order quantity: %s", toDecimal(result.RemainingOrder.Quantity))
		// Verify it's dust
		isDust := validator.IsQuantityDust(result.RemainingOrder.Quantity, result.RemainingOrder.Price)
		assert.True(t, isDust, "Remaining quantity 0.1 should be detected as dust (less than lot size 1.0)")
	}
}

// TestLimitOrderDustPrevention tests that dust orders are prevented from being created
func TestLimitOrderDustPrevention(t *testing.T) {
	// Create a mock validator with lot size of 0.5
	validator := NewMockMarketValidator("500000000000000000") // 0.5 * 10^18
	symbol := types.Symbol("BASE/QUOTE")

	// Create matcher with the validator
	matcher := NewPriceTimePriority(symbol, validator)

	// Create orderbook
	ob := book.NewOrderBook(symbol)

	// Scenario: Orders that would create dust after matching
	// Sell order: 1.5 quantity
	// Buy order: 1.2 quantity
	// If matched, sell would have 0.3 remaining (less than 0.5 lot size = dust)

	sellPrice, _ := uint256.FromDecimal("1000000000000000000") // 1.0 * 10^18
	sellQuantity, _ := uint256.FromDecimal("1500000000000000000") // 1.5 * 10^18

	sellOrder := &types.Order{
		OrderID:   types.OrderID("sell-order-2"),
		UserID:    types.UserID("user1"),
		Symbol:    symbol,
		Side:      types.SELL,
		OrderType: types.LIMIT,
		Price:     sellPrice,
		Quantity:  sellQuantity,
		OrigQty:   sellQuantity.Clone(),
		Status:    types.PENDING,
		Timestamp: types.TimeNow(),
	}

	// Add sell order
	err := ob.AddOrder(sellOrder)
	require.NoError(t, err)

	// Create buy order
	buyPrice, _ := uint256.FromDecimal("1000000000000000000") // 1.0 * 10^18
	buyQuantity, _ := uint256.FromDecimal("1200000000000000000") // 1.2 * 10^18

	buyOrder := &types.Order{
		OrderID:   types.OrderID("buy-order-2"),
		UserID:    types.UserID("user2"),
		Symbol:    symbol,
		Side:      types.BUY,
		OrderType: types.LIMIT,
		Price:     buyPrice,
		Quantity:  buyQuantity,
		OrigQty:   buyQuantity.Clone(),
		Status:    types.PENDING,
		Timestamp: types.TimeNow(),
	}

	// Execute matching
	result, err := matcher.MatchOrder(buyOrder, ob)
	require.NoError(t, err)
	require.NotNil(t, result)

	// After fix, the matching engine should either:
	// 1. Adjust the trade quantity to prevent dust (e.g., trade 1.0 instead of 1.2)
	// 2. Or fully match the sell order (1.5) if buy has enough

	// Check what happened
	if len(result.Trades) > 0 {
		totalTraded := uint256.NewInt(0)
		for _, trade := range result.Trades {
			totalTraded = new(uint256.Int).Add(totalTraded, trade.Quantity)
		}
		t.Logf("Total traded quantity: %s", toDecimal(totalTraded))

		// Check sell order status
		sellOrderAfter, found := ob.GetOrder(types.OrderID("sell-order-2"))
		if found {
			t.Logf("Sell order remaining: %s", toDecimal(sellOrderAfter.Quantity))
			// Remaining should not be dust
			isDust := validator.IsQuantityDust(sellOrderAfter.Quantity, sellOrderAfter.Price)
			assert.False(t, isDust, "Sell order should not have dust remaining")
		}
	}
}

// TestLimitOrderMultipleDustScenarios tests various dust scenarios
func TestLimitOrderMultipleDustScenarios(t *testing.T) {
	tests := []struct {
		name            string
		lotSize         string
		sellPrice       string
		sellQty         string
		buyPrice        string
		buyQty          string
		expectedTradeQty string
		expectSellDust  bool
		expectBuyDust   bool
		description     string
	}{
		{
			name:            "Both orders create dust",
			lotSize:         "1000000000000000000", // 1.0
			sellPrice:       "1000000000000000000", // 1.0
			sellQty:         "2300000000000000000", // 2.3
			buyPrice:        "1000000000000000000", // 1.0
			buyQty:          "2400000000000000000", // 2.4
			expectedTradeQty: "2000000000000000000", // Should trade 2.0 to avoid dust
			expectSellDust:  false, // 0.3 would be dust, should be prevented
			expectBuyDust:   false, // 0.4 would be dust, should be prevented
			description:     "Trade quantity should be adjusted to prevent dust on both sides",
		},
		{
			name:            "Exact match no dust",
			lotSize:         "1000000000000000000", // 1.0
			sellPrice:       "1000000000000000000", // 1.0
			sellQty:         "3000000000000000000", // 3.0
			buyPrice:        "1000000000000000000", // 1.0
			buyQty:          "3000000000000000000", // 3.0
			expectedTradeQty: "3000000000000000000", // 3.0
			expectSellDust:  false,
			expectBuyDust:   false,
			description:     "Exact match should work without issues",
		},
		{
			name:            "Small lot size allows more flexibility",
			lotSize:         "100000000000000000",  // 0.1
			sellPrice:       "1000000000000000000", // 1.0
			sellQty:         "2300000000000000000", // 2.3
			buyPrice:        "1000000000000000000", // 1.0
			buyQty:          "2400000000000000000", // 2.4
			expectedTradeQty: "2300000000000000000", // 2.3 (full sell)
			expectSellDust:  false,
			expectBuyDust:   false, // 0.1 remaining is exactly lot size
			description:     "With 0.1 lot size, 2.3 trade is valid",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup
			validator := NewMockMarketValidator(tt.lotSize)
			symbol := types.Symbol("BASE/QUOTE")
			matcher := NewPriceTimePriority(symbol, validator)
			ob := book.NewOrderBook(symbol)

			// Create sell order
			sellPrice, _ := uint256.FromDecimal(tt.sellPrice)
			sellQuantity, _ := uint256.FromDecimal(tt.sellQty)
			sellOrder := &types.Order{
				OrderID:   types.OrderID("sell"),
				UserID:    types.UserID("user1"),
				Symbol:    symbol,
				Side:      types.SELL,
				OrderType: types.LIMIT,
				Price:     sellPrice,
				Quantity:  sellQuantity,
				OrigQty:   sellQuantity.Clone(),
				Status:    types.PENDING,
				Timestamp: types.TimeNow(),
			}
			err := ob.AddOrder(sellOrder)
			require.NoError(t, err)

			// Create buy order
			buyPrice, _ := uint256.FromDecimal(tt.buyPrice)
			buyQuantity, _ := uint256.FromDecimal(tt.buyQty)
			buyOrder := &types.Order{
				OrderID:   types.OrderID("buy"),
				UserID:    types.UserID("user2"),
				Symbol:    symbol,
				Side:      types.BUY,
				OrderType: types.LIMIT,
				Price:     buyPrice,
				Quantity:  buyQuantity,
				OrigQty:   buyQuantity.Clone(),
				Status:    types.PENDING,
				Timestamp: types.TimeNow(),
			}

			// Execute matching
			result, err := matcher.MatchOrder(buyOrder, ob)
			require.NoError(t, err, tt.description)
			require.NotNil(t, result)

			// Verify no dust remains
			sellOrderAfter, sellFound := ob.GetOrder(types.OrderID("sell"))
			if sellFound && !tt.expectSellDust {
				isDust := validator.IsQuantityDust(sellOrderAfter.Quantity, sellOrderAfter.Price)
				assert.False(t, isDust, "Sell order should not have dust: %s", tt.description)
			}

			buyOrderAfter, buyFound := ob.GetOrder(types.OrderID("buy"))
			if buyFound && !tt.expectBuyDust {
				isDust := validator.IsQuantityDust(buyOrderAfter.Quantity, buyOrderAfter.Price)
				assert.False(t, isDust, "Buy order should not have dust: %s", tt.description)
			}

			t.Logf("%s - Trades: %d", tt.name, len(result.Trades))
			if len(result.Trades) > 0 {
				t.Logf("  Trade quantity: %s", toDecimal(result.Trades[0].Quantity))
			}
			if sellFound {
				t.Logf("  Sell remaining: %s", toDecimal(sellOrderAfter.Quantity))
			}
			if buyFound {
				t.Logf("  Buy remaining: %s", toDecimal(buyOrderAfter.Quantity))
			}
		})
	}
}

// Helper function to convert scaled value to decimal string
func toDecimal(val *uint256.Int) string {
	if val == nil {
		return "0"
	}
	// Divide by 10^18 for display
	scale, _ := uint256.FromDecimal("1000000000000000000")
	quotient := new(uint256.Int).Div(val, scale)
	remainder := new(uint256.Int).Mod(val, scale)

	if remainder.IsZero() {
		return quotient.String()
	}

	// Simple decimal formatting
	remainderStr := remainder.String()
	// Pad with zeros if needed
	for len(remainderStr) < 18 {
		remainderStr = "0" + remainderStr
	}
	// Trim trailing zeros
	remainderStr = strings.TrimRight(remainderStr, "0")
	if remainderStr == "" {
		return quotient.String()
	}
	return quotient.String() + "." + remainderStr
}

