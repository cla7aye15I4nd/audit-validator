package types

import (
	"fmt"

	"github.com/holiman/uint256"
)

// ScalingExp is the decimal scaling exponent (10^18)
const ScalingExp = 18

// MarketRules defines tick and lot size rules based on price ranges
type MarketRules struct {
	MinOrderValueUSD *uint256.Int // Minimum order value in USD ($1)
	MinNotionalUSD   *uint256.Int // Minimum notional for market orders ($1)
	PriceRanges      []PriceRange // Price-based rules
}

// PriceRange defines tick size and lot size rules for a specific price range
type PriceRange struct {
	MinPrice    *uint256.Int // Minimum price for this range (in scaled units)
	MaxDecimals uint8        // Maximum decimal places allowed for price
	MinLotSize  *uint256.Int // Minimum lot size (quantity increment)
}

// NewMarketRules creates market rules with default configuration
func NewMarketRules() *MarketRules {
	// $1 minimum for limit orders, $1 for market orders (with 18 decimals scaling)
	minOrderValue, _ := uint256.FromDecimal("1000000000000000000") // 1 * 10^18
	minNotional, _ := uint256.FromDecimal("1000000000000000000")   // 1 * 10^18

	return &MarketRules{
		MinOrderValueUSD: minOrderValue,
		MinNotionalUSD:   minNotional,
		PriceRanges:      DefaultPriceRanges(),
	}
}

// DefaultPriceRanges returns the default price range configurations
// All values are already scaled by 10^18
func DefaultPriceRanges() []PriceRange {
	// Helper to create scaled uint256
	scale := func(v string) *uint256.Int {
		result, _ := uint256.FromDecimal(v)
		return result
	}

	return []PriceRange{
		// Price >= $10,000: 0 decimals, min size 0.00001
		{
			MinPrice:    scale("10000000000000000000000"), // 10000 * 10^18
			MaxDecimals: 0,
			MinLotSize:  scale("10000000000000"), // 0.00001 * 10^18
		},
		// Price >= $1,000: 1 decimal, min size 0.0001
		{
			MinPrice:    scale("1000000000000000000000"), // 1000 * 10^18
			MaxDecimals: 1,
			MinLotSize:  scale("100000000000000"), // 0.0001 * 10^18
		},
		// Price >= $100: 2 decimals, min size 0.001
		{
			MinPrice:    scale("100000000000000000000"), // 100 * 10^18
			MaxDecimals: 2,
			MinLotSize:  scale("1000000000000000"), // 0.001 * 10^18
		},
		// Price >= $10: 3 decimals, min size 0.01
		{
			MinPrice:    scale("10000000000000000000"), // 10 * 10^18
			MaxDecimals: 3,
			MinLotSize:  scale("10000000000000000"), // 0.01 * 10^18
		},
		// Price >= $1: 4 decimals, min size 0.1
		{
			MinPrice:    scale("1000000000000000000"), // 1 * 10^18
			MaxDecimals: 4,
			MinLotSize:  scale("100000000000000000"), // 0.1 * 10^18
		},
		// Price >= $0.1: 5 decimals, min size 1
		{
			MinPrice:    scale("100000000000000000"), // 0.1 * 10^18
			MaxDecimals: 5,
			MinLotSize:  scale("1000000000000000000"), // 1 * 10^18
		},
		// Price >= $0.01: 6 decimals, min size 1
		{
			MinPrice:    scale("10000000000000000"), // 0.01 * 10^18
			MaxDecimals: 6,
			MinLotSize:  scale("1000000000000000000"), // 1 * 10^18
		},
		// Price >= $0.001: 7 decimals, min size 1
		{
			MinPrice:    scale("1000000000000000"), // 0.001 * 10^18
			MaxDecimals: 7,
			MinLotSize:  scale("1000000000000000000"), // 1 * 10^18
		},
		// Price >= $0.0001: 8 decimals, min size 1
		{
			MinPrice:    scale("100000000000000"), // 0.0001 * 10^18
			MaxDecimals: 8,
			MinLotSize:  scale("1000000000000000000"), // 1 * 10^18
		},
		// For any price < $0.0001: 8 decimals, min size 1
		// This serves as the default/minimum range
		{
			MinPrice:    uint256.NewInt(0),
			MaxDecimals: 8,
			MinLotSize:  scale("1000000000000000000"), // 1 * 10^18
		},
	}
}

