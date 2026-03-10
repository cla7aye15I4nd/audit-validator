package persistence

import (
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	metrics "github.com/ethereum/go-ethereum/core/orderbook/v2/metrics"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/ethdb"
	"github.com/ethereum/go-ethereum/log"
)

// PersistenceManager manages orderbook persistence
type PersistenceManager struct {
	config types.OrderbookConfig
	db     ethdb.KeyValueStore

	// Core components
	walManager      *WALManager
	snapshotManager *SnapshotManager
	recoveryEngine  *RecoveryEngine

	// State tracking
	currentBlock uint64
	isRecovered  bool

	// Synchronization
	mu      sync.RWMutex
	enabled atomic.Bool

	// Lifecycle
	stopChan chan struct{}
	wg       sync.WaitGroup
}

// NewPersistenceManager creates a new persistence manager
func NewPersistenceManager(db ethdb.KeyValueStore, config types.OrderbookConfig, provider StateProvider) *PersistenceManager {
	// Create WAL manager (always synchronous)
	walManager := NewWALManager(db)

	// Create snapshot manager with async config if enabled
	var snapshotManager *SnapshotManager
	if config.AsyncSnapshotCreation {
		snapshotManager = NewSnapshotManagerWithConfig(db, config.SnapshotInterval, true)
	} else {
		snapshotManager = NewSnapshotManagerWithConfig(db, config.SnapshotInterval, false)
	}

	// Use default state provider initially
	// Can be replaced with SetBlockchain() if blockchain is available
	recoveryEngine := NewRecoveryEngine(db, walManager, snapshotManager, provider)

	manager := &PersistenceManager{
		config:          config,
		db:              db,
		walManager:      walManager,
		snapshotManager: snapshotManager,
		recoveryEngine:  recoveryEngine,
		stopChan:        make(chan struct{}),
	}

	manager.enabled.Store(config.PersistenceEnabled)

	log.Debug("Persistence manager created",
		"asyncSnapshotCreation", config.AsyncSnapshotCreation,
		"snapshotInterval", config.SnapshotInterval)

	return manager
}

// Start starts the persistence manager
func (p *PersistenceManager) Start() error {
	if !p.enabled.Load() {
		log.Debug("Persistence manager disabled")
		return nil
	}

	// Start components
	//p.walManager.Start()
	p.snapshotManager.Start()

	log.Debug("Persistence manager started",
		"enabled", p.config.PersistenceEnabled,
		"snapshotInterval", p.config.SnapshotInterval)

	return nil
}

// Stop stops the persistence manager
func (p *PersistenceManager) Stop() error {
	close(p.stopChan)
	p.wg.Wait()

	// Stop components
	if err := p.walManager.Stop(); err != nil {
		return fmt.Errorf("failed to stop WAL manager: %w", err)
	}

	if err := p.snapshotManager.Stop(); err != nil {
		return fmt.Errorf("failed to stop snapshot manager: %w", err)
	}

	log.Debug("Persistence manager stopped")
	return nil
}

// SetEnabled enables or disables persistence
func (p *PersistenceManager) SetEnabled(enabled bool) {
	p.enabled.Store(enabled)
	log.Debug("Persistence enabled status changed", "enabled", enabled)
}

// IsEnabled returns whether persistence is enabled
func (p *PersistenceManager) IsEnabled() bool {
	return p.enabled.Load()
}

// SetBlockContext sets the current block context
func (p *PersistenceManager) SetBlockContext(blockNum uint64) {
	p.mu.Lock()
	defer p.mu.Unlock()

	p.currentBlock = blockNum
}

// LogRequest logs a request before processing
func (p *PersistenceManager) LogRequest(req interfaces.Request) (uint64, error) {
	if !p.enabled.Load() {
		return 0, nil
	}

	p.mu.RLock()
	blockNum := p.currentBlock
	p.mu.RUnlock()

	return p.walManager.LogRequest(req, blockNum)
}

// LogResponse logs a response after processing
func (p *PersistenceManager) LogResponse(walSequence uint64, resp interfaces.Response) error {
	if !p.enabled.Load() || walSequence == 0 {
		return nil
	}

	p.mu.RLock()
	blockNum := p.currentBlock
	p.mu.RUnlock()

	return p.walManager.LogResponse(blockNum, walSequence, resp)
}

func (p *PersistenceManager) WriteSnapshot(blockNum uint64, dispatcher interfaces.Dispatcher) error {
	if !p.enabled.Load() {
		return nil
	}

	if p.config.AsyncSnapshotCreation {
		// Async mode - create snapshot in background
		p.wg.Add(1)
		go func() {
			defer p.wg.Done()
			if err := p.createSnapshot(blockNum, dispatcher); err != nil {
				log.Error("Failed to create snapshot async", "block", blockNum, "error", err)
			}
		}()
		return nil
	} else {
		// Sync mode - create snapshot immediately
		return p.createSnapshot(blockNum, dispatcher)
	}
}

