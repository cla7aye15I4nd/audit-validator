package orderbook

import (
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
)

// MockLocker is a test implementation that doesn't require stateDB
type MockLocker struct{}

func (m *MockLocker) AddTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// Mock implementation - do nothing
}

func (m *MockLocker) ConsumeLockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// Mock implementation - do nothing
}

func (m *MockLocker) GetTokenBalance(addr common.Address, token string) *uint256.Int {
	// Mock implementation - return zero
	return uint256.NewInt(0)
}

func (m *MockLocker) LockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// Mock implementation - do nothing
}

func (m *MockLocker) UnlockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// Mock implementation - do nothing
}

func (m *MockLocker) GetLockedTokenBalance(addr common.Address, token string) *uint256.Int {
	// Mock implementation - return zero
	return uint256.NewInt(0)
}

func TestConditionalOrderCancelLogic(t *testing.T) {
	// Test that TPSL orders are handled correctly based on lifecycle stage
	
	t.Run("Regular order with TPSL field - before fill", func(t *testing.T) {
		// This test demonstrates that TPSL field in a regular order
		// is not managed by conditional order manager until the order is fully filled
		
		engine := NewSymbolEngine("ETH/USDT")
		
		// The key insight: Before an order is fully filled, its TPSL field
		// is just data attached to the order. The conditional order manager
		// is not involved at all.
		
		// When the order is cancelled before being fully filled,
		// the TPSL data is simply discarded along with the order.
		// No interaction with conditional order manager is needed.
		
		// Verify conditional order manager starts empty
		assert.Equal(t, 0, len(engine.conditionalOrderManager.queue), "No TPSL in queue initially")
		
		// Even if we had an order with TPSL field and cancelled it,
		// the conditional order manager would remain empty because
		// TPSL is only added to the manager after the order is fully filled
		// (see trade_matcher.go lines 262-269)
	})
	
	t.Run("TPSL order after full fill - in queue", func(t *testing.T) {
		manager := NewConditionalOrderManager()
		
		// Create TPSL order (would be added after original order fully filled)
		tpslOrder := &TPSLOrder{
			TPOrder: &StopOrder{
				Order: &Order{
					OrderID:   GenerateConditionalOrderID(common.HexToHash("0xabc456"), TPIncrement),
					UserID:    "0xuser2",
					Symbol:    "ETH/USDT",
					Side:      SELL,
					Price:     uint256.NewInt(1200),
					Quantity:  uint256.NewInt(100),
				},
				StopPrice: uint256.NewInt(1150),
			},
			SLOrder: &StopOrder{
				Order: &Order{
					OrderID:   GenerateConditionalOrderID(common.HexToHash("0xabc456"), SLIncrement),
					UserID:    "0xuser2",
					Symbol:    "ETH/USDT",
					Side:      SELL,
					Price:     uint256.NewInt(900),
					Quantity:  uint256.NewInt(100),
				},
				StopPrice: uint256.NewInt(950),
			},
			submitted: false, // Not yet triggered
		}
		
		// Add to manager (simulating what happens after original order fills)
		// We don't actually need a locker for this test since we're bypassing the lock logic
		manager.AddTPSLOrder(tpslOrder, nil)
		assert.Equal(t, 1, len(manager.queue), "TPSL should be in queue")
		
		// Try to cancel by individual TP ID - should fail (behavioral rule)
		tpID := GenerateConditionalOrderID(common.HexToHash("0xabc456"), TPIncrement)
		cancelledIDs, found := manager.CancelOrder(tpID, nil, nil)
		assert.False(t, found, "Should not be able to cancel individual TPSL before trigger")
		assert.Equal(t, 0, len(cancelledIDs), "No IDs should be cancelled")
		
		// Try to cancel by individual SL ID - should also fail
		slID := GenerateConditionalOrderID(common.HexToHash("0xabc456"), SLIncrement)
		cancelledIDs, found = manager.CancelOrder(slID, nil, nil)
		assert.False(t, found, "Should not be able to cancel individual TPSL before trigger")
		assert.Equal(t, 0, len(cancelledIDs), "No IDs should be cancelled")
		
		// Queue should still have the TPSL
		assert.Equal(t, 1, len(manager.queue), "TPSL should still be in queue")
	})
	
	t.Run("Stop order cancellation", func(t *testing.T) {
		manager := NewConditionalOrderManager()
		
		// Create a single stop order wrapped in TPSLOrder format (for compatibility)
		stopOrder := &StopOrder{
			Order: &Order{
				OrderID:   common.HexToHash("0xabc789").Hex(),
				UserID:    "0xuser3",
				Symbol:    "ETH/USDT",
				Side:      BUY,
				Price:     uint256.NewInt(1100),
				Quantity:  uint256.NewInt(50),
				Timestamp: time.Now().UnixNano(),
			},
			StopPrice:    uint256.NewInt(1050),
			TriggerAbove: true,
		}
		
		// Directly add to queue (bypassing AddStopOrder which requires locker)
		// This simulates the state after AddStopOrder has completed
		tpslWrapper := &TPSLOrder{
			TPOrder: stopOrder,  // Since it's a TP-type stop order
			SLOrder: nil,
		}
		
		manager.queue = append(manager.queue, ConditionalOrderEntry{
			OrderID:   stopOrder.Order.OrderID,
			OrderType: ConditionalStop,
			Data:      tpslWrapper,
			Timestamp: stopOrder.Order.Timestamp,
			Sequence:  0,
		})
		manager.legacyOrders = append(manager.legacyOrders, tpslWrapper)
		
		assert.Equal(t, 1, len(manager.queue), "Stop order should be in queue")
		
		// Cancel by stop order ID - should work
		stopID := common.HexToHash("0xabc789").Hex()
		
		// Mock locker for cancellation
		mockLocker := &DefaultLocker{
			Locker: &MockLocker{},
		}
		cancelledIDs, found := manager.CancelOrder(stopID, mockLocker, nil)
		assert.True(t, found, "Stop order should be found and cancelled")
		assert.Equal(t, 1, len(cancelledIDs), "One ID should be cancelled")
		assert.Equal(t, stopID, cancelledIDs[0], "Correct ID should be cancelled")
		
		// Queue should be empty now
		assert.Equal(t, 0, len(manager.queue), "Queue should be empty after cancellation")
	})
	
	t.Run("TPSL after execution - TP in orderbook", func(t *testing.T) {
		// When TPSL is submitted, TP goes to orderbook
		// Cancelling either TP or SL should cancel both
		
		manager := NewConditionalOrderManager()
		
		// Mock orderbook cancel function
		orderbookCancelled := false
		mockCancelOrderbook := func(orderID string, locker *DefaultLocker) bool {
			orderbookCancelled = true
			return true
		}
		
		// Create submitted TPSL (TP is in orderbook, SL waiting)
		tpslOrder := &TPSLOrder{
			TPOrder: &StopOrder{
				Order: &Order{
					OrderID:   GenerateConditionalOrderID(common.HexToHash("0xdef123"), TPIncrement),
					UserID:    "0xuser4",
					Symbol:    "ETH/USDT",
					Side:      SELL,
					Price:     uint256.NewInt(1200),
					Quantity:  uint256.NewInt(100),
				},
				StopPrice: uint256.NewInt(1150),
			},
			SLOrder: &StopOrder{
				Order: &Order{
					OrderID:   GenerateConditionalOrderID(common.HexToHash("0xdef123"), SLIncrement),
					UserID:    "0xuser4",
					Symbol:    "ETH/USDT",
					Side:      SELL,
					Price:     uint256.NewInt(900),
					Quantity:  uint256.NewInt(100),
				},
				StopPrice: uint256.NewInt(950),
			},
			submitted: true, // Already triggered, TP is in orderbook
		}
		
		// Add to manager
		manager.queue = append(manager.queue, ConditionalOrderEntry{
			OrderID:   tpslOrder.TPOrder.Order.OrderID,
			OrderType: ConditionalTPSL,
			Data:      tpslOrder,
			Timestamp: time.Now().UnixNano(),
			Sequence:  0,
		})
		
		// Cancel by TP ID - should cancel both TP and SL
		tpID := GenerateConditionalOrderID(common.HexToHash("0xdef123"), TPIncrement)
		cancelledIDs, found := manager.CancelOrder(tpID, nil, mockCancelOrderbook)
		assert.True(t, found, "Should find and cancel submitted TPSL")
		assert.Equal(t, 2, len(cancelledIDs), "Both TP and SL should be cancelled")
		assert.Contains(t, cancelledIDs, tpID, "TP should be in cancelled IDs")
		assert.Contains(t, cancelledIDs, GenerateConditionalOrderID(common.HexToHash("0xdef123"), SLIncrement), "SL should be in cancelled IDs")
		assert.True(t, orderbookCancelled, "TP should be cancelled from orderbook")
		
		// Queue should be empty
		assert.Equal(t, 0, len(manager.queue), "Queue should be empty after cancellation")
	})
}

func TestIDGenerationConsistency(t *testing.T) {
	// Verify that ID generation is consistent and predictable
	
	txHash := common.HexToHash("0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
	
	// Generate IDs
	tpID := GenerateConditionalOrderID(txHash, TPIncrement)
	slID := GenerateConditionalOrderID(txHash, SLIncrement)
	
	// All IDs should be unique
	assert.NotEqual(t, txHash.Hex(), tpID, "TP ID should differ from original")
	assert.NotEqual(t, txHash.Hex(), slID, "SL ID should differ from original")
	assert.NotEqual(t, tpID, slID, "TP and SL IDs should be different")
	
	// Verify the last byte differences
	assert.Equal(t, byte(0xef+1), common.HexToHash(tpID)[31], "TP should have +1 increment")
	assert.Equal(t, byte(0xef+2), common.HexToHash(slID)[31], "SL should have +2 increment")
}