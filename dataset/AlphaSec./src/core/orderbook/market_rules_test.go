package orderbook

import (
	"testing"

	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
)

func TestMarketRulesValidation(t *testing.T) {
	rules := NewMarketRules()

	t.Run("Price validation for different ranges", func(t *testing.T) {
		tests := []struct {
			name        string
			price       string
			shouldPass  bool
			description string
		}{
			// Price >= $10,000: 0 decimals allowed
			{"10000exact", "10000000000000000000000", true, "$10,000 exact"},
			{"15000exact", "15000000000000000000000", true, "$15,000 exact"},
			{"10000.1invalid", "10000100000000000000000", false, "$10,000.1 should fail (no decimals)"},
			
			// Price >= $1,000: 1 decimal allowed
			{"1000exact", "1000000000000000000000", true, "$1,000 exact"},
			{"1500.5valid", "1500500000000000000000", true, "$1,500.5 valid"},
			{"1500.55invalid", "1500550000000000000000", false, "$1,500.55 should fail (max 1 decimal)"},
			
			// Price >= $100: 2 decimals allowed
			{"100exact", "100000000000000000000", true, "$100 exact"},
			{"150.25valid", "150250000000000000000", true, "$150.25 valid"},
			{"150.255invalid", "150255000000000000000", false, "$150.255 should fail (max 2 decimals)"},
			
			// Price >= $10: 3 decimals allowed
			{"10exact", "10000000000000000000", true, "$10 exact"},
			{"15.125valid", "15125000000000000000", true, "$15.125 valid"},
			{"15.1255invalid", "15125500000000000000", false, "$15.1255 should fail (max 3 decimals)"},
			
			// Price >= $1: 4 decimals allowed
			{"1exact", "1000000000000000000", true, "$1 exact"},
			{"1.5432valid", "1543200000000000000", true, "$1.5432 valid"},
			{"1.54321invalid", "1543210000000000000", false, "$1.54321 should fail (max 4 decimals)"},
			
			// Price >= $0.1: 5 decimals allowed
			{"0.1exact", "100000000000000000", true, "$0.1 exact"},
			{"0.15432valid", "154320000000000000", true, "$0.15432 valid"},
			{"0.154321invalid", "154321000000000000", false, "$0.154321 should fail (max 5 decimals)"},
			
			// Price >= $0.0001: 8 decimals allowed
			{"0.0001exact", "100000000000000", true, "$0.0001 exact"},
			{"0.00012345valid", "123450000000000", true, "$0.00012345 valid"},
			{"0.000123456789invalid", "123456789000", false, "$0.000123456789 should fail (max 8 decimals)"},
			
			// Price < $0.0001: always 8 decimals, tick size 0.00000001
			{"0.00001valid", "10000000000000", true, "$0.00001 valid"},
			{"0.00000001valid", "10000000000", true, "$0.00000001 valid (min tick)"},
			{"0.000000015invalid", "15000000000", false, "$0.000000015 should fail (not divisible by min tick)"},
		}

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				price, _ := uint256.FromDecimal(tt.price)
				err := rules.ValidateOrderPrice(price)
				if tt.shouldPass {
					assert.NoError(t, err, tt.description)
				} else {
					assert.Error(t, err, tt.description)
				}
			})
		}
	})

	t.Run("Quantity lot size validation", func(t *testing.T) {
		tests := []struct {
			name        string
			price       string
			quantity    string
			shouldPass  bool
			description string
		}{
			// Price >= $10,000: min lot size 0.00001
			{"10kvalidqty", "10000000000000000000000", "10000000000000", true, "0.00001 quantity at $10k"},
			{"10kinvalidqty", "10000000000000000000000", "5000000000000", false, "0.000005 should fail"},
			
			// Price >= $1,000: min lot size 0.0001
			{"1kvalidqty", "1000000000000000000000", "100000000000000", true, "0.0001 quantity at $1k"},
			{"1kinvalidqty", "1000000000000000000000", "50000000000000", false, "0.00005 should fail"},
			
			// Price >= $1: min lot size 0.1
			{"1validqty", "1000000000000000000", "100000000000000000", true, "0.1 quantity at $1"},
			{"1invalidqty", "1000000000000000000", "50000000000000000", false, "0.05 should fail"},
			
			// Price < $1: min lot size 1
			{"0.1validqty", "100000000000000000", "1000000000000000000", true, "1 quantity at $0.1"},
			{"0.1invalidqty", "100000000000000000", "500000000000000000", false, "0.5 should fail"},
		}

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				price, _ := uint256.FromDecimal(tt.price)
				quantity, _ := uint256.FromDecimal(tt.quantity)
				err := rules.ValidateOrderQuantity(price, quantity)
				if tt.shouldPass {
					assert.NoError(t, err, tt.description)
				} else {
					assert.Error(t, err, tt.description)
				}
			})
		}
	})

	t.Run("Minimum order value validation", func(t *testing.T) {
		tests := []struct {
			name        string
			price       string
			quantity    string
			shouldPass  bool
			description string
		}{
			// Order value >= $1
			{"1dollarexact", "1000000000000000000", "1000000000000000000", true, "$1 order value"},
			{"10dollar", "10000000000000000000", "100000000000000000", true, "$10 order value"},
			{"0.5dollar", "500000000000000000", "1000000000000000000", false, "$0.5 order value should fail"},
			{"0.99dollar", "990000000000000000", "1000000000000000000", false, "$0.99 order value should fail"},
		}

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				price, _ := uint256.FromDecimal(tt.price)
				quantity, _ := uint256.FromDecimal(tt.quantity)
				err := rules.ValidateMinimumOrderValue(price, quantity)
				if tt.shouldPass {
					assert.NoError(t, err, tt.description)
				} else {
					assert.Error(t, err, tt.description)
				}
			})
		}
	})

	t.Run("GetTickSize returns correct values", func(t *testing.T) {
		tests := []struct {
			price        string
			expectedTick string
			description  string
		}{
			{"10000000000000000000000", "1000000000000000000", "$10k -> tick 1.0"},
			{"1000000000000000000000", "100000000000000000", "$1k -> tick 0.1"},
			{"100000000000000000000", "10000000000000000", "$100 -> tick 0.01"},
			{"10000000000000000000", "1000000000000000", "$10 -> tick 0.001"},
			{"1000000000000000000", "100000000000000", "$1 -> tick 0.0001"},
			{"100000000000000000", "10000000000000", "$0.1 -> tick 0.00001"},
			{"10000000000000", "10000000000", "$0.00001 -> tick 0.00000001"},
		}

		for _, tt := range tests {
			price, _ := uint256.FromDecimal(tt.price)
			expectedTick, _ := uint256.FromDecimal(tt.expectedTick)
			tick := rules.GetTickSize(price)
			assert.Equal(t, expectedTick.String(), tick.String(), tt.description)
		}
	})

	t.Run("GetLotSize returns correct values", func(t *testing.T) {
		tests := []struct {
			price       string
			expectedLot string
			description string
		}{
			{"10000000000000000000000", "10000000000000", "$10k -> lot 0.00001"},
			{"1000000000000000000000", "100000000000000", "$1k -> lot 0.0001"},
			{"100000000000000000000", "1000000000000000", "$100 -> lot 0.001"},
			{"10000000000000000000", "10000000000000000", "$10 -> lot 0.01"},
			{"1000000000000000000", "100000000000000000", "$1 -> lot 0.1"},
			{"100000000000000000", "1000000000000000000", "$0.1 -> lot 1"},
			{"10000000000000", "1000000000000000000", "$0.00001 -> lot 1"},
		}

		for _, tt := range tests {
			price, _ := uint256.FromDecimal(tt.price)
			expectedLot, _ := uint256.FromDecimal(tt.expectedLot)
			lot := rules.GetLotSize(price)
			assert.Equal(t, expectedLot.String(), lot.String(), tt.description)
		}
	})
}

