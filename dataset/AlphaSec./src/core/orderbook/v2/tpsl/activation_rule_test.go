package tpsl

import (
	"testing"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestActivationRule_ShouldActivate(t *testing.T) {
	rule := NewActivationRule()

	testCases := []struct {
		name     string
		order    *types.Order
		expected bool
	}{
		{
			name:     "Nil order",
			order:    nil,
			expected: false,
		},
		{
			name: "Order without TPSL",
			order: &types.Order{
				OrderID: "order1",
				Status:  types.FILLED,
			},
			expected: false,
		},
		{
			name: "Order with TPSL but not filled",
			order: &types.Order{
				OrderID: "order2",
				Status:  types.NEW,
				TPSL: &types.TPSLContext{
					TPLimitPrice:   uint256.NewInt(2100),
					SLTriggerPrice: uint256.NewInt(1900),
				},
			},
			expected: false,
		},
		{
			name: "Filled order with complete TPSL",
			order: &types.Order{
				OrderID: "order3",
				Status:  types.FILLED,
				TPSL: &types.TPSLContext{
					TPLimitPrice:   uint256.NewInt(2100),
					SLTriggerPrice: uint256.NewInt(1900),
				},
			},
			expected: true,
		},
		{
			name: "Filled order with nil TP price",
			order: &types.Order{
				OrderID: "order4",
				Status:  types.FILLED,
				TPSL: &types.TPSLContext{
					TPLimitPrice:   nil,
					SLTriggerPrice: uint256.NewInt(1900),
				},
			},
			expected: false,
		},
		{
			name: "Filled order with nil SL price",
			order: &types.Order{
				OrderID: "order5",
				Status:  types.FILLED,
				TPSL: &types.TPSLContext{
					TPLimitPrice:   uint256.NewInt(2100),
					SLTriggerPrice: nil,
				},
			},
			expected: false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result := rule.ShouldActivate(tc.order)
			assert.Equal(t, tc.expected, result)
		})
	}
}

func TestActivationRule_Activate_BuyOrder(t *testing.T) {
	rule := NewActivationRule()

	buyOrder := &types.Order{
		OrderID:   "BUY_001",
		UserID:    "user1",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		OrderType: types.LIMIT,
		Price:     uint256.NewInt(2000),
		Quantity:  uint256.NewInt(10),
		OrigQty:   uint256.NewInt(10),
		Status:    types.FILLED,
		TPSL: &types.TPSLContext{
			TPLimitPrice:   uint256.NewInt(2100),
			SLTriggerPrice: uint256.NewInt(1900),
			SLLimitPrice:   uint256.NewInt(1895),
		},
	}

	activation, err := rule.Activate(buyOrder)
	require.NoError(t, err)
	require.NotNil(t, activation)

	// Check TP order
	assert.NotNil(t, activation.TPOrder)
	assert.Equal(t, types.GenerateTPOrderID("BUY_001"), activation.TPOrder.OrderID)
	assert.Equal(t, types.SELL, activation.TPOrder.Side) // Opposite side
	assert.Equal(t, types.TP_LIMIT, activation.TPOrder.OrderType)
	assert.Equal(t, uint256.NewInt(2100), activation.TPOrder.Price)
	assert.Equal(t, uint256.NewInt(10), activation.TPOrder.Quantity)
	assert.Equal(t, types.NEW, activation.TPOrder.Status)

	// Check SL trigger
	assert.NotNil(t, activation.SLTrigger)
	slTrigger, ok := activation.SLTrigger.(*StopLossTrigger)
	require.True(t, ok)
	assert.Equal(t, types.GenerateSLOrderID("BUY_001"), slTrigger.Order.OrderID)
	assert.Equal(t, types.SELL, slTrigger.Order.Side) // Opposite side
	assert.Equal(t, uint256.NewInt(1895), slTrigger.Order.Price)
	assert.Equal(t, uint256.NewInt(1900), slTrigger.StopPrice)
	assert.False(t, slTrigger.TriggerAbove) // For BUY, SL triggers below

	// Check OCO pair
	assert.NotNil(t, activation.OCOPair)
	assert.Equal(t, "TPSL_BUY_001", activation.OCOPair.ID)
	assert.Len(t, activation.OCOPair.OrderIDs, 2)
	assert.Contains(t, activation.OCOPair.OrderIDs, activation.TPOrder.OrderID)
	assert.Contains(t, activation.OCOPair.OrderIDs, slTrigger.Order.OrderID)
	assert.Equal(t, OneCancelsOther, activation.OCOPair.Strategy)
}

