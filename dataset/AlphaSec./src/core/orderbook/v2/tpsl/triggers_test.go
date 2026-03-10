package tpsl

import (
	"testing"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestStopLossTrigger_Basic(t *testing.T) {
	order := &types.Order{
		OrderID:  "SL_001",
		UserID:   "user1",
		Symbol:   "ETH/USDT",
		Side:     types.SELL,
		Price:    uint256.NewInt(1900),
		Quantity: uint256.NewInt(10),
		OrigQty:  uint256.NewInt(10),
		Status:   types.TRIGGER_WAIT,
	}

	stopPrice := uint256.NewInt(1950)
	trigger := NewStopLossTrigger(order, stopPrice, false)

	assert.Equal(t, types.OrderID("SL_001"), trigger.GetOrderID())
	assert.Equal(t, types.UserID("user1"), trigger.GetUserID())
	assert.Equal(t, stopPrice, trigger.StopPrice)
	assert.False(t, trigger.TriggerAbove)
	assert.Equal(t, types.TRIGGER_WAIT, trigger.Status)
}

func TestStopLossTrigger_ShouldTriggerBelowPrice(t *testing.T) {
	order := &types.Order{
		OrderID: "SL_001",
		UserID:  "user1",
		Status:  types.TRIGGER_WAIT,
	}

	stopPrice := uint256.NewInt(1950)
	trigger := NewStopLossTrigger(order, stopPrice, false)

	testCases := []struct {
		name          string
		currentPrice  *uint256.Int
		shouldTrigger bool
	}{
		{"Price above stop", uint256.NewInt(2000), false},
		{"Price at stop", uint256.NewInt(1950), true},
		{"Price below stop", uint256.NewInt(1900), true},
		{"Nil price", nil, false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.shouldTrigger, trigger.ShouldTrigger(tc.currentPrice))
		})
	}
}

func TestStopLossTrigger_ShouldTriggerAbovePrice(t *testing.T) {
	order := &types.Order{
		OrderID: "SL_002",
		UserID:  "user1",
		Status:  types.TRIGGER_WAIT,
	}

	stopPrice := uint256.NewInt(2050)
	trigger := NewStopLossTrigger(order, stopPrice, true)

	testCases := []struct {
		name          string
		currentPrice  *uint256.Int
		shouldTrigger bool
	}{
		{"Price below stop", uint256.NewInt(2000), false},
		{"Price at stop", uint256.NewInt(2050), true},
		{"Price above stop", uint256.NewInt(2100), true},
		{"Nil price", nil, false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.shouldTrigger, trigger.ShouldTrigger(tc.currentPrice))
		})
	}
}

func TestStopLossTrigger_Execute(t *testing.T) {
	order := &types.Order{
		OrderID:  "SL_003",
		UserID:   "user1",
		Symbol:   "ETH/USDT",
		Side:     types.SELL,
		Price:    uint256.NewInt(1900),
		Quantity: uint256.NewInt(10),
		OrigQty:  uint256.NewInt(10),
		Status:   types.TRIGGER_WAIT,
	}

	trigger := NewStopLossTrigger(order, uint256.NewInt(1950), false)

	executedOrder := trigger.Execute()
	require.NotNil(t, executedOrder)
	assert.Equal(t, order.OrderID, executedOrder.OrderID)
	assert.Equal(t, types.TRIGGERED, executedOrder.Status)
	assert.Equal(t, types.TRIGGERED, trigger.Status)

	executedAgain := trigger.Execute()
	assert.Nil(t, executedAgain)
}

func TestStopLossTrigger_Cancel(t *testing.T) {
	order := &types.Order{
		OrderID: "SL_004",
		UserID:  "user1",
		Status:  types.TRIGGER_WAIT,
	}

	trigger := NewStopLossTrigger(order, uint256.NewInt(1950), false)

	trigger.Cancel()
	assert.Equal(t, types.CANCELLED, trigger.Status)
	assert.Equal(t, types.CANCELLED, order.Status)

	assert.False(t, trigger.ShouldTrigger(uint256.NewInt(1900)))

	executedOrder := trigger.Execute()
	assert.Nil(t, executedOrder)
}

