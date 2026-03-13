package system

import (
	v2dispatcher "github.com/ethereum/go-ethereum/core/orderbook/v2/dispatcher"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/persistence"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/ethdb"
	"github.com/ethereum/go-ethereum/log"
)

// OrderbookSystem manages the overall orderbook v2 system
type OrderbookSystem struct {
	config     types.OrderbookConfig
	dispatcher *v2dispatcher.Dispatcher
	persistence *persistence.PersistenceManager // System manages persistence lifecycle
	// No longer need adapter - dispatcher can implement Dex interface directly

	// System state
	isRunning bool

	// TODO-Orderbook: Implement metrics collection for v2
	// - Add metrics collection similar to v1
	// - Track orders, trades, symbols, engines
}

// NewOrderbookSystem creates a new orderbook v2 system
// StateDB will be provided dynamically per request, not at initialization
// db is optional - if provided, persistence will be enabled
// blockchain is optional - if provided, enables state recovery from blockchain
func NewOrderbookSystem(config types.OrderbookConfig, db ethdb.KeyValueStore, blockchain persistence.StateProvider) *OrderbookSystem {
	system := &OrderbookSystem{
		config:    config,
		isRunning: true, // Mark as running by default
	}

	// Initialize persistence if database is provided
	if db != nil && config.PersistenceEnabled {
		system.persistence = persistence.NewPersistenceManager(db, config, blockchain)
		log.Debug("Orderbook v2 initialized with persistence")
	} else {
		log.Debug("Orderbook v2 initialized without persistence")
	}

	// Initialize dispatcher with persistence manager
	system.dispatcher = v2dispatcher.NewDispatcher(system.persistence)

	log.Debug("Orderbook v2 system initialized")

	return system
}

// GetDispatcher returns the v2 dispatcher directly
// Note: The adapter is created in the wrapper to avoid import cycles
func (s *OrderbookSystem) GetDispatcher() *v2dispatcher.Dispatcher {
	return s.dispatcher
}

// GetV2Dispatcher returns the v2 dispatcher directly for tests/migration
func (s *OrderbookSystem) GetV2Dispatcher() *v2dispatcher.Dispatcher {
	return s.dispatcher
}

// GetPersistence returns the persistence manager
func (s *OrderbookSystem) GetPersistence() *persistence.PersistenceManager {
	return s.persistence
}

// Start starts the orderbook system
func (s *OrderbookSystem) Start() {
	s.isRunning = true

	// Start persistence manager if enabled
	if s.persistence != nil {
		if err := s.persistence.Start(); err != nil {
			log.Error("Failed to start persistence manager", "error", err)
			// Continue without persistence
			s.persistence = nil
		} else {
			// Try to recover from persistence
			if err := s.persistence.Recover(s.dispatcher); err != nil {
				log.Error("Failed to recover from persistence", "error", err)
				// Continue with empty state
			} else {
				log.Debug("Orderbook v2 recovered from persistence")
			}
		}
	}

	// Start dispatcher workers
	s.dispatcher.Start()

	// TODO-Orderbook: Start metrics collection loop when implemented
}

// SetCurrentBlock sets the current block context for persistence
func (s *OrderbookSystem) SetCurrentBlock(blockNum uint64) {
	// Forward to dispatcher which manages persistence
	s.dispatcher.SetCurrentBlock(blockNum)
}

// OnBlockEnd is called at the end of each block for snapshot checks
func (s *OrderbookSystem) OnBlockEnd(blockNum uint64) error {
	// Forward to dispatcher which manages persistence
	s.dispatcher.OnBlockEnd(blockNum)
	return nil
}

// Close gracefully shuts down the orderbook system
func (s *OrderbookSystem) Close() error {
	if !s.isRunning {
		return nil
	}

	log.Debug("Shutting down orderbook v2 system...")
	s.isRunning = false

	// Stop dispatcher and wait for workers to finish
	if err := s.dispatcher.Stop(); err != nil {
		log.Error("Error stopping dispatcher", "error", err)
	}

	// Stop persistence manager if enabled
	if s.persistence != nil {
		if err := s.persistence.Stop(); err != nil {
			log.Error("Failed to stop persistence manager", "error", err)
		}
	}

	log.Debug("Orderbook v2 system shutdown complete")
	return nil
}

// GetLastSnapshotBlock returns the last recovered snapshot block number
// Returns 0 if no snapshot was recovered
func (s *OrderbookSystem) GetLastSnapshotBlock() uint64 {
	if s.persistence == nil {
		return 0
	}
	return s.persistence.GetLastSnapshotBlock()
}
