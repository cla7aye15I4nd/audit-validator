package types

import (
	"testing"

	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMarketRules_PriceValidation(t *testing.T) {
	rules := NewMarketRules()

	tests := []struct {
		name      string
		price     string
		expectErr bool
		errMsg    string
	}{
		// Valid prices
		{"Valid price $10000", "10000000000000000000000", false, ""},
		{"Valid price $1000.1", "1000100000000000000000", false, ""},
		{"Valid price $100.12", "100120000000000000000", false, ""},
		{"Valid price $10.123", "10123000000000000000", false, ""},
		{"Valid price $1.1234", "1123400000000000000", false, ""},
		{"Valid price $0.12345", "123450000000000000", false, ""},
		{"Valid price $0.012345", "12345000000000000", false, ""},
		{"Valid price $0.0012345", "1234500000000000", false, ""},
		{"Valid price $0.00012345", "123450000000000", false, ""},
		
		// Invalid prices (too many decimals)
		{"Invalid price $10000.1", "10000100000000000000000", true, "max 0 decimals"},
		{"Invalid price $1000.12", "1000120000000000000000", true, "max 1 decimals"},
		{"Invalid price $100.123", "100123000000000000000", true, "max 2 decimals"},
		{"Invalid price $10.1234", "10123400000000000000", true, "max 3 decimals"},
		{"Invalid price $1.12345", "1123450000000000000", true, "max 4 decimals"},
		{"Invalid price $0.123456", "123456000000000000", true, "max 5 decimals"},
		{"Invalid price $0.0123456", "12345600000000000", true, "max 6 decimals"},
		{"Invalid price $0.00123456", "1234560000000000", true, "max 7 decimals"},
		{"Invalid price $0.000123456", "123456000000000", true, "max 8 decimals"},
		
		// Edge cases
		{"Zero price", "0", true, "price cannot be zero"},
		{"Nil price", "", true, "price cannot be zero"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var price *uint256.Int
			if tt.price != "" {
				price, _ = uint256.FromDecimal(tt.price)
			}
			
			err := rules.ValidateOrderPrice(price)
			
			if tt.expectErr {
				assert.Error(t, err)
				if tt.errMsg != "" {
					assert.Contains(t, err.Error(), tt.errMsg)
				}
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestMarketRules_QuantityValidation(t *testing.T) {
	rules := NewMarketRules()

	tests := []struct {
		name      string
		price     string
		quantity  string
		expectErr bool
		errMsg    string
	}{
		// Price >= $10000: min lot size 0.00001
		{"Valid qty for $10000", "10000000000000000000000", "10000000000000", false, ""}, // 0.00001
		{"Valid qty for $10000", "10000000000000000000000", "20000000000000", false, ""}, // 0.00002
		{"Invalid qty for $10000", "10000000000000000000000", "15000000000000", true, "lot size"}, // 0.000015
		
		// Price >= $1000: min lot size 0.0001
		{"Valid qty for $1000", "1000000000000000000000", "100000000000000", false, ""}, // 0.0001
		{"Valid qty for $1000", "1000000000000000000000", "200000000000000", false, ""}, // 0.0002
		{"Invalid qty for $1000", "1000000000000000000000", "150000000000000", true, "lot size"}, // 0.00015
		
		// Price >= $100: min lot size 0.001
		{"Valid qty for $100", "100000000000000000000", "1000000000000000", false, ""}, // 0.001
		{"Valid qty for $100", "100000000000000000000", "2000000000000000", false, ""}, // 0.002
		{"Invalid qty for $100", "100000000000000000000", "1500000000000000", true, "lot size"}, // 0.0015
		
		// Price >= $10: min lot size 0.01
		{"Valid qty for $10", "10000000000000000000", "10000000000000000", false, ""}, // 0.01
		{"Valid qty for $10", "10000000000000000000", "20000000000000000", false, ""}, // 0.02
		{"Invalid qty for $10", "10000000000000000000", "15000000000000000", true, "lot size"}, // 0.015
		
		// Price >= $1: min lot size 0.1
		{"Valid qty for $1", "1000000000000000000", "100000000000000000", false, ""}, // 0.1
		{"Valid qty for $1", "1000000000000000000", "200000000000000000", false, ""}, // 0.2
		{"Invalid qty for $1", "1000000000000000000", "150000000000000000", true, "lot size"}, // 0.15
		
		// Price >= $0.1: min lot size 1
		{"Valid qty for $0.1", "100000000000000000", "1000000000000000000", false, ""}, // 1
		{"Valid qty for $0.1", "100000000000000000", "2000000000000000000", false, ""}, // 2
		{"Invalid qty for $0.1", "100000000000000000", "1500000000000000000", true, "lot size"}, // 1.5
		
		// Edge cases
		{"Zero quantity", "1000000000000000000", "0", true, "quantity cannot be zero"},
		{"Nil quantity", "1000000000000000000", "", true, "quantity cannot be zero"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			price, _ := uint256.FromDecimal(tt.price)
			var quantity *uint256.Int
			if tt.quantity != "" {
				quantity, _ = uint256.FromDecimal(tt.quantity)
			}
			
			err := rules.ValidateOrderQuantity(price, quantity)
			
			if tt.expectErr {
				assert.Error(t, err)
				if tt.errMsg != "" {
					assert.Contains(t, err.Error(), tt.errMsg)
				}
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestMarketRules_MinimumOrderValue(t *testing.T) {
	rules := NewMarketRules()

	tests := []struct {
		name      string
		price     string
		quantity  string
		expectErr bool
		errMsg    string
	}{
		// Valid orders (>= $1)
		{"$10 * 0.1 = $1", "10000000000000000000", "100000000000000000", false, ""},
		{"$1 * 1 = $1", "1000000000000000000", "1000000000000000000", false, ""},
		{"$0.1 * 10 = $1", "100000000000000000", "10000000000000000000", false, ""},
		{"$2 * 0.5 = $1", "2000000000000000000", "500000000000000000", false, ""},
		{"$100 * 0.01 = $1", "100000000000000000000", "10000000000000000", false, ""},
		
		// Invalid orders (< $1)
		{"$0.1 * 1 = $0.1", "100000000000000000", "1000000000000000000", true, "at least $1"},
		{"$0.5 * 1 = $0.5", "500000000000000000", "1000000000000000000", true, "at least $1"},
		{"$1 * 0.5 = $0.5", "1000000000000000000", "500000000000000000", true, "at least $1"},
		{"$10 * 0.01 = $0.1", "10000000000000000000", "10000000000000000", true, "at least $1"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			price, _ := uint256.FromDecimal(tt.price)
			quantity, _ := uint256.FromDecimal(tt.quantity)
			
			err := rules.ValidateMinimumOrderValue(price, quantity)
			
			if tt.expectErr {
				assert.Error(t, err)
				if tt.errMsg != "" {
					assert.Contains(t, err.Error(), tt.errMsg)
				}
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestMarketRules_GetTickSize(t *testing.T) {
	rules := NewMarketRules()

	tests := []struct {
		name         string
		price        string
		expectedTick string
	}{
		// Price >= $10,000: tick size 1 (0 decimals)
		{"$10000", "10000000000000000000000", "1000000000000000000"},
		{"$15000", "15000000000000000000000", "1000000000000000000"},
		
		// Price >= $1,000: tick size 0.1 (1 decimal)
		{"$1000", "1000000000000000000000", "100000000000000000"},
		{"$5000", "5000000000000000000000", "100000000000000000"},
		
		// Price >= $100: tick size 0.01 (2 decimals)
		{"$100", "100000000000000000000", "10000000000000000"},
		{"$500", "500000000000000000000", "10000000000000000"},
		
		// Price >= $10: tick size 0.001 (3 decimals)
		{"$10", "10000000000000000000", "1000000000000000"},
		{"$50", "50000000000000000000", "1000000000000000"},
		
		// Price >= $1: tick size 0.0001 (4 decimals)
		{"$1", "1000000000000000000", "100000000000000"},
		{"$5", "5000000000000000000", "100000000000000"},
		
		// Price >= $0.1: tick size 0.00001 (5 decimals)
		{"$0.1", "100000000000000000", "10000000000000"},
		{"$0.5", "500000000000000000", "10000000000000"},
		
		// Price >= $0.01: tick size 0.000001 (6 decimals)
		{"$0.01", "10000000000000000", "1000000000000"},
		{"$0.05", "50000000000000000", "1000000000000"},
		
		// Price >= $0.001: tick size 0.0000001 (7 decimals)
		{"$0.001", "1000000000000000", "100000000000"},
		{"$0.005", "5000000000000000", "100000000000"},
		
		// Price >= $0.0001: tick size 0.00000001 (8 decimals)
		{"$0.0001", "100000000000000", "10000000000"},
		{"$0.0005", "500000000000000", "10000000000"},
		
		// Price < $0.0001: tick size 0.00000001 (8 decimals)
		{"$0.00001", "10000000000000", "10000000000"},
		{"$0.00005", "50000000000000", "10000000000"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			price, _ := uint256.FromDecimal(tt.price)
			expectedTick, _ := uint256.FromDecimal(tt.expectedTick)
			
			tickSize := rules.GetTickSize(price)
			
			assert.Equal(t, expectedTick, tickSize)
		})
	}
}

func TestMarketRules_GetLotSize(t *testing.T) {
	rules := NewMarketRules()

	tests := []struct {
		name        string
		price       string
		expectedLot string
	}{
		// Price >= $10,000: lot size 0.00001
		{"$10000", "10000000000000000000000", "10000000000000"},
		{"$15000", "15000000000000000000000", "10000000000000"},
		
		// Price >= $1,000: lot size 0.0001
		{"$1000", "1000000000000000000000", "100000000000000"},
		{"$5000", "5000000000000000000000", "100000000000000"},
		
		// Price >= $100: lot size 0.001
		{"$100", "100000000000000000000", "1000000000000000"},
		{"$500", "500000000000000000000", "1000000000000000"},
		
		// Price >= $10: lot size 0.01
		{"$10", "10000000000000000000", "10000000000000000"},
		{"$50", "50000000000000000000", "10000000000000000"},
		
		// Price >= $1: lot size 0.1
		{"$1", "1000000000000000000", "100000000000000000"},
		{"$5", "5000000000000000000", "100000000000000000"},
		
		// Price >= $0.1: lot size 1
		{"$0.1", "100000000000000000", "1000000000000000000"},
		{"$0.5", "500000000000000000", "1000000000000000000"},
		
		// Price < $0.1: lot size 1
		{"$0.01", "10000000000000000", "1000000000000000000"},
		{"$0.001", "1000000000000000", "1000000000000000000"},
		{"$0.0001", "100000000000000", "1000000000000000000"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			price, _ := uint256.FromDecimal(tt.price)
			expectedLot, _ := uint256.FromDecimal(tt.expectedLot)
			
			lotSize := rules.GetLotSize(price)
			
			assert.Equal(t, expectedLot, lotSize)
		})
	}
}

func TestMarketRules_RoundDownToLotSize(t *testing.T) {
	rules := NewMarketRules()

	tests := []struct {
		name         string
		price        string
		quantity     string
		expected     string
		wasRounded  bool
	}{
		// Price $100 (lot size 0.001)
		{"Already aligned", "100000000000000000000", "1000000000000000", "1000000000000000", false}, // 0.001
		{"Round down", "100000000000000000000", "1500000000000000", "1000000000000000", true}, // 0.0015 -> 0.001
		{"Round down", "100000000000000000000", "2700000000000000", "2000000000000000", true}, // 0.0027 -> 0.002
		
		// Price $1 (lot size 0.1)
		{"Already aligned", "1000000000000000000", "100000000000000000", "100000000000000000", false}, // 0.1
		{"Round down", "1000000000000000000", "150000000000000000", "100000000000000000", true}, // 0.15 -> 0.1
		{"Round down", "1000000000000000000", "270000000000000000", "200000000000000000", true}, // 0.27 -> 0.2
		
		// Price $0.1 (lot size 1)
		{"Already aligned", "100000000000000000", "1000000000000000000", "1000000000000000000", false}, // 1
		{"Round down", "100000000000000000", "1500000000000000000", "1000000000000000000", true}, // 1.5 -> 1
		{"Round down", "100000000000000000", "2700000000000000000", "2000000000000000000", true}, // 2.7 -> 2
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			price, _ := uint256.FromDecimal(tt.price)
			quantity, _ := uint256.FromDecimal(tt.quantity)
			expected, _ := uint256.FromDecimal(tt.expected)
			
			result, wasRounded := rules.RoundDownToLotSize(price, quantity)
			
			assert.Equal(t, expected, result)
			assert.Equal(t, tt.wasRounded, wasRounded)
		})
	}
}

func TestMarketRules_IsQuantityDust(t *testing.T) {
	rules := NewMarketRules()

	tests := []struct {
		name     string
		price    string
		quantity string
		isDust   bool
	}{
		// Price $100 (lot size 0.001)
		{"Below lot size", "100000000000000000000", "500000000000000", true}, // 0.0005 < 0.001
		{"At lot size", "100000000000000000000", "1000000000000000", false}, // 0.001 = 0.001
		{"Above lot size", "100000000000000000000", "2000000000000000", false}, // 0.002 > 0.001
		
		// Price $1 (lot size 0.1)
		{"Below lot size", "1000000000000000000", "50000000000000000", true}, // 0.05 < 0.1
		{"At lot size", "1000000000000000000", "100000000000000000", false}, // 0.1 = 0.1
		{"Above lot size", "1000000000000000000", "200000000000000000", false}, // 0.2 > 0.1
		
		// Price $0.1 (lot size 1)
		{"Below lot size", "100000000000000000", "500000000000000000", true}, // 0.5 < 1
		{"At lot size", "100000000000000000", "1000000000000000000", false}, // 1 = 1
		{"Above lot size", "100000000000000000", "2000000000000000000", false}, // 2 > 1
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			price, _ := uint256.FromDecimal(tt.price)
			quantity, _ := uint256.FromDecimal(tt.quantity)
			
			isDust := rules.IsQuantityDust(quantity, price)
			
			assert.Equal(t, tt.isDust, isDust)
		})
	}
}

func TestMarketRules_ValidateMarketOrder(t *testing.T) {
	rules := NewMarketRules()

	tests := []struct {
		name      string
		quantity  string
		bestPrice string
		side      OrderSide
		mode      OrderMode
		expectErr bool
		errMsg    string
	}{
		// Base mode with best price
		{"Valid base buy", "100000000000000000", "10000000000000000000", BUY, BASE_MODE, false, ""},
		{"Valid base sell", "100000000000000000", "10000000000000000000", SELL, BASE_MODE, false, ""},
		{"Invalid lot size", "50000000000000000", "10000000000000000000", BUY, BASE_MODE, true, "at least $1"}, // Actually fails min value check
		{"Below min value", "10000000000000000", "10000000000000000000", BUY, BASE_MODE, true, "at least $1"},
		
		// Quote mode with best price
		{"Valid quote buy", "1000000000000000000", "1000000000000000000", BUY, QUOTE_MODE, false, ""}, // $1
		{"Valid quote sell", "2000000000000000000", "1000000000000000000", SELL, QUOTE_MODE, false, ""}, // $2
		{"Below min notional", "500000000000000000", "1000000000000000000", BUY, QUOTE_MODE, true, "at least $1"},
		
		// Base mode without best price
		{"Valid base no price", "10000000000000", "", BUY, BASE_MODE, false, ""}, // 0.00001 (min lot size)
		{"Invalid base no price", "15000000000000", "", BUY, BASE_MODE, true, "minimum lot size"},
		
		// Quote mode without best price
		{"Valid quote no price", "1000000000000000000", "", BUY, QUOTE_MODE, false, ""}, // $1
		{"Invalid quote no price", "500000000000000000", "", BUY, QUOTE_MODE, true, "at least $1"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			quantity, _ := uint256.FromDecimal(tt.quantity)
			var bestPrice *uint256.Int
			if tt.bestPrice != "" {
				bestPrice, _ = uint256.FromDecimal(tt.bestPrice)
			}
			
			err := rules.ValidateMarketOrder(quantity, bestPrice, tt.side, tt.mode)
			
			if tt.expectErr {
				assert.Error(t, err)
				if tt.errMsg != "" {
					assert.Contains(t, err.Error(), tt.errMsg)
				}
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestMarketRules_ValidateOrder(t *testing.T) {
	rules := NewMarketRules()

	// Create a valid limit order
	validPrice, _ := uint256.FromDecimal("1000000000000000000") // $1
	validQty, _ := uint256.FromDecimal("1000000000000000000")   // 1 unit
	
	validOrder := &Order{
		OrderID:   "test-order-1",
		UserID:    "user-1",
		Symbol:    "ETH-USDT",
		Side:      BUY,
		OrderType: LIMIT,
		Price:     validPrice,
		Quantity:  validQty,
	}
	
	// Test valid order
	err := rules.ValidateOrder(validOrder)
	require.NoError(t, err)
	
	// Test market order (should skip validation)
	marketOrder := &Order{
		OrderID:   "test-order-2",
		UserID:    "user-1",
		Symbol:    "ETH-USDT",
		Side:      BUY,
		OrderType: MARKET,
		Price:     nil, // Market orders don't need price
		Quantity:  validQty,
	}
	
	err = rules.ValidateOrder(marketOrder)
	require.NoError(t, err)
	
	// Test invalid price
	invalidPriceOrder := &Order{
		OrderID:   "test-order-3",
		UserID:    "user-1",
		Symbol:    "ETH-USDT",
		Side:      BUY,
		OrderType: LIMIT,
		Price:     uint256.NewInt(0), // Zero price
		Quantity:  validQty,
	}
	
	err = rules.ValidateOrder(invalidPriceOrder)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "price cannot be zero")
	
	// Test invalid quantity
	invalidQtyOrder := &Order{
		OrderID:   "test-order-4",
		UserID:    "user-1",
		Symbol:    "ETH-USDT",
		Side:      BUY,
		OrderType: LIMIT,
		Price:     validPrice,
		Quantity:  uint256.NewInt(0), // Zero quantity
	}
	
	err = rules.ValidateOrder(invalidQtyOrder)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "quantity cannot be zero")
	
	// Test below minimum value
	smallQty, _ := uint256.FromDecimal("100000000000000000") // 0.1 unit
	belowMinOrder := &Order{
		OrderID:   "test-order-5",
		UserID:    "user-1",
		Symbol:    "ETH-USDT",
		Side:      BUY,
		OrderType: LIMIT,
		Price:     validPrice, // $1
		Quantity:  smallQty,   // 0.1 * $1 = $0.1 < $1 minimum
	}
	
	err = rules.ValidateOrder(belowMinOrder)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "at least $1")
}