// GetPriceRange returns the appropriate price range for a given price
func (m *MarketRules) GetPriceRange(price *uint256.Int) *PriceRange {
	// Iterate from highest to lowest price range
	for _, pr := range m.PriceRanges {
		if price.Cmp(pr.MinPrice) >= 0 {
			return &pr
		}
	}
	// Return the last range as default (should not happen with proper config)
	lastIdx := len(m.PriceRanges) - 1
	return &m.PriceRanges[lastIdx]
}

// GetTickSize returns the tick size for a given price
func (m *MarketRules) GetTickSize(price *Price) *Quantity {
	pr := m.GetPriceRange(price)

	// For price < $0.0001, tick size is always 0.00000001 (8 decimals)
	threshold, _ := uint256.FromDecimal("100000000000000") // 0.0001 * 10^18
	if price.Cmp(threshold) < 0 {
		minTickSize, _ := uint256.FromDecimal("10000000000") // 0.00000001 * 10^18
		return minTickSize
	}

	// Otherwise, tick size based on max decimals
	return CalculateTickSize(pr.MaxDecimals)
}

// GetLotSize returns the minimum lot size for a given price
func (m *MarketRules) GetLotSize(price *Price) *Quantity {
	pr := m.GetPriceRange(price)
	return new(uint256.Int).Set(pr.MinLotSize)
}

// GetMinimumLotSize returns the smallest lot size across all price ranges
func (m *MarketRules) GetMinimumLotSize() *Quantity {
	minLot, _ := uint256.FromDecimal("10000000000000") // 0.00001 * 10^18
	return minLot
}

// ValidateOrder performs complete order validation
func (m *MarketRules) ValidateOrder(order *Order) error {
	// Skip validation for market orders (price can be nil)
	if order.OrderType.IsMarket() {
		return nil
	}

	// Validate price
	if err := m.ValidateOrderPrice(order.Price); err != nil {
		return err
	}

	// Validate quantity
	if err := m.ValidateOrderQuantity(order.Price, order.Quantity); err != nil {
		return err
	}

	// Validate minimum order value
	if err := m.ValidateMinimumOrderValue(order.Price, order.Quantity); err != nil {
		return err
	}

	return nil
}

// ValidateOrderPrice validates if the price conforms to tick size rules
func (m *MarketRules) ValidateOrderPrice(price *Price) error {
	if price == nil || price.IsZero() {
		return fmt.Errorf("price cannot be zero")
	}

	tickSize := m.GetTickSize(price)

	// Check if price is divisible by tick size
	remainder := new(uint256.Int)
	remainder.Mod(price, tickSize)

	if !remainder.IsZero() {
		pr := m.GetPriceRange(price)
		return fmt.Errorf("price must be divisible by tick size (max %d decimals for price %s)",
			pr.MaxDecimals, toDecimal(price))
	}

	return nil
}

// ValidateOrderQuantity validates if the quantity conforms to lot size rules
func (m *MarketRules) ValidateOrderQuantity(price, quantity *Quantity) error {
	if quantity == nil || quantity.IsZero() {
		return fmt.Errorf("quantity cannot be zero")
	}

	lotSize := m.GetLotSize(price)

	// Check if quantity is divisible by lot size
	remainder := new(uint256.Int)
	remainder.Mod(quantity, lotSize)

	if !remainder.IsZero() {
		return fmt.Errorf("quantity must be divisible by lot size %s",
			toDecimal(lotSize))
	}

	return nil
}

// ValidateMinimumOrderValue validates if the order meets minimum value requirement
func (m *MarketRules) ValidateMinimumOrderValue(price, quantity *Quantity) error {
	// Calculate order value: price * quantity / 10^18 (to account for scaling)
	orderValue := new(uint256.Int).Mul(price, quantity)
	scale, _ := uint256.FromDecimal("1000000000000000000") // 10^18
	orderValue.Div(orderValue, scale)

	if orderValue.Cmp(m.MinOrderValueUSD) < 0 {
		return fmt.Errorf("order value must be at least $1 (current: %s)",
			toDecimal(orderValue))
	}

	return nil
}

