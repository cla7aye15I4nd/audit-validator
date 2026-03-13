package common

import (
	"github.com/holiman/uint256"
	"github.com/shopspring/decimal"
	"log"
	"math/big"
)

var ScalingDecimal = decimal.NewFromUint64(1_000_000_000_000_000_000)

// Uint256MulScaled performs (a * b) / 1e18 safely
func Uint256MulScaled(a, b *uint256.Int) *uint256.Int {
	// 1. a * b → big.Int (512-bit)
	aBig := a.ToBig()
	bBig := b.ToBig()

	product := new(big.Int).Mul(aBig, bBig)
	product.Div(product, ScalingDecimal.BigInt()) // (a * b) / 1e18

	// 2. 결과를 uint256.Int로 변환
	u256, overflow := uint256.FromBig(product)
	if overflow {
		log.Fatal("Overflow during scaled multiplication")
	}
	return u256
}

// Uint256DivScaled performs (a * 1e18) / b safely
func Uint256DivScaled(a, b *uint256.Int) *uint256.Int {
	// Convert to *big.Int for intermediate 512-bit precision
	aBig := a.ToBig()
	bBig := b.ToBig()

	// numerator = a * 1e18
	numerator := new(big.Int).Mul(aBig, ScalingDecimal.BigInt())

	// result = (a * 1e18) / b
	if bBig.Sign() == 0 {
		log.Fatal("Division by zero in Uint256DivScaled")
	}
	result := new(big.Int).Div(numerator, bBig)

	// convert to *uint256.Int safely
	u256, overflow := uint256.FromBig(result)
	if overflow {
		log.Fatal("Overflow during scaled division")
	}
	return u256
}

// Uint256MulScaledDecimal performs (a * b) / 1e18 using decimal to avoid overflow
func Uint256MulScaledDecimal(a, b *uint256.Int) *uint256.Int {
	// 1. uint256 → decimal
	decA, _ := decimal.NewFromString(a.Dec())
	decB, _ := decimal.NewFromString(b.Dec())

	// 2. 곱하고 나누기
	result := decA.Mul(decB).Div(ScalingDecimal).Truncate(0)

	// 3. decimal → uint256
	u, err := uint256.FromDecimal(result.String())
	if err != nil {
		log.Fatalf("failed to convert: %v", err)
	}
	return u
}

// Uint256DivScaledDecimal performs (a * 1e18) / b using decimal to avoid overflow
func Uint256DivScaledDecimal(a, b *uint256.Int) *uint256.Int {
	decA, _ := decimal.NewFromString(a.Dec())
	decB, _ := decimal.NewFromString(b.Dec())

	result := decA.Mul(ScalingDecimal).Div(decB).Truncate(0)

	u, err := uint256.FromDecimal(result.String())
	if err != nil {
		log.Fatalf("failed to convert: %v", err)
	}
	return u
}

// BigIntMulScaled performs (a * b) / 1e18
func BigIntMulScaled(a, b *big.Int) *big.Int {
	// (a * b) / 1e18
	mul := new(big.Int).Mul(a, b)
	result := new(big.Int).Div(mul, ScalingDecimal.BigInt())
	return result
}

// BigIntDivScaled performs (a * 1e18) / b
func BigIntDivScaled(a, b *big.Int) *big.Int {
	// (a * 1e18) / b
	if b.Sign() == 0 {
		log.Fatal("division by zero")
	}
	scaled := new(big.Int).Mul(a, ScalingDecimal.BigInt())
	result := new(big.Int).Div(scaled, b)
	return result
}

// BigIntMulScaledDecimal performs (a * b) / 1e18 using decimal
func BigIntMulScaledDecimal(a, b *big.Int) *big.Int {
	decA := decimal.NewFromBigInt(a, 0)
	decB := decimal.NewFromBigInt(b, 0)

	result := decA.Mul(decB).Div(ScalingDecimal).Truncate(0)

	out, ok := new(big.Int).SetString(result.String(), 10)
	if !ok {
		log.Fatalf("failed to convert decimal result to big.Int: %s", result.String())
	}
	return out
}

// BigIntDivScaledDecimal performs (a * 1e18) / b using decimal
func BigIntDivScaledDecimal(a, b *big.Int) *big.Int {
	if b.Sign() == 0 {
		log.Fatal("division by zero")
	}
	decA := decimal.NewFromBigInt(a, 0)
	decB := decimal.NewFromBigInt(b, 0)

	result := decA.Mul(ScalingDecimal).Div(decB).Truncate(0)

	out, ok := new(big.Int).SetString(result.String(), 10)
	if !ok {
		log.Fatalf("failed to convert decimal result to big.Int: %s", result.String())
	}
	return out
}
