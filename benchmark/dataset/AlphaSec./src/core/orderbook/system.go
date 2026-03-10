package orderbook

import (
	"fmt"
	"os"
	"time"

	"github.com/ethereum/go-ethereum/log"
)

// OrderbookSystem manages the overall orderbook system
// Implements IOrderbookSystem for v1 orderbook
type OrderbookSystem struct {
	config     OrderbookConfig
	dispatcher *Dispatcher

	// TODO-Orderbook: Collect metrics later
	// System state
	isRunning bool
	metrics   SystemMetrics
}

type SystemMetrics struct {
	TotalOrders   uint64
	TotalTrades   uint64
	TotalSymbols  uint64
	ActiveEngines int
	LastUpdated   time.Time
}

// NewOrderbookSystem creates a new orderbook system with optional persistence
func NewOrderbookSystem(config OrderbookConfig) *OrderbookSystem {
	system := &OrderbookSystem{
		config:    config,
		isRunning: true, // Mark as running by default
	}

	// Initialize dispatcher with optional persistence
	if config.PersistenceEnabled {
		dispatcher, err := initializeWithPersistence(config)
		if err != nil {
			log.Error("Failed to initialize with persistence, falling back to non-persistent mode", "error", err)
			system.dispatcher = NewDispatcher()
		} else {
			system.dispatcher = dispatcher
		}
	} else {
		system.dispatcher = NewDispatcher()
		log.Info("Orderbook persistence disabled")
	}

	return system
}

// initializeWithPersistence attempts to recover from existing data and enables persistence
func initializeWithPersistence(config OrderbookConfig) (*Dispatcher, error) {
	// Ensure directory exists
	if err := os.MkdirAll(config.PersistenceDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create persistence directory: %w", err)
	}

	// Create dispatcher
	dispatcher := NewDispatcher()

	// Create persistence manager first
	pm, err := NewPersistenceManager(config.PersistenceDir, config.SnapshotInterval)
	if err != nil {
		return nil, fmt.Errorf("failed to create persistence manager: %w", err)
	}
	dispatcher.persistence = pm

	// Try to recover using the persistence manager
	if err := pm.Recover(dispatcher); err != nil {
		log.Warn("Recovery failed, starting fresh orderbook", "error", err)
		// Continue with empty dispatcher
	} else {
		engines := dispatcher.GetEngines()
		routing := dispatcher.GetOrderRouting()
		log.Info("Successfully recovered orderbook from persistence",
			"symbols", len(engines),
			"orders", len(routing))
	}

	log.Info("Orderbook persistence initialized",
		"dataDir", config.PersistenceDir,
		"snapshotInterval", config.SnapshotInterval)

	return dispatcher, nil
}

// GetDispatcher returns the current dispatcher as Dex interface
func (s *OrderbookSystem) GetDispatcher() Dex {
	return s.dispatcher
}

// Start starts the orderbook system
func (s *OrderbookSystem) Start() {
	s.isRunning = true
	log.Info("Orderbook system started")
}

// GetMetrics returns current system metrics
func (s *OrderbookSystem) GetMetrics() SystemMetrics {
	return s.metrics
}

// metricsLoop collects system metrics
func (s *OrderbookSystem) metricsLoop() {
	ticker := time.NewTicker(s.config.MetricsInterval)
	defer ticker.Stop()

	for s.isRunning {
		select {
		case <-ticker.C:
			s.collectMetrics()
		}
	}
}

// collectMetrics collects current system metrics
func (s *OrderbookSystem) collectMetrics() {
	if s.dispatcher == nil {
		return
	}

	engines := s.dispatcher.GetEngines()

	s.metrics = SystemMetrics{
		ActiveEngines: len(engines),
		LastUpdated:   time.Now(),
	}

	// TODO: Collect more detailed metrics
	// - Total orders across all engines
	// - Total trades across all engines

	log.Debug("Metrics collected",
		"activeEngines", s.metrics.ActiveEngines)
}

// Close gracefully shuts down the orderbook system
func (s *OrderbookSystem) Close() error {
	if !s.isRunning {
		return nil
	}

	log.Info("Shutting down orderbook system...")
	s.isRunning = false

	// Close the dispatcher (which will close persistence and flush events)
	if s.dispatcher != nil {
		if err := s.dispatcher.Close(); err != nil {
			log.Error("Failed to close dispatcher", "error", err)
			return err
		}
	}

	log.Info("Orderbook system shutdown complete")
	return nil
}

// GetLastSnapshotBlock returns the last recovered snapshot block number
// Returns 0 if no snapshot was recovered or persistence is disabled
func (s *OrderbookSystem) GetLastSnapshotBlock() uint64 {
	if s.dispatcher == nil || s.dispatcher.persistence == nil {
		return 0
	}
	return s.dispatcher.persistence.GetLastRecoveredBlock()
}