// OnBlockEnd is called at the end of each block for snapshot checks
func (p *PersistenceManager) OnBlockEnd(blockNum uint64, dispatcher interfaces.Dispatcher) error {
	if !p.enabled.Load() {
		return nil
	}

	//// Check if snapshot is needed
	//if p.snapshotManager.ShouldSnapshot(blockNum) {
	//	if p.config.AsyncSnapshotCreation {
	//		// Async mode - create snapshot in background
	//		p.wg.Add(1)
	//		go func() {
	//			defer p.wg.Done()
	//			if err := p.createSnapshot(blockNum, dispatcher); err != nil {
	//				log.Error("Failed to create snapshot async", "block", blockNum, "error", err)
	//			}
	//		}()
	//		return nil
	//	} else {
	//		// Sync mode - create snapshot immediately
	//		return p.createSnapshot(blockNum, dispatcher)
	//	}
	//}

	return nil
}

// createSnapshot creates a new snapshot
func (p *PersistenceManager) createSnapshot(blockNum uint64, dispatcher interfaces.Dispatcher) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	log.Debug("Creating snapshot", "block", blockNum)

	// Get WAL sequence
	walSequence := p.walManager.GetLastSequence()

	// Get full dispatcher snapshot
	dispatcherSnapshot := dispatcher.GetSnapshotData(blockNum)

	// Create snapshot
	_, err := p.snapshotManager.CreateSnapshot(
		dispatcherSnapshot,
		blockNum,
		common.Hash{}, // TODO: Get actual state root
		walSequence,
	)

	if err != nil {
		return fmt.Errorf("failed to create snapshot: %w", err)
	}

	return nil
}

// GetLastSnapshotBlock returns the last recovered snapshot block number
// Returns 0 if no snapshot was recovered
func (p *PersistenceManager) GetLastSnapshotBlock() uint64 {
	if p.snapshotManager == nil {
		return 0
	}
	return p.snapshotManager.GetLastSnapshotBlock()
}

// Recover performs recovery from persistence
func (p *PersistenceManager) Recover(dispatcher interfaces.Dispatcher) error {
	// Check if there's anything to recover
	lastWALSeq := p.walManager.GetLastSequence()
	lastSnapshot := p.snapshotManager.GetLastSnapshotBlock()

	if lastWALSeq == 0 && lastSnapshot == 0 {
		log.Debug("No persistence data to recover")
		return nil
	}

	log.Debug("Starting recovery",
		"lastWAL", lastWALSeq,
		"lastSnapshot", lastSnapshot)

	// Start recovery timer
	recoveryStart := time.Now()
	defer func() {
		metrics.PersistenceRecoveryTimer.UpdateSince(recoveryStart)
	}()

	// Perform recovery
	if err := p.recoveryEngine.RecoverFromColdStart(dispatcher); err != nil {
		metrics.PersistenceRecoveryErrorsCounter.Inc(1)
		return fmt.Errorf("recovery failed: %w", err)
	}

	p.mu.Lock()
	p.isRecovered = true
	p.mu.Unlock()

	// Get recovery stats
	stats := p.recoveryEngine.GetStats()
	log.Debug("Recovery completed",
		"duration", stats.EndTime.Sub(stats.StartTime),
		"walEntries", stats.WALEntriesReplayed,
		"lastBlock", stats.LastBlock,
		"errors", len(stats.Errors))

	return nil
}

// RecoverToBlock recovers to a specific block
func (p *PersistenceManager) RecoverToBlock(dispatcher interfaces.Dispatcher, targetBlock uint64) error {
	log.Debug("Recovering to block", "target", targetBlock)

	if err := p.recoveryEngine.RecoverFromBlock(dispatcher, targetBlock); err != nil {
		return fmt.Errorf("recovery to block %d failed: %w", targetBlock, err)
	}

	p.mu.Lock()
	p.isRecovered = true
	p.currentBlock = targetBlock
	p.mu.Unlock()

	return nil
}

// ForceSnapshot forces creation of a snapshot
func (p *PersistenceManager) ForceSnapshot(dispatcher interfaces.Dispatcher) error {
	p.mu.RLock()
	blockNum := p.currentBlock
	p.mu.RUnlock()

	return p.createSnapshot(blockNum, dispatcher)
}

// GetMetrics returns persistence metrics
func (p *PersistenceManager) GetMetrics() map[string]interface{} {
	p.mu.RLock()
	defer p.mu.RUnlock()

	return map[string]interface{}{
		"enabled":           p.enabled.Load(),
		"current_block":     p.currentBlock,
		"is_recovered":      p.isRecovered,
		"wal_sequence":      p.walManager.GetLastSequence(),
		"last_snapshot":     p.snapshotManager.GetLastSnapshotBlock(),
		"snapshot_interval": p.config.SnapshotInterval,
	}
}
