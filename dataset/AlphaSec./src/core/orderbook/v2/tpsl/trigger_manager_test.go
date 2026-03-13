package tpsl

import (
	"fmt"
	"sync"
	"testing"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTriggerManager_AddTrigger(t *testing.T) {
	manager := NewTriggerManager()

	trigger := NewStopOrderTrigger(
		&types.Order{
			OrderID: "trigger1",
			UserID:  "user1",
		},
		uint256.NewInt(2000),
		true,
	)

	err := manager.AddTrigger(trigger)
	assert.NoError(t, err)
	assert.Equal(t, 1, manager.GetQueueSize())

	err = manager.AddTrigger(trigger)
	assert.Error(t, err)
	assert.Equal(t, types.ErrOrderAlreadyExists, err)

	err = manager.AddTrigger(nil)
	assert.Error(t, err)
	assert.Equal(t, types.ErrInvalidOrder, err)
}

func TestTriggerManager_RemoveTrigger(t *testing.T) {
	manager := NewTriggerManager()

	trigger := NewStopOrderTrigger(
		&types.Order{
			OrderID: "trigger1",
			UserID:  "user1",
		},
		uint256.NewInt(2000),
		true,
	)

	manager.AddTrigger(trigger)
	assert.Equal(t, 1, manager.GetQueueSize())

	removed := manager.RemoveTrigger("trigger1")
	assert.True(t, removed)
	assert.Equal(t, 0, manager.GetQueueSize())
	assert.Equal(t, types.CANCELLED, trigger.Status)

	removed = manager.RemoveTrigger("trigger1")
	assert.False(t, removed)
}

func TestTriggerManager_GetTrigger(t *testing.T) {
	manager := NewTriggerManager()

	originalTrigger := NewStopOrderTrigger(
		&types.Order{
			OrderID: "trigger1",
			UserID:  "user1",
		},
		uint256.NewInt(2000),
		true,
	)

	manager.AddTrigger(originalTrigger)

	trigger, exists := manager.GetTrigger("trigger1")
	assert.True(t, exists)
	assert.Equal(t, originalTrigger, trigger)

	trigger, exists = manager.GetTrigger("nonexistent")
	assert.False(t, exists)
	assert.Nil(t, trigger)
}

func TestTriggerManager_CheckTriggers_Sequential(t *testing.T) {
	manager := NewTriggerManager()

	trigger1 := NewStopOrderTrigger(
		&types.Order{
			OrderID:  "stop1",
			UserID:   "user1",
			Quantity: uint256.NewInt(10),
		},
		uint256.NewInt(1950),
		false,
	)

	trigger2 := NewStopOrderTrigger(
		&types.Order{
			OrderID:  "stop2",
			UserID:   "user2",
			Quantity: uint256.NewInt(20),
		},
		uint256.NewInt(2050),
		true,
	)

	trigger3 := NewStopLossTrigger(
		&types.Order{
			OrderID:  "sl1",
			UserID:   "user3",
			Quantity: uint256.NewInt(30),
		},
		uint256.NewInt(1900),
		false,
	)

	manager.AddTrigger(trigger1)
	manager.AddTrigger(trigger2)
	manager.AddTrigger(trigger3)

	assert.Equal(t, 3, manager.GetQueueSize())

	triggered := manager.CheckTriggers(uint256.NewInt(1950))
	assert.Len(t, triggered, 1)
	assert.Equal(t, "stop1", string(triggered[0].Order.OrderID))
	assert.Equal(t, TriggerTypeStopOrder, triggered[0].TriggerType)
	assert.Equal(t, 2, manager.GetQueueSize())

	triggered = manager.CheckTriggers(uint256.NewInt(1900))
	assert.Len(t, triggered, 1)
	assert.Equal(t, "sl1", string(triggered[0].Order.OrderID))
	assert.Equal(t, TriggerTypeStopLoss, triggered[0].TriggerType)
	assert.Equal(t, 1, manager.GetQueueSize())

	triggered = manager.CheckTriggers(uint256.NewInt(2050))
	assert.Len(t, triggered, 1)
	assert.Equal(t, "stop2", string(triggered[0].Order.OrderID))
	assert.Equal(t, 0, manager.GetQueueSize())
}

func TestTriggerManager_CheckTriggers_Multiple(t *testing.T) {
	manager := NewTriggerManager()

	for i := 0; i < 5; i++ {
		trigger := NewStopOrderTrigger(
			&types.Order{
				OrderID: types.OrderID(fmt.Sprintf("stop%d", i)),
				UserID:  "user1",
			},
			uint256.NewInt(2000),
			false,
		)
		manager.AddTrigger(trigger)
	}

	triggered := manager.CheckTriggers(uint256.NewInt(1999))
	assert.Len(t, triggered, 5)
	assert.Equal(t, 0, manager.GetQueueSize())

	for i, tr := range triggered {
		assert.Equal(t, fmt.Sprintf("stop%d", i), string(tr.Order.OrderID))
	}
}

func TestTriggerManager_CheckTriggers_NilPrice(t *testing.T) {
	manager := NewTriggerManager()

	trigger := NewStopOrderTrigger(
		&types.Order{
			OrderID: "stop1",
			UserID:  "user1",
		},
		uint256.NewInt(2000),
		true,
	)

	manager.AddTrigger(trigger)

	triggered := manager.CheckTriggers(nil)
	assert.Len(t, triggered, 0)
	assert.Equal(t, 1, manager.GetQueueSize())
}

func TestTriggerManager_CheckTriggers_RemovedTrigger(t *testing.T) {
	manager := NewTriggerManager()

	for i := 0; i < 3; i++ {
		trigger := NewStopOrderTrigger(
			&types.Order{
				OrderID: types.OrderID(fmt.Sprintf("stop%d", i)),
				UserID:  "user1",
			},
			uint256.NewInt(2000),
			false,
		)
		manager.AddTrigger(trigger)
	}

	manager.RemoveTrigger("stop1")

	triggered := manager.CheckTriggers(uint256.NewInt(1999))
	assert.Len(t, triggered, 2)

	foundRemoved := false
	for _, tr := range triggered {
		if tr.Order.OrderID == "stop1" {
			foundRemoved = true
		}
	}
	assert.False(t, foundRemoved)
}

func TestTriggerManager_CheckTriggers_OrderPreservation(t *testing.T) {
	manager := NewTriggerManager()

	trigger1 := NewStopOrderTrigger(
		&types.Order{OrderID: "A", UserID: "user1"},
		uint256.NewInt(2100),
		true,
	)

	trigger2 := NewStopOrderTrigger(
		&types.Order{OrderID: "B", UserID: "user1"},
		uint256.NewInt(2000),
		false,
	)

	trigger3 := NewStopOrderTrigger(
		&types.Order{OrderID: "C", UserID: "user1"},
		uint256.NewInt(2050),
		true,
	)

	manager.AddTrigger(trigger1)
	manager.AddTrigger(trigger2)
	manager.AddTrigger(trigger3)

	triggered := manager.CheckTriggers(uint256.NewInt(2000))
	assert.Len(t, triggered, 1)
	assert.Equal(t, "B", string(triggered[0].Order.OrderID))

	remaining := manager.queue
	assert.Len(t, remaining, 2)
	assert.Equal(t, types.OrderID("A"), remaining[0])
	assert.Equal(t, types.OrderID("C"), remaining[1])
}

func TestTriggerManager_UserOperations(t *testing.T) {
	manager := NewTriggerManager()

	// Create triggers for different users
	user1Trigger1 := NewStopOrderTrigger(
		&types.Order{
			OrderID:  "user1_stop1",
			UserID:   "user1",
			Symbol:   "ETH/USDT",
			Side:     types.BUY,
			Price:    uint256.NewInt(2000),
			Quantity: uint256.NewInt(1),
			OrigQty:  uint256.NewInt(1),
		},
		uint256.NewInt(1950), // Stop price
		false,                // Trigger when price <= 1950
	)

	user1Trigger2 := NewStopOrderTrigger(
		&types.Order{
			OrderID:  "user1_stop2",
			UserID:   "user1",
			Symbol:   "ETH/USDT",
			Side:     types.SELL,
			Price:    uint256.NewInt(2100),
			Quantity: uint256.NewInt(1),
			OrigQty:  uint256.NewInt(1),
		},
		uint256.NewInt(2050),
		true, // Trigger when price >= 2050
	)

	user2Trigger := NewStopOrderTrigger(
		&types.Order{
			OrderID:  "user2_stop1",
			UserID:   "user2",
			Symbol:   "ETH/USDT",
			Side:     types.BUY,
			Price:    uint256.NewInt(2000),
			Quantity: uint256.NewInt(1),
			OrigQty:  uint256.NewInt(1),
		},
		uint256.NewInt(1950),
		false,
	)

	// Add all triggers
	require.NoError(t, manager.AddTrigger(user1Trigger1))
	require.NoError(t, manager.AddTrigger(user1Trigger2))
	require.NoError(t, manager.AddTrigger(user2Trigger))

	// Test GetUserTriggers
	user1Triggers := manager.GetUserTriggers("user1")
	assert.Len(t, user1Triggers, 2)
	assert.Contains(t, user1Triggers, types.OrderID("user1_stop1"))
	assert.Contains(t, user1Triggers, types.OrderID("user1_stop2"))

	user2Triggers := manager.GetUserTriggers("user2")
	assert.Len(t, user2Triggers, 1)
	assert.Contains(t, user2Triggers, types.OrderID("user2_stop1"))

	// Test RemoveUserTriggers
	removedTriggers := manager.RemoveUserTriggers("user1")
	assert.Len(t, removedTriggers, 2)
	assert.Contains(t, removedTriggers, types.OrderID("user1_stop1"))
	assert.Contains(t, removedTriggers, types.OrderID("user1_stop2"))

	// Verify user1 triggers are removed
	user1TriggersAfter := manager.GetUserTriggers("user1")
	assert.Len(t, user1TriggersAfter, 0)

	// Verify user2 triggers are still there
	user2TriggersAfter := manager.GetUserTriggers("user2")
	assert.Len(t, user2TriggersAfter, 1)

	// Verify removed triggers don't trigger
	triggered := manager.CheckTriggers(uint256.NewInt(1900))
	assert.Len(t, triggered, 1) // Only user2's trigger
	assert.Equal(t, "user2_stop1", string(triggered[0].Order.OrderID))
}

func TestTriggerManager_OCOIntegration(t *testing.T) {
	manager := NewTriggerManager()

	// Create a stop-loss trigger (part of TPSL)
	slTrigger := NewStopLossTrigger(
		&types.Order{
			OrderID:  "SL_order1",
			UserID:   "user1",
			Symbol:   "ETH/USDT",
			Side:     types.SELL,
			Price:    uint256.NewInt(1900),
			Quantity: uint256.NewInt(1),
			OrigQty:  uint256.NewInt(1),
		},
		uint256.NewInt(1950), // Stop price
		false,                // Trigger when price <= 1950
	)

	// Add the trigger
	require.NoError(t, manager.AddTrigger(slTrigger))

	// Check triggers - price drops to trigger SL
	triggered := manager.CheckTriggers(uint256.NewInt(1950))
	require.Len(t, triggered, 1)

	// Verify trigger type is StopLoss
	assert.Equal(t, TriggerTypeStopLoss, triggered[0].TriggerType)

	// Verify the order details
	assert.Equal(t, "SL_order1", string(triggered[0].Order.OrderID))
	assert.Equal(t, types.SELL, triggered[0].Order.Side)
}

func TestTriggerManager_Clear(t *testing.T) {
	manager := NewTriggerManager()

	// Add some triggers
	trigger1 := NewStopOrderTrigger(
		&types.Order{
			OrderID: "stop1",
			UserID:  "user1",
		},
		uint256.NewInt(2000),
		true,
	)
	trigger2 := NewStopOrderTrigger(
		&types.Order{
			OrderID: "stop2",
			UserID:  "user2",
		},
		uint256.NewInt(2000),
		true,
	)

	manager.AddTrigger(trigger1)
	manager.AddTrigger(trigger2)

	assert.Equal(t, 2, manager.GetQueueSize())

	// Clear all triggers
	manager.Clear()

	assert.Equal(t, 0, manager.GetQueueSize())

	// Verify no triggers remain
	triggered := manager.CheckTriggers(uint256.NewInt(2100))
	assert.Len(t, triggered, 0)
}

func TestTriggerManager_ConcurrentOperations(t *testing.T) {
	manager := NewTriggerManager()
	wg := sync.WaitGroup{}
	numGoroutines := 100

	wg.Add(numGoroutines * 4)

	for i := 0; i < numGoroutines; i++ {
		go func(id int) {
			defer wg.Done()
			trigger := NewStopOrderTrigger(
				&types.Order{
					OrderID: types.OrderID(fmt.Sprintf("add_%d", id)),
					UserID:  types.UserID(fmt.Sprintf("user_%d", id)),
				},
				uint256.NewInt(uint64(2000+id)),
				true,
			)
			manager.AddTrigger(trigger)
		}(i)

		go func(id int) {
			defer wg.Done()
			manager.GetTrigger(types.OrderID(fmt.Sprintf("add_%d", id)))
		}(i)

		go func(id int) {
			defer wg.Done()
			manager.CheckTriggers(uint256.NewInt(uint64(2000 + id)))
		}(i)

		go func(id int) {
			defer wg.Done()
			if id%2 == 0 {
				manager.RemoveTrigger(types.OrderID(fmt.Sprintf("add_%d", id)))
			}
		}(i)
	}

	wg.Wait()
}

func TestTriggerManager_DetermineTriggerType(t *testing.T) {
	manager := NewTriggerManager()

	slTrigger := NewStopLossTrigger(
		&types.Order{OrderID: "sl1"},
		uint256.NewInt(1900),
		false,
	)

	stopTrigger := NewStopOrderTrigger(
		&types.Order{OrderID: "stop1"},
		uint256.NewInt(2000),
		true,
	)

	triggerType := manager.determineTriggerType(slTrigger)
	assert.Equal(t, TriggerTypeStopLoss, triggerType)

	triggerType = manager.determineTriggerType(stopTrigger)
	assert.Equal(t, TriggerTypeStopOrder, triggerType)

	type CustomTrigger struct {
		Trigger
	}
	customTrigger := &CustomTrigger{}
	triggerType = manager.determineTriggerType(customTrigger)
	assert.Equal(t, TriggerTypeStopOrder, triggerType)
}

func TestTriggerManager_EdgeCases(t *testing.T) {
	t.Run("Empty manager operations", func(t *testing.T) {
		manager := NewTriggerManager()

		triggered := manager.CheckTriggers(uint256.NewInt(2000))
		assert.Len(t, triggered, 0)

		removed := manager.RemoveTrigger("nonexistent")
		assert.False(t, removed)

		trigger, exists := manager.GetTrigger("nonexistent")
		assert.False(t, exists)
		assert.Nil(t, trigger)

		assert.Equal(t, 0, manager.GetQueueSize())
	})

	t.Run("Trigger with nil order", func(t *testing.T) {
		manager := NewTriggerManager()

		trigger := &StopOrderTrigger{
			Order:     nil,
			StopPrice: uint256.NewInt(2000),
			Status:    types.TRIGGER_WAIT,
		}

		err := manager.AddTrigger(trigger)
		assert.NoError(t, err)

		triggered := manager.CheckTriggers(uint256.NewInt(1999))
		assert.Len(t, triggered, 0)
	})

	t.Run("Large number of triggers", func(t *testing.T) {
		manager := NewTriggerManager()
		numTriggers := 1000

		for i := 0; i < numTriggers; i++ {
			trigger := NewStopOrderTrigger(
				&types.Order{
					OrderID: types.OrderID(fmt.Sprintf("large_%d", i)),
					UserID:  "user1",
				},
				uint256.NewInt(uint64(1000+i)),
				false,
			)
			err := manager.AddTrigger(trigger)
			require.NoError(t, err)
		}

		assert.Equal(t, numTriggers, manager.GetQueueSize())

		// At price 2000, triggers with stopPrice < 2000 and triggerAbove=false won't trigger
		// They trigger when price <= stopPrice, so we need price below all stop prices
		triggered := manager.CheckTriggers(uint256.NewInt(999))
		assert.Len(t, triggered, numTriggers)
		assert.Equal(t, 0, manager.GetQueueSize())
	})
}

func TestTriggerManager_MemoryLeak(t *testing.T) {
	manager := NewTriggerManager()

	for round := 0; round < 100; round++ {
		for i := 0; i < 10; i++ {
			trigger := NewStopOrderTrigger(
				&types.Order{
					OrderID: types.OrderID(fmt.Sprintf("mem_%d_%d", round, i)),
					UserID:  "user1",
				},
				uint256.NewInt(2000),
				false,
			)
			manager.AddTrigger(trigger)
		}

		manager.CheckTriggers(uint256.NewInt(1999))
		assert.Equal(t, 0, manager.GetQueueSize())
		assert.Equal(t, 0, len(manager.triggers))
	}
}