func TestStopLossTrigger_NilOrder(t *testing.T) {
	trigger := NewStopLossTrigger(nil, uint256.NewInt(1950), false)

	assert.Equal(t, types.OrderID(""), trigger.GetOrderID())
	assert.Equal(t, types.UserID(""), trigger.GetUserID())
	// With nil order and valid stop price, ShouldTrigger will check condition
	// But Execute will return nil since order is nil
	assert.True(t, trigger.ShouldTrigger(uint256.NewInt(1900))) // Price <= 1950
	assert.Nil(t, trigger.Execute())

	trigger.Cancel()
}

func TestStopOrderTrigger_Basic(t *testing.T) {
	order := &types.Order{
		OrderID:  "STOP_001",
		UserID:   "user2",
		Symbol:   "BTC/USDT",
		Side:     types.BUY,
		Price:    uint256.NewInt(30000),
		Quantity: uint256.NewInt(1),
		OrigQty:  uint256.NewInt(1),
		Status:   types.TRIGGER_WAIT,
	}

	stopPrice := uint256.NewInt(29500)
	trigger := NewStopOrderTrigger(order, stopPrice, false)

	assert.Equal(t, types.OrderID("STOP_001"), trigger.GetOrderID())
	assert.Equal(t, types.UserID("user2"), trigger.GetUserID())
	assert.Equal(t, stopPrice, trigger.StopPrice)
	assert.False(t, trigger.TriggerAbove)
	assert.Equal(t, types.TRIGGER_WAIT, trigger.Status)
}

func TestStopOrderTrigger_ShouldTrigger(t *testing.T) {
	order := &types.Order{
		OrderID: "STOP_002",
		UserID:  "user2",
		Status:  types.TRIGGER_WAIT,
	}

	testCases := []struct {
		name         string
		stopPrice    *uint256.Int
		triggerAbove bool
		currentPrice *uint256.Int
		expected     bool
	}{
		{
			name:         "Trigger below - price drops",
			stopPrice:    uint256.NewInt(29500),
			triggerAbove: false,
			currentPrice: uint256.NewInt(29000),
			expected:     true,
		},
		{
			name:         "Trigger below - price at stop",
			stopPrice:    uint256.NewInt(29500),
			triggerAbove: false,
			currentPrice: uint256.NewInt(29500),
			expected:     true,
		},
		{
			name:         "Trigger below - price above",
			stopPrice:    uint256.NewInt(29500),
			triggerAbove: false,
			currentPrice: uint256.NewInt(30000),
			expected:     false,
		},
		{
			name:         "Trigger above - price rises",
			stopPrice:    uint256.NewInt(30500),
			triggerAbove: true,
			currentPrice: uint256.NewInt(31000),
			expected:     true,
		},
		{
			name:         "Trigger above - price at stop",
			stopPrice:    uint256.NewInt(30500),
			triggerAbove: true,
			currentPrice: uint256.NewInt(30500),
			expected:     true,
		},
		{
			name:         "Trigger above - price below",
			stopPrice:    uint256.NewInt(30500),
			triggerAbove: true,
			currentPrice: uint256.NewInt(30000),
			expected:     false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			trigger := NewStopOrderTrigger(order, tc.stopPrice, tc.triggerAbove)
			assert.Equal(t, tc.expected, trigger.ShouldTrigger(tc.currentPrice))
		})
	}
}

func TestStopOrderTrigger_Execute(t *testing.T) {
	order := &types.Order{
		OrderID:  "STOP_003",
		UserID:   "user2",
		Symbol:   "BTC/USDT",
		Side:     types.BUY,
		Price:    uint256.NewInt(30000),
		Quantity: uint256.NewInt(1),
		OrigQty:  uint256.NewInt(1),
		Status:   types.TRIGGER_WAIT,
	}

	trigger := NewStopOrderTrigger(order, uint256.NewInt(29500), false)

	executedOrder := trigger.Execute()
	require.NotNil(t, executedOrder)
	assert.Equal(t, order.OrderID, executedOrder.OrderID)
	assert.Equal(t, types.TRIGGERED, executedOrder.Status)
	assert.Equal(t, types.TRIGGERED, trigger.Status)

	executedAgain := trigger.Execute()
	assert.Nil(t, executedAgain)
}