func TestActivationRule_Activate_SellOrder(t *testing.T) {
	rule := NewActivationRule()

	sellOrder := &types.Order{
		OrderID:   "SELL_001",
		UserID:    "user2",
		Symbol:    "BTC/USDT",
		Side:      types.SELL,
		OrderType: types.LIMIT,
		Price:     uint256.NewInt(30000),
		Quantity:  uint256.NewInt(1),
		OrigQty:   uint256.NewInt(1),
		Status:    types.FILLED,
		TPSL: &types.TPSLContext{
			TPLimitPrice:   uint256.NewInt(29000),
			SLTriggerPrice: uint256.NewInt(31000),
			SLLimitPrice:   uint256.NewInt(31100),
		},
	}

	activation, err := rule.Activate(sellOrder)
	require.NoError(t, err)
	require.NotNil(t, activation)

	// Check TP order
	assert.NotNil(t, activation.TPOrder)
	assert.Equal(t, types.BUY, activation.TPOrder.Side) // Opposite side
	assert.Equal(t, uint256.NewInt(29000), activation.TPOrder.Price)

	// Check SL trigger
	slTrigger, ok := activation.SLTrigger.(*StopLossTrigger)
	require.True(t, ok)
	assert.Equal(t, types.BUY, slTrigger.Order.Side) // Opposite side
	assert.Equal(t, uint256.NewInt(31100), slTrigger.Order.Price)
	assert.Equal(t, uint256.NewInt(31000), slTrigger.StopPrice)
	assert.True(t, slTrigger.TriggerAbove) // For SELL, SL triggers above
}

func TestActivationRule_Activate_MarketSL(t *testing.T) {
	rule := NewActivationRule()

	order := &types.Order{
		OrderID:   "MARKET_SL_001",
		UserID:    "user3",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		OrderType: types.LIMIT,
		Price:     uint256.NewInt(2000),
		Quantity:  uint256.NewInt(5),
		OrigQty:   uint256.NewInt(5),
		Status:    types.FILLED,
		TPSL: &types.TPSLContext{
			TPLimitPrice:   uint256.NewInt(2100),
			SLTriggerPrice: uint256.NewInt(1900),
			SLLimitPrice:   nil, // Market order for SL
		},
	}

	activation, err := rule.Activate(order)
	require.NoError(t, err)
	require.NotNil(t, activation)

	// Check SL order is market type
	slTrigger, ok := activation.SLTrigger.(*StopLossTrigger)
	require.True(t, ok)
	assert.Equal(t, types.SL_MARKET, slTrigger.Order.OrderType)
	assert.Nil(t, slTrigger.Order.Price)
}

func TestActivationRule_Activate_InvalidOrder(t *testing.T) {
	rule := NewActivationRule()

	testCases := []struct {
		name  string
		order *types.Order
	}{
		{
			name:  "Nil order",
			order: nil,
		},
		{
			name: "Order not filled",
			order: &types.Order{
				OrderID: "order1",
				Status:  types.NEW,
				TPSL: &types.TPSLContext{
					TPLimitPrice:   uint256.NewInt(2100),
					SLTriggerPrice: uint256.NewInt(1900),
				},
			},
		},
		{
			name: "Order without TPSL",
			order: &types.Order{
				OrderID: "order2",
				Status:  types.FILLED,
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			activation, err := rule.Activate(tc.order)
			assert.Error(t, err)
			assert.Nil(t, activation)
			assert.Contains(t, err.Error(), "not eligible for TPSL activation")
		})
	}
}

