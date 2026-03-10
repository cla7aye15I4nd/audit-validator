package types

import (
	"github.com/holiman/uint256"
	"github.com/shopspring/decimal"
)

// MustParsePrice parses a price string (either decimal or uint256)
func MustParsePrice(s string) *Price {
	// Try parsing as decimal first (for Level2 formatted prices)
	if d, err := decimal.NewFromString(s); err == nil {
		scaled := d.Shift(ScalingExp)
		return (*Price)(uint256.MustFromDecimal(scaled.String()))
	}
	
	// Fall back to uint256 parsing (for internal price strings)
	return (*Price)(uint256.MustFromDecimal(s))
}

// MustParseQuantity parses a quantity string (either decimal or uint256)
func MustParseQuantity(s string) *Quantity {
	// Try parsing as decimal first
	if d, err := decimal.NewFromString(s); err == nil {
		scaled := d.Shift(ScalingExp)
		return (*Quantity)(uint256.MustFromDecimal(scaled.String()))
	}
	
	// Fall back to uint256 parsing
	return (*Quantity)(uint256.MustFromDecimal(s))
}

// MustFromUint256String parses a uint256 string directly
func MustFromUint256String(s string) *uint256.Int {
	return uint256.MustFromDecimal(s)
}

// PriceToDecimalString converts a Price to decimal string representation
func PriceToDecimalString(p *Price, exp int32) string {
	if p == nil {
		return "0"
	}
	d := decimal.NewFromBigInt((*uint256.Int)(p).ToBig(), -exp)
	return d.String()
}

// QuantityToDecimalString converts a Quantity to decimal string representation
func QuantityToDecimalString(q *Quantity, exp int32) string {
	if q == nil {
		return "0"
	}
	d := decimal.NewFromBigInt((*uint256.Int)(q).ToBig(), -exp)
	return d.String()
}