func TestStopOrderTrigger_Cancel(t *testing.T) {
	order := &types.Order{
		OrderID: "STOP_004",
		UserID:  "user2",
		Status:  types.TRIGGER_WAIT,
	}

	trigger := NewStopOrderTrigger(order, uint256.NewInt(29500), false)

	trigger.Cancel()
	assert.Equal(t, types.CANCELLED, trigger.Status)
	assert.Equal(t, types.CANCELLED, order.Status)

	assert.False(t, trigger.ShouldTrigger(uint256.NewInt(29000)))

	executedOrder := trigger.Execute()
	assert.Nil(t, executedOrder)
}

func TestStopOrderTrigger_StatusChecks(t *testing.T) {
	t.Run("Should not trigger when already triggered", func(t *testing.T) {
		order := &types.Order{
			OrderID: "STOP_005",
			Status:  types.TRIGGER_WAIT,
		}
		trigger := NewStopOrderTrigger(order, uint256.NewInt(29500), false)

		trigger.Status = types.TRIGGERED
		assert.False(t, trigger.ShouldTrigger(uint256.NewInt(29000)))
	})

	t.Run("Should not trigger when cancelled", func(t *testing.T) {
		order := &types.Order{
			OrderID: "STOP_006",
			Status:  types.TRIGGER_WAIT,
		}
		trigger := NewStopOrderTrigger(order, uint256.NewInt(29500), false)

		trigger.Status = types.CANCELLED
		assert.False(t, trigger.ShouldTrigger(uint256.NewInt(29000)))
	})

	t.Run("Should not execute when not in TRIGGER_WAIT status", func(t *testing.T) {
		order := &types.Order{
			OrderID: "STOP_007",
			Status:  types.TRIGGER_WAIT,
		}
		trigger := NewStopOrderTrigger(order, uint256.NewInt(29500), false)

		trigger.Status = types.CANCELLED
		assert.Nil(t, trigger.Execute())
	})
}

func TestTriggers_EdgeCases(t *testing.T) {
	t.Run("StopLoss with nil stop price", func(t *testing.T) {
		order := &types.Order{
			OrderID: "SL_EDGE_001",
			Status:  types.TRIGGER_WAIT,
		}
		trigger := NewStopLossTrigger(order, nil, false)
		assert.False(t, trigger.ShouldTrigger(uint256.NewInt(1000)))
	})

	t.Run("StopOrder with nil stop price", func(t *testing.T) {
		order := &types.Order{
			OrderID: "STOP_EDGE_001",
			Status:  types.TRIGGER_WAIT,
		}
		trigger := NewStopOrderTrigger(order, nil, false)
		assert.False(t, trigger.ShouldTrigger(uint256.NewInt(1000)))
	})

	t.Run("Large price values", func(t *testing.T) {
		order := &types.Order{
			OrderID: "LARGE_001",
			Status:  types.TRIGGER_WAIT,
		}

		largeStop := uint256.MustFromDecimal("999999999999999999999999999")
		largeCurrent := uint256.MustFromDecimal("1000000000000000000000000000")

		trigger := NewStopLossTrigger(order, largeStop, true)
		assert.True(t, trigger.ShouldTrigger(largeCurrent))
	})

	t.Run("Zero price values", func(t *testing.T) {
		order := &types.Order{
			OrderID: "ZERO_001",
			Status:  types.TRIGGER_WAIT,
		}

		trigger := NewStopLossTrigger(order, uint256.NewInt(0), false)
		assert.True(t, trigger.ShouldTrigger(uint256.NewInt(0)))
		assert.False(t, trigger.ShouldTrigger(uint256.NewInt(1)))
	})
}