func TestActivationRule_ValidateTPSLContext_BuyOrder(t *testing.T) {
	rule := NewActivationRule()

	testCases := []struct {
		name        string
		order       *types.Order
		expectError bool
		errorMsg    string
	}{
		{
			name: "Valid BUY order TPSL",
			order: &types.Order{
				Side:  types.BUY,
				Price: uint256.NewInt(2000),
				TPSL: &types.TPSLContext{
					TPLimitPrice:   uint256.NewInt(2100), // Higher than price
					SLTriggerPrice: uint256.NewInt(1900), // Lower than price
				},
			},
			expectError: false,
		},
		{
			name: "BUY order with TP <= price",
			order: &types.Order{
				Side:  types.BUY,
				Price: uint256.NewInt(2000),
				TPSL: &types.TPSLContext{
					TPLimitPrice:   uint256.NewInt(2000), // Equal to price
					SLTriggerPrice: uint256.NewInt(1900),
				},
			},
			expectError: true,
			errorMsg:    "TP price must be higher than order price for BUY orders",
		},
		{
			name: "BUY order with SL >= price",
			order: &types.Order{
				Side:  types.BUY,
				Price: uint256.NewInt(2000),
				TPSL: &types.TPSLContext{
					TPLimitPrice:   uint256.NewInt(2100),
					SLTriggerPrice: uint256.NewInt(2000), // Equal to price
				},
			},
			expectError: true,
			errorMsg:    "SL trigger price must be lower than order price for BUY orders",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			err := rule.ValidateTPSLContext(tc.order)
			if tc.expectError {
				assert.Error(t, err)
				assert.Contains(t, err.Error(), tc.errorMsg)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestActivationRule_ValidateTPSLContext_SellOrder(t *testing.T) {
	rule := NewActivationRule()

	testCases := []struct {
		name        string
		order       *types.Order
		expectError bool
		errorMsg    string
	}{
		{
			name: "Valid SELL order TPSL",
			order: &types.Order{
				Side:  types.SELL,
				Price: uint256.NewInt(2000),
				TPSL: &types.TPSLContext{
					TPLimitPrice:   uint256.NewInt(1900), // Lower than price
					SLTriggerPrice: uint256.NewInt(2100), // Higher than price
				},
			},
			expectError: false,
		},
		{
			name: "SELL order with TP >= price",
			order: &types.Order{
				Side:  types.SELL,
				Price: uint256.NewInt(2000),
				TPSL: &types.TPSLContext{
					TPLimitPrice:   uint256.NewInt(2000), // Equal to price
					SLTriggerPrice: uint256.NewInt(2100),
				},
			},
			expectError: true,
			errorMsg:    "TP price must be lower than order price for SELL orders",
		},
		{
			name: "SELL order with SL <= price",
			order: &types.Order{
				Side:  types.SELL,
				Price: uint256.NewInt(2000),
				TPSL: &types.TPSLContext{
					TPLimitPrice:   uint256.NewInt(1900),
					SLTriggerPrice: uint256.NewInt(2000), // Equal to price
				},
			},
			expectError: true,
			errorMsg:    "SL trigger price must be higher than order price for SELL orders",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			err := rule.ValidateTPSLContext(tc.order)
			if tc.expectError {
				assert.Error(t, err)
				assert.Contains(t, err.Error(), tc.errorMsg)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestActivationRule_ValidateTPSLContext_MissingFields(t *testing.T) {
	rule := NewActivationRule()

	testCases := []struct {
		name     string
		order    *types.Order
		errorMsg string
	}{
		{
			name:     "Nil order",
			order:    nil,
			errorMsg: "order or TPSL context is nil",
		},
		{
			name: "Nil TPSL context",
			order: &types.Order{
				OrderID: "order1",
				TPSL:    nil,
			},
			errorMsg: "order or TPSL context is nil",
		},
		{
			name: "Nil TP price",
			order: &types.Order{
				OrderID: "order2",
				TPSL: &types.TPSLContext{
					TPLimitPrice:   nil,
					SLTriggerPrice: uint256.NewInt(1900),
				},
			},
			errorMsg: "TP limit price is required",
		},
		{
			name: "Nil SL trigger price",
			order: &types.Order{
				OrderID: "order3",
				TPSL: &types.TPSLContext{
					TPLimitPrice:   uint256.NewInt(2100),
					SLTriggerPrice: nil,
				},
			},
			errorMsg: "SL trigger price is required",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			err := rule.ValidateTPSLContext(tc.order)
			assert.Error(t, err)
			assert.Contains(t, err.Error(), tc.errorMsg)
		})
	}
}

func TestActivationRule_ComplexScenarios(t *testing.T) {
	rule := NewActivationRule()

	t.Run("Multiple activations with same base order", func(t *testing.T) {
		baseOrder := &types.Order{
			OrderID:  "BASE_001",
			UserID:   "user1",
			Symbol:   "ETH/USDT",
			Side:     types.BUY,
			Price:    uint256.NewInt(2000),
			Quantity: uint256.NewInt(10),
			OrigQty:  uint256.NewInt(10),
			Status:   types.FILLED,
			TPSL: &types.TPSLContext{
				TPLimitPrice:   uint256.NewInt(2100),
				SLTriggerPrice: uint256.NewInt(1900),
				SLLimitPrice:   uint256.NewInt(1895),
			},
		}

		activation1, err1 := rule.Activate(baseOrder)
		activation2, err2 := rule.Activate(baseOrder)

		assert.NoError(t, err1)
		assert.NoError(t, err2)
		assert.NotNil(t, activation1)
		assert.NotNil(t, activation2)

		// Same base order generates same TPSL IDs (deterministic)
		assert.Equal(t, activation1.TPOrder.OrderID, activation2.TPOrder.OrderID)
		assert.Equal(t, activation1.OCOPair.ID, activation2.OCOPair.ID)
	})

	t.Run("Large quantity order", func(t *testing.T) {
		largeQty := uint256.MustFromDecimal("1000000000000000000")

		order := &types.Order{
			OrderID:  "LARGE_001",
			UserID:   "whale",
			Symbol:   "BTC/USDT",
			Side:     types.SELL,
			Price:    uint256.NewInt(30000),
			Quantity: largeQty,
			OrigQty:  largeQty,
			Status:   types.FILLED,
			TPSL: &types.TPSLContext{
				TPLimitPrice:   uint256.NewInt(29000),
				SLTriggerPrice: uint256.NewInt(31000),
			},
		}

		activation, err := rule.Activate(order)
		assert.NoError(t, err)
		assert.NotNil(t, activation)
		assert.Equal(t, largeQty, activation.TPOrder.Quantity)
		assert.Equal(t, largeQty, activation.TPOrder.OrigQty)
	})

	t.Run("Edge case prices", func(t *testing.T) {
		order := &types.Order{
			OrderID:  "EDGE_001",
			UserID:   "user1",
			Symbol:   "ETH/USDT",
			Side:     types.BUY,
			Price:    uint256.NewInt(1),
			Quantity: uint256.NewInt(10),
			OrigQty:  uint256.NewInt(10),
			Status:   types.FILLED,
			TPSL: &types.TPSLContext{
				TPLimitPrice:   uint256.NewInt(2),
				SLTriggerPrice: uint256.NewInt(0),
				SLLimitPrice:   uint256.NewInt(0),
			},
		}

		activation, err := rule.Activate(order)
		assert.NoError(t, err)
		assert.NotNil(t, activation)
	})
}
