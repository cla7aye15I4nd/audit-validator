package balance

import (
	"fmt"
	"github.com/holiman/uint256"
)

const SCALE_FACTOR = 18

var (
	// Pre-computed constants for performance
	SCALE     = uint256.NewInt(1e18)
	SCALE_SQ  = new(uint256.Int).Mul(SCALE, SCALE) // 10^36
	MAX_UINT256 = new(uint256.Int).SetAllOne()     // 2^256 - 1
	
	// Fee scale: 1 = 0.0001% (0.000001), 1,000,000 = 100% (1.0)
	FEE_SCALE = uint256.NewInt(1000000)
)

// Note: ScaledMul and ScaledDiv have been moved to common.Uint256MulScaledDecimal 
// and common.Uint256DivScaledDecimal for better overflow handling and consistency

// SafeMul performs a * b with overflow check (no scaling)
func SafeMul(a, b *uint256.Int) (*uint256.Int, error) {
	if a == nil || b == nil {
		return uint256.NewInt(0), nil
	}
	
	if a.IsZero() || b.IsZero() {
		return uint256.NewInt(0), nil
	}
	
	// Check overflow
	maxDiv := new(uint256.Int).Div(MAX_UINT256, b)
	if a.Cmp(maxDiv) > 0 {
		return nil, fmt.Errorf("multiplication overflow")
	}
	
	return new(uint256.Int).Mul(a, b), nil
}

// SafeAdd performs a + b with overflow check
func SafeAdd(a, b *uint256.Int) (*uint256.Int, error) {
	if a == nil {
		a = uint256.NewInt(0)
	}
	if b == nil {
		b = uint256.NewInt(0)
	}
	
	result, overflow := new(uint256.Int).AddOverflow(a, b)
	if overflow {
		return nil, fmt.Errorf("addition overflow")
	}
	
	return result, nil
}

// SafeSub performs a - b with underflow check
func SafeSub(a, b *uint256.Int) (*uint256.Int, error) {
	if a == nil {
		a = uint256.NewInt(0)
	}
	if b == nil {
		b = uint256.NewInt(0)
	}
	
	if a.Cmp(b) < 0 {
		return nil, fmt.Errorf("subtraction underflow: %s < %s", a.String(), b.String())
	}
	
	return new(uint256.Int).Sub(a, b), nil
}

// Min returns the minimum of two uint256 values
func Min(a, b *uint256.Int) *uint256.Int {
	if a.Cmp(b) < 0 {
		return new(uint256.Int).Set(a)
	}
	return new(uint256.Int).Set(b)
}

// Max returns the maximum of two uint256 values
func Max(a, b *uint256.Int) *uint256.Int {
	if a.Cmp(b) > 0 {
		return new(uint256.Int).Set(a)
	}
	return new(uint256.Int).Set(b)
}

// IsZeroOrNil checks if value is nil or zero
func IsZeroOrNil(v *uint256.Int) bool {
	return v == nil || v.IsZero()
}

// ApplyFee calculates fee amount using the new fee scale
// feeRate is in basis points where 1 = 0.0001%, 1,000,000 = 100%
// Returns: (amount * feeRate) / 1,000,000
func ApplyFee(amount, feeRate *uint256.Int) (*uint256.Int, error) {
	if amount == nil || feeRate == nil {
		return uint256.NewInt(0), nil
	}
	
	// Check for zero operands
	if amount.IsZero() || feeRate.IsZero() {
		return uint256.NewInt(0), nil
	}
	
	// Check potential overflow: if amount * feeRate > MAX_UINT256
	maxDiv := new(uint256.Int).Div(MAX_UINT256, feeRate)
	if amount.Cmp(maxDiv) > 0 {
		return nil, fmt.Errorf("fee calculation overflow: %s * %s", amount.String(), feeRate.String())
	}
	
	// Safe to multiply
	result := new(uint256.Int).Mul(amount, feeRate)
	result.Div(result, FEE_SCALE)
	return result, nil
}