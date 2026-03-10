package orderbook

import (
	"os"
	"path"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestEventRecovery(t *testing.T) {
	// Create temp directory for test
	tmpDir, err := os.MkdirTemp("", "event_recovery_test")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Test basic event recovery
	t.Run("BasicRecovery", func(t *testing.T) {
		// Create some events
		events := []OrderbookEvent{
			&OrderAddedEvent{
				BaseEvent: BaseEvent{BlockNumber: 1, TxIndex: 0},
				Order: &Order{
					OrderID:  "order1",
					UserID:   "0x1234567890123456789012345678901234567890",
					Symbol:   "ETH-USDT",
					Side:     BUY,
					Price:    uint256.NewInt(3000),
					Quantity: uint256.NewInt(100),
					OrigQty:  uint256.NewInt(100),
				},
			},
			&OrderAddedEvent{
				BaseEvent: BaseEvent{BlockNumber: 1, TxIndex: 1},
				Order: &Order{
					OrderID:  "order2",
					UserID:   "0x2345678901234567890123456789012345678901",
					Symbol:   "ETH-USDT",
					Side:     SELL,
					Price:    uint256.NewInt(3100),
					Quantity: uint256.NewInt(50),
					OrigQty:  uint256.NewInt(50),
				},
			},
			&PriceUpdatedEvent{
				BaseEvent: BaseEvent{BlockNumber: 2, TxIndex: 0},
				Symbol:    "ETH-USDT",
				Price:     uint256.NewInt(3050),
			},
		}

		// Create event logger and write events
		eventsDir := path.Join(tmpDir, "events")
		logger, err := NewEventWALLogger(eventsDir)
		require.NoError(t, err)

		// Log events for block 1
		logger.SetBlockContext(1)
		logger.LogEvents(events[:2])
		err = logger.OnBlockEnd(1)
		require.NoError(t, err)

		// Log events for block 2
		logger.SetBlockContext(2)
		logger.LogEvents(events[2:])
		err = logger.OnBlockEnd(2)
		require.NoError(t, err)

		logger.Close()

		// Now recover into a new dispatcher
		d2 := NewDispatcher()
		recovery := NewEventRecovery(eventsDir)
		err = recovery.RecoverFromEvents(d2, 0)
		require.NoError(t, err)

		// Verify recovered state
		engines := d2.GetEngines()
		require.Len(t, engines, 1)

		engine, exists := engines["ETH-USDT"]
		require.True(t, exists)

		// Check orders
		assert.Equal(t, 1, len(engine.buyQueue))
		assert.Equal(t, 1, len(engine.sellQueue))

		// Check current price
		assert.Equal(t, uint256.NewInt(3050), engine.currentPrice)

		// Check order routing
		order1, exists := d2.GetOrder("order1")
		assert.True(t, exists)
		assert.Equal(t, "order1", order1.OrderID)

		order2, exists := d2.GetOrder("order2")
		assert.True(t, exists)
		assert.Equal(t, "order2", order2.OrderID)
	})

	// Test partial recovery from specific block
	t.Run("PartialRecovery", func(t *testing.T) {
		eventsDir := path.Join(tmpDir, "events2")
		logger, err := NewEventWALLogger(eventsDir)
		require.NoError(t, err)

		// Create events for multiple blocks
		for blockNum := uint64(1); blockNum <= 5; blockNum++ {
			logger.SetBlockContext(blockNum)
			logger.LogEvents([]OrderbookEvent{
				&OrderAddedEvent{
					BaseEvent: BaseEvent{BlockNumber: blockNum, TxIndex: 0},
					Order: &Order{
						OrderID:  "order_block_" + uint256.NewInt(blockNum).String(),
						UserID:   common.Address{}.Hex(),
						Symbol:   "BTC-USDT",
						Side:     BUY,
						Price:    uint256.NewInt(40000 + blockNum),
						Quantity: uint256.NewInt(10),
						OrigQty:  uint256.NewInt(10),
					},
				},
			})
			err = logger.OnBlockEnd(blockNum)
			require.NoError(t, err)
		}
		logger.Close()

		// Recover only from block 3 onwards
		d := NewDispatcher()
		recovery := NewEventRecovery(eventsDir)
		err = recovery.RecoverFromEvents(d, 3)
		require.NoError(t, err)

		// Should have orders only from blocks 3, 4, 5
		engines := d.GetEngines()
		engine := engines["BTC-USDT"]
		require.NotNil(t, engine)
		assert.Equal(t, 3, len(engine.buyQueue))
	})

	// Test TPSL order recovery
	t.Run("TPSLOrderRecovery", func(t *testing.T) {
		eventsDir := path.Join(tmpDir, "events3")
		logger, err := NewEventWALLogger(eventsDir)
		require.NoError(t, err)

		// Create TPSL events
		tpslOrder := &TPSLOrder{
			TPOrder: &StopOrder{
				StopPrice:    uint256.NewInt(3200),
				TriggerAbove: true,
				Order: &Order{
					OrderID:  "tpsl1",
					UserID:   common.Address{}.Hex(),
					Symbol:   "ETH-USDT",
					Side:     SELL,
					Price:    uint256.NewInt(3190),
					Quantity: uint256.NewInt(50),
					OrigQty:  uint256.NewInt(50),
				},
			},
		}

		logger.SetBlockContext(1)
		logger.LogEvents([]OrderbookEvent{
			&TPSLOrderAddedEvent{
				BaseEvent: BaseEvent{BlockNumber: 1, TxIndex: 0},
				TPSLOrder: tpslOrder,
			},
		})
		err = logger.OnBlockEnd(1)
		require.NoError(t, err)

		// Add removal event
		logger.SetBlockContext(2)
		logger.LogEvents([]OrderbookEvent{
			&TPSLOrderRemovedEvent{
				BaseEvent: BaseEvent{BlockNumber: 2, TxIndex: 0},
				OrderID:   "tpsl1",
				Symbol:    "ETH-USDT",
			},
		})
		err = logger.OnBlockEnd(2)
		require.NoError(t, err)
		logger.Close()

		// Recover
		d := NewDispatcher()
		recovery := NewEventRecovery(eventsDir)
		err = recovery.RecoverFromEvents(d, 0)
		require.NoError(t, err)

		// TPSL should be removed (added then removed)
		engine := d.GetEngines()["ETH-USDT"]
		require.NotNil(t, engine)
		assert.Equal(t, 0, len(engine.conditionalOrderManager.GetOrders()))
	})
}

// TestDeterministicRecovery tests that recovery produces identical state
func TestDeterministicRecovery(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "deterministic_test")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create a series of events that test determinism
	events := []OrderbookEvent{
		// Add orders
		&OrderAddedEvent{
			BaseEvent: BaseEvent{BlockNumber: 1},
			Order: &Order{
				OrderID: "buy1", UserID: "user1", Symbol: "ETH-USDT",
				Side: BUY, Price: uint256.NewInt(2900),
				Quantity: uint256.NewInt(100), OrigQty: uint256.NewInt(100),
			},
		},
		&OrderAddedEvent{
			BaseEvent: BaseEvent{BlockNumber: 1},
			Order: &Order{
				OrderID: "sell1", UserID: "user2", Symbol: "ETH-USDT",
				Side: SELL, Price: uint256.NewInt(3100),
				Quantity: uint256.NewInt(100), OrigQty: uint256.NewInt(100),
			},
		},
		// Partial fill
		&OrderQuantityUpdatedEvent{
			BaseEvent:   BaseEvent{BlockNumber: 2},
			OrderID:     "buy1",
			Symbol:      "ETH-USDT",
			NewQuantity: uint256.NewInt(70),
		},
		// Price update
		&PriceUpdatedEvent{
			BaseEvent: BaseEvent{BlockNumber: 2},
			Symbol:    "ETH-USDT",
			Price:     uint256.NewInt(3000),
		},
		// Order removal
		&OrderRemovedEvent{
			BaseEvent: BaseEvent{BlockNumber: 3},
			OrderID:   "sell1",
			Symbol:    "ETH-USDT",
			Side:      SELL,
		},
	}

	// Write events
	eventsDir := path.Join(tmpDir, "events")
	logger, err := NewEventWALLogger(eventsDir)
	require.NoError(t, err)

	currentBlock := uint64(0)
	for _, event := range events {
		blockNum := event.GetBase().BlockNumber
		if blockNum != currentBlock {
			if currentBlock > 0 {
				err = logger.OnBlockEnd(currentBlock)
				require.NoError(t, err)
			}
			currentBlock = blockNum
			logger.SetBlockContext(blockNum)
		}
		logger.LogEvents([]OrderbookEvent{event})
	}
	err = logger.OnBlockEnd(currentBlock)
	require.NoError(t, err)
	logger.Close()

	// Recover multiple times and verify identical state
	recovery := NewEventRecovery(eventsDir)

	d1 := NewDispatcher()
	err = recovery.RecoverFromEvents(d1, 0)
	require.NoError(t, err)

	d2 := NewDispatcher()
	err = recovery.RecoverFromEvents(d2, 0)
	require.NoError(t, err)

	// Compare states
	engine1 := d1.GetEngines()["ETH-USDT"]
	engine2 := d2.GetEngines()["ETH-USDT"]

	require.NotNil(t, engine1)
	require.NotNil(t, engine2)

	// Compare buy queues
	assert.Equal(t, len(engine1.buyQueue), len(engine2.buyQueue))
	if len(engine1.buyQueue) > 0 {
		assert.Equal(t, engine1.buyQueue[0].OrderID, engine2.buyQueue[0].OrderID)
		assert.Equal(t, engine1.buyQueue[0].Quantity, engine2.buyQueue[0].Quantity)
	}

	// Compare sell queues
	assert.Equal(t, len(engine1.sellQueue), len(engine2.sellQueue))

	// Compare current price
	assert.Equal(t, engine1.currentPrice, engine2.currentPrice)

	// Verify final state matches expectations
	assert.Equal(t, 1, len(engine1.buyQueue))
	assert.Equal(t, 0, len(engine1.sellQueue)) // sell1 was removed
	assert.Equal(t, uint256.NewInt(3000), engine1.currentPrice)

	buyOrder := engine1.buyQueue[0]
	assert.Equal(t, "buy1", buyOrder.OrderID)
	assert.Equal(t, uint256.NewInt(70), buyOrder.Quantity) // Updated quantity
}