// ValidateMarketOrder validates market order based on best price
func (m *MarketRules) ValidateMarketOrder(quantity *Quantity, bestPrice *Price, side OrderSide, orderMode OrderMode) error {
	// If no best price available, use minimum lot size
	if bestPrice == nil || bestPrice.IsZero() {
		// Use smallest lot size (0.00001) when no price reference
		minLotSize, _ := uint256.FromDecimal("10000000000000") // 0.00001 * 10^18

		// Convert quote mode to base if needed (but without price, just check minimum)
		if orderMode == QUOTE_MODE {
			// For quote mode without price, just check minimum notional
			if quantity.Cmp(m.MinNotionalUSD) < 0 {
				return fmt.Errorf("market order value must be at least $1")
			}
			return nil
		}

		// Base mode: validate with minimum lot size
		remainder := new(uint256.Int)
		remainder.Mod(quantity, minLotSize)
		if !remainder.IsZero() {
			return fmt.Errorf("quantity must be divisible by minimum lot size %s", toDecimal(minLotSize))
		}
		return nil
	}

	// For quote mode market orders, skip lot size validation
	// The actual traded quantity will be determined and rounded during matching
	if orderMode == QUOTE_MODE {
		// Just validate minimum notional value
		if quantity.Cmp(m.MinNotionalUSD) < 0 {
			return fmt.Errorf("market order value must be at least $1")
		}
		return nil
	}

	// For base mode, validate with price-based lot size
	lotSize := m.GetLotSize(bestPrice)

	// Validate lot size
	remainder := new(uint256.Int)
	remainder.Mod(quantity, lotSize)
	if !remainder.IsZero() {
		return fmt.Errorf("quantity must be divisible by lot size %s for price level %s",
			toDecimal(lotSize), toDecimal(bestPrice))
	}

	// Validate minimum notional value for base mode
	// Calculate notional: base_qty * price / 10^18
	notional := new(uint256.Int).Mul(quantity, bestPrice)
	scale, _ := uint256.FromDecimal("1000000000000000000")
	notional.Div(notional, scale)

	if notional.Cmp(m.MinNotionalUSD) < 0 {
		return fmt.Errorf("market order value must be at least $1 (current: %s)",
			toDecimal(notional))
	}

	return nil
}

// RoundPriceToTickSize rounds a price to the nearest valid tick size
func (m *MarketRules) RoundPriceToTickSize(price *Price, roundUp bool) *Price {
	tickSize := m.GetTickSize(price)

	remainder := new(uint256.Int)
	remainder.Mod(price, tickSize)

	// If already valid, return as is
	if remainder.IsZero() {
		return new(uint256.Int).Set(price)
	}

	// Round down by subtracting remainder
	rounded := new(uint256.Int).Sub(price, remainder)

	// If rounding up, add one tick
	if roundUp && !remainder.IsZero() {
		rounded.Add(rounded, tickSize)
	}

	return rounded
}

// RoundQuantityToLotSize rounds a quantity to the nearest valid lot size
func (m *MarketRules) RoundQuantityToLotSize(price, quantity *Quantity, roundUp bool) *Quantity {
	lotSize := m.GetLotSize(price)

	remainder := new(uint256.Int)
	remainder.Mod(quantity, lotSize)

	// If already valid, return as is
	if remainder.IsZero() {
		return new(uint256.Int).Set(quantity)
	}

	// Round down by subtracting remainder
	rounded := new(uint256.Int).Sub(quantity, remainder)

	// If rounding up, add one lot
	if roundUp && !remainder.IsZero() {
		rounded.Add(rounded, lotSize)
	}

	return rounded
}

// RoundDownToLotSize rounds a quantity down to the nearest lot size
// Returns the rounded quantity and whether any rounding occurred
func (m *MarketRules) RoundDownToLotSize(price, quantity *Quantity) (*Quantity, bool) {
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

// IsQuantityDust checks if quantity is less than minimum lot size (dust)
func (m *MarketRules) IsQuantityDust(quantity, price *Quantity) bool {
	if quantity == nil || price == nil {
		return false
	}
	
	lotSize := m.GetLotSize(price)
	return quantity.Cmp(lotSize) < 0
}

// CalculateTickSize calculates tick size based on decimal places
func CalculateTickSize(decimals uint8) *uint256.Int {
	// tick size = 10^(18-decimals)
	// For 0 decimals: 10^18 (1.0)
	// For 8 decimals: 10^10 (0.00000001)
	if decimals > ScalingExp {
		decimals = ScalingExp
	}

	exp := ScalingExp - uint(decimals)
	result := uint256.NewInt(10)
	result.Exp(result, uint256.NewInt(uint64(exp)))
	return result
}

// toDecimal converts a scaled uint256 to a decimal string for display
func toDecimal(value *uint256.Int) string {
	if value == nil {
		return "0"
	}
	// Simple conversion for display purposes
	// In production, use proper decimal formatting
	return value.String()
}