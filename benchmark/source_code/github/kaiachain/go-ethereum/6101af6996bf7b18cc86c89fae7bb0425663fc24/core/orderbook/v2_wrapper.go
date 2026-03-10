package orderbook

import (
	"github.com/ethereum/go-ethereum/core/orderbook/v2/persistence"
	v2system "github.com/ethereum/go-ethereum/core/orderbook/v2/system"
	v2types "github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/ethdb"
	"github.com/ethereum/go-ethereum/log"
)

// OrderbookSystemV2Wrapper wraps the v2 OrderbookSystem to implement IOrderbookSystem
type OrderbookSystemV2Wrapper struct {
	v2System *v2system.OrderbookSystem
	config   OrderbookConfig
}

// NewOrderbookSystemV2 creates a new v2 orderbook system wrapped to implement the common interface
// StateDB will be provided dynamically per request, not at initialization
func NewOrderbookSystemV2(config OrderbookConfig, db ethdb.KeyValueStore, blockchain persistence.StateProvider) IOrderbookSystem {
	// Convert config to v2 types
	v2Config := v2types.OrderbookConfig{
		Version:               config.Version,
		EnableMetrics:         config.EnableMetrics,
		MetricsInterval:       config.MetricsInterval,
		PersistenceEnabled:    config.PersistenceEnabled,
		PersistenceDir:        config.PersistenceDir,
		SnapshotInterval:      config.SnapshotInterval,
		AsyncSnapshotCreation: config.AsyncSnapshotCreation,
	}

	// Create v2 system with optional database
	v2System := v2system.NewOrderbookSystem(v2Config, db, blockchain)

	return &OrderbookSystemV2Wrapper{
		v2System: v2System,
		config:   config,
	}
}

// GetDispatcher returns the Dex interface for the v2 system
func (w *OrderbookSystemV2Wrapper) GetDispatcher() Dex {
	// Create and return the adapter which implements the Dex interface
	dispatcher := w.v2System.GetDispatcher()
	return NewDexAdapter(dispatcher)
}

// Start starts the v2 orderbook system
func (w *OrderbookSystemV2Wrapper) Start() {
	w.v2System.Start()
	log.Info("Orderbook v2 system started")
}

// Close gracefully shuts down the v2 orderbook system
func (w *OrderbookSystemV2Wrapper) Close() error {
	return w.v2System.Close()
}

// GetLastSnapshotBlock returns the last recovered snapshot block number
// Returns 0 if no snapshot was recovered
func (w *OrderbookSystemV2Wrapper) GetLastSnapshotBlock() uint64 {
	return w.v2System.GetLastSnapshotBlock()
}

// SetCurrentBlock sets the current block context for persistence
func (w *OrderbookSystemV2Wrapper) SetCurrentBlock(blockNum uint64) {
	w.v2System.SetCurrentBlock(blockNum)
}

// OnBlockEnd handles end-of-block processing for v2 system
func (w *OrderbookSystemV2Wrapper) OnBlockEnd(blockNum uint64) error {
	return w.v2System.OnBlockEnd(blockNum)
}
