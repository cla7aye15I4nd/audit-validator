package balance

import (
	"fmt"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
)

// TestApplyFee tests the new fee scaling function
func TestApplyFee(t *testing.T) {
	tests := []struct {
		name        string
		amount      *uint256.Int
		feeRate     *uint256.Int
		expectedFee *uint256.Int
		description string
	}{
		{
			name:        "0.1% fee",
			amount:      uint256.NewInt(1000000), // 1,000,000 units
			feeRate:     uint256.NewInt(1000),    // 0.1% (1000 / 1,000,000)
			expectedFee: uint256.NewInt(1000),    // 1,000,000 * 0.001 = 1,000
			description: "0.1% of 1,000,000 = 1,000",
		},
		{
			name:        "0.2% fee",
			amount:      uint256.NewInt(1000000),
			feeRate:     uint256.NewInt(2000), // 0.2% (2000 / 1,000,000)
			expectedFee: uint256.NewInt(2000), // 1,000,000 * 0.002 = 2,000
			description: "0.2% of 1,000,000 = 2,000",
		},
		{
			name:        "0.3% fee",
			amount:      uint256.NewInt(1000000),
			feeRate:     uint256.NewInt(3000), // 0.3% (3000 / 1,000,000)
			expectedFee: uint256.NewInt(3000), // 1,000,000 * 0.003 = 3,000
			description: "0.3% of 1,000,000 = 3,000",
		},
		{
			name:        "0.05% fee",
			amount:      uint256.NewInt(1000000),
			feeRate:     uint256.NewInt(500), // 0.05% (500 / 1,000,000)
			expectedFee: uint256.NewInt(500), // 1,000,000 * 0.0005 = 500
			description: "0.05% of 1,000,000 = 500",
		},
		{
			name:        "0.0001% fee (minimum)",
			amount:      uint256.NewInt(1000000),
			feeRate:     uint256.NewInt(1),     // 0.0001% (1 / 1,000,000)
			expectedFee: uint256.NewInt(1),     // 1,000,000 * 0.000001 = 1
			description: "0.0001% of 1,000,000 = 1",
		},
		{
			name:        "1% fee",
			amount:      uint256.NewInt(1000000),
			feeRate:     uint256.NewInt(10000), // 1% (10,000 / 1,000,000)
			expectedFee: uint256.NewInt(10000), // 1,000,000 * 0.01 = 10,000
			description: "1% of 1,000,000 = 10,000",
		},
		{
			name:        "Zero fee rate",
			amount:      uint256.NewInt(1000000),
			feeRate:     uint256.NewInt(0),
			expectedFee: uint256.NewInt(0),
			description: "No fee",
		},
		{
			name:        "Zero amount",
			amount:      uint256.NewInt(0),
			feeRate:     uint256.NewInt(1000),
			expectedFee: uint256.NewInt(0),
			description: "No amount to charge fee on",
		},
		{
			name:        "Large amount with 0.1% fee",
			amount:      new(uint256.Int).Mul(uint256.NewInt(1e18), uint256.NewInt(1000)), // 1000 ETH in wei
			feeRate:     uint256.NewInt(1000), // 0.1%
			expectedFee: new(uint256.Int).Mul(uint256.NewInt(1e18), uint256.NewInt(1)), // 1 ETH fee
			description: "0.1% of 1000 ETH = 1 ETH",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fee, err := ApplyFee(tt.amount, tt.feeRate)
			assert.NoError(t, err)
			assert.Equal(t, tt.expectedFee.String(), fee.String(), tt.description)
		})
	}
}

// TestApplyFeeVsCommonScaled compares the new ApplyFee with common.Uint256MulScaledDecimal approach
func TestApplyFeeVsCommonScaled(t *testing.T) {
	// Test that 0.1% fee gives same result with both methods
	amount := new(uint256.Int).Mul(uint256.NewInt(10), uint256.NewInt(1e18)) // 10 ETH

	// New method: 0.1% = 1000 / 1,000,000
	newFeeRate := uint256.NewInt(1000)
	newFee, err := ApplyFee(amount, newFeeRate)
	assert.NoError(t, err)

	// Common package method: 0.1% = 1e15 / 1e18
	oldFeeRate := uint256.NewInt(1e15)
	oldFee := common.Uint256MulScaledDecimal(amount, oldFeeRate)

	// Both should give 0.01 ETH (10 * 0.001)
	expectedFee := new(uint256.Int).Mul(uint256.NewInt(1), uint256.NewInt(1e16))
	assert.Equal(t, expectedFee.String(), newFee.String(), "New method should give 0.01 ETH")
	assert.Equal(t, expectedFee.String(), oldFee.String(), "Common method should give 0.01 ETH")
}

// TestFeeScaleConstants verifies the fee scale constants
func TestFeeScaleConstants(t *testing.T) {
	// Verify FEE_SCALE is 1,000,000
	assert.Equal(t, uint256.NewInt(1000000).String(), FEE_SCALE.String())
	
	// Test percentage conversions
	testCases := []struct {
		percentage float64
		feeRate    uint64
	}{
		{100.0, 1000000},   // 100% = 1,000,000
		{10.0, 100000},     // 10% = 100,000
		{1.0, 10000},       // 1% = 10,000
		{0.1, 1000},        // 0.1% = 1,000
		{0.01, 100},        // 0.01% = 100
		{0.001, 10},        // 0.001% = 10
		{0.0001, 1},        // 0.0001% = 1 (minimum)
	}
	
	for _, tc := range testCases {
		t.Run(fmt.Sprintf("%.4f%%", tc.percentage), func(t *testing.T) {
			// Verify that feeRate / FEE_SCALE = percentage / 100
			expectedRatio := tc.percentage / 100
			actualRatio := float64(tc.feeRate) / 1000000
			assert.InDelta(t, expectedRatio, actualRatio, 0.0000001, 
				"Fee rate %d should represent %.4f%%", tc.feeRate, tc.percentage)
		})
	}
}