func TestMarketRulesRounding(t *testing.T) {
	rules := NewMarketRules()

	t.Run("Round price to tick size", func(t *testing.T) {
		tests := []struct {
			name         string
			price        string
			roundUp      bool
			expectedPrice string
			description  string
		}{
			// $1000 range (1 decimal)
			{"1500.55down", "1500550000000000000000", false, "1500500000000000000000", "$1500.55 -> $1500.5"},
			{"1500.55up", "1500550000000000000000", true, "1500600000000000000000", "$1500.55 -> $1500.6"},
			
			// $100 range (2 decimals)
			{"150.255down", "150255000000000000000", false, "150250000000000000000", "$150.255 -> $150.25"},
			{"150.255up", "150255000000000000000", true, "150260000000000000000", "$150.255 -> $150.26"},
			
			// Already valid
			{"150.25exact", "150250000000000000000", false, "150250000000000000000", "$150.25 unchanged"},
		}

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				price, _ := uint256.FromDecimal(tt.price)
				expected, _ := uint256.FromDecimal(tt.expectedPrice)
				rounded := rules.RoundPriceToTickSize(price, tt.roundUp)
				assert.Equal(t, expected.String(), rounded.String(), tt.description)
			})
		}
	})

	t.Run("Round quantity to lot size", func(t *testing.T) {
		tests := []struct {
			name         string
			price        string
			quantity     string
			roundUp      bool
			expectedQty  string
			description  string
		}{
			// $10k (lot 0.00001)
			{"10krounddown", "10000000000000000000000", "15500000000000", false, "10000000000000", "0.0000155 -> 0.00001"},
			{"10kroundup", "10000000000000000000000", "15500000000000", true, "20000000000000", "0.0000155 -> 0.00002"},
			
			// $1 (lot 0.1)
			{"1rounddown", "1000000000000000000", "155000000000000000", false, "100000000000000000", "0.155 -> 0.1"},
			{"1roundup", "1000000000000000000", "155000000000000000", true, "200000000000000000", "0.155 -> 0.2"},
		}

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				price, _ := uint256.FromDecimal(tt.price)
				quantity, _ := uint256.FromDecimal(tt.quantity)
				expected, _ := uint256.FromDecimal(tt.expectedQty)
				rounded := rules.RoundQuantityToLotSize(price, quantity, tt.roundUp)
				assert.Equal(t, expected.String(), rounded.String(), tt.description)
			})
		}
	})
}