package persistence

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/metrics"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/ethdb"
	"github.com/ethereum/go-ethereum/log"
)

var (
	// Snapshot key prefixes
	snapshotPrefix     = []byte("snapshot:")
	snapshotMetaPrefix = []byte("snapshot:meta:")

	// Metadata keys
	lastSnapshotBlockKey = append(metaPrefix, []byte("last_snapshot_block")...)
	snapshotCountKey     = append(metaPrefix, []byte("snapshot_count")...)
)

// Snapshot represents a complete orderbook state at a specific block
type Snapshot struct {
	// Snapshot identity
	SnapshotID  string      `json:"snapshot_id"`
	BlockNumber uint64      `json:"block_number"`
	Timestamp   time.Time   `json:"timestamp"`
	StateRoot   common.Hash `json:"state_root"`

	// Orderbook state
	OrderbookState OrderbookState `json:"orderbook_state"`

	// Persistence state
	LastWALSequence    uint64 `json:"last_wal_sequence"`
	LastProcessedBlock uint64 `json:"last_processed_block"`

	// Metadata
	Version   string `json:"version"`
	Checksum  string `json:"checksum,omitempty"`
	SizeBytes int64  `json:"size_bytes"`
}

// OrderbookState represents the complete state of the orderbook
// Now uses DispatcherSnapshotData which includes everything
type OrderbookState struct {
	// Full dispatcher state (includes engines, balance manager, routing, cache)
	DispatcherSnapshot *types.DispatcherSnapshotData `json:"dispatcher_snapshot"`

	// Global state
	TotalOrders uint64 `json:"total_orders"`
	TotalTrades uint64 `json:"total_trades"`

	// Timestamp
	CreatedAt time.Time `json:"created_at"`
}

// Note: EngineState, OrderQueueState, and UserBookState have been removed.
// We now use types.EngineSnapshotData directly which contains minimal data:
// - Orders (from which queues and user mappings can be rebuilt)
// - CurrentPrice and LastTradeTime
// - Triggers and OCO pairs for conditional orders
// - BlockNumber for context

// SnapshotManager manages orderbook snapshots
type SnapshotManager struct {
	db ethdb.KeyValueStore

	// Configuration
	snapshotInterval uint64 // Blocks between snapshots
	asyncMode        bool   // Enable async snapshot creation

	// State
	lastSnapshotBlock uint64
	snapshotCount     int
	processing        atomic.Bool // Whether a snapshot is being processed

	// Synchronization
	mu sync.RWMutex

	// Lifecycle
	stopChan chan struct{}
	wg       sync.WaitGroup
}

// NewSnapshotManager creates a new snapshot manager
func NewSnapshotManager(db ethdb.KeyValueStore, snapshotInterval uint64) *SnapshotManager {
	return NewSnapshotManagerWithConfig(db, snapshotInterval, true)
}

// NewSnapshotManagerWithConfig creates a new snapshot manager with custom config
func NewSnapshotManagerWithConfig(db ethdb.KeyValueStore, snapshotInterval uint64, asyncMode bool) *SnapshotManager {
	manager := &SnapshotManager{
		db:               db,
		snapshotInterval: snapshotInterval,
		asyncMode:        asyncMode,
		stopChan:         make(chan struct{}),
	}

	// Load metadata
	manager.loadMetadata()

	return manager
}

// Start starts the snapshot manager
func (s *SnapshotManager) Start() {
	log.Debug("Snapshot manager started",
		"interval", s.snapshotInterval,
		"lastSnapshot", s.lastSnapshotBlock,
		"count", s.snapshotCount)
}

// Stop stops the snapshot manager
func (s *SnapshotManager) Stop() error {
	close(s.stopChan)
	s.wg.Wait()

	// Wait for any async snapshot to complete
	for s.processing.Load() {
		time.Sleep(100 * time.Millisecond)
	}

	log.Debug("Snapshot manager stopped")
	return nil
}

// loadMetadata loads snapshot metadata from the database
func (s *SnapshotManager) loadMetadata() {
	// Load last snapshot block
	if data, err := s.db.Get(lastSnapshotBlockKey); err == nil && len(data) == 8 {
		s.lastSnapshotBlock = binary.BigEndian.Uint64(data)
	}

	// Load snapshot count
	if data, err := s.db.Get(snapshotCountKey); err == nil && len(data) == 4 {
		s.snapshotCount = int(binary.BigEndian.Uint32(data))
	}
}

// saveMetadata saves snapshot metadata to the database
func (s *SnapshotManager) saveMetadata() error {
	batch := s.db.NewBatch()

	// Save last snapshot block
	blockBytes := make([]byte, 8)
	binary.BigEndian.PutUint64(blockBytes, s.lastSnapshotBlock)
	if err := batch.Put(lastSnapshotBlockKey, blockBytes); err != nil {
		return err
	}

	// Save snapshot count
	countBytes := make([]byte, 4)
	binary.BigEndian.PutUint32(countBytes, uint32(s.snapshotCount))
	if err := batch.Put(snapshotCountKey, countBytes); err != nil {
		return err
	}

	return batch.Write()
}

// CreateSnapshot creates a new snapshot of the orderbook state
func (s *SnapshotManager) CreateSnapshot(dispatcherSnapshot *types.DispatcherSnapshotData, blockNum uint64, stateRoot common.Hash, walSequence uint64) (*Snapshot, error) {
	// Check if already processing (for async mode)
	if s.asyncMode && !s.processing.CompareAndSwap(false, true) {
		return nil, fmt.Errorf("snapshot already in progress")
	}

	log.Debug("Creating snapshot", "block", blockNum, "async", s.asyncMode)

	// Create orderbook state from dispatcher snapshot (fast, in-memory)
	orderbookState := s.captureOrderbookState(dispatcherSnapshot)

	// Create snapshot object
	snapshot := &Snapshot{
		SnapshotID:         fmt.Sprintf("snapshot_%d_%d", blockNum, time.Now().Unix()),
		BlockNumber:        blockNum,
		Timestamp:          time.Now(),
		StateRoot:          stateRoot,
		OrderbookState:     orderbookState,
		LastWALSequence:    walSequence,
		LastProcessedBlock: blockNum,
		Version:            "v2.0.0",
	}

	if s.asyncMode {
		// Update in-memory state immediately to prevent race condition
		// But only save to DB after successful snapshot write
		s.mu.Lock()
		previousSnapshotBlock := s.lastSnapshotBlock
		s.lastSnapshotBlock = blockNum
		s.snapshotCount++
		s.mu.Unlock()

		// Async mode - serialize and save in background
		s.wg.Add(1)
		go func() {
			defer s.wg.Done()
			defer s.processing.Store(false)

			startTime := time.Now()

			// Calculate size and checksum
			if data, err := json.Marshal(snapshot); err == nil {
				snapshot.SizeBytes = int64(len(data))
				snapshot.Checksum = common.BytesToHash(data).Hex()
			}

			// Write to database
			if err := s.writeSnapshot(snapshot); err != nil {
				log.Error("Failed to write snapshot async, rolling back in-memory state",
					"block", blockNum,
					"error", err)

				// Rollback the in-memory state on write failure
				s.mu.Lock()
				// Only rollback if this block is still recorded as the last snapshot
				// (another snapshot may have been created in the meantime)
				if s.lastSnapshotBlock == blockNum {
					s.lastSnapshotBlock = previousSnapshotBlock
					s.snapshotCount--
				}
				s.mu.Unlock()
				return
			}

			// Only save metadata to DB after successful snapshot write
			if err := s.saveMetadata(); err != nil {
				log.Error("Failed to save snapshot metadata", "error", err)
				return
			}

			// Update metrics
			metrics.PersistenceSnapshotTimer.UpdateSince(startTime)
			metrics.PersistenceSnapshotsCounter.Inc(1)
			metrics.PersistenceSnapshotSizeGauge.Update(snapshot.SizeBytes)

			log.Info("Snapshot saved async",
				"id", snapshot.SnapshotID,
				"timestamp", snapshot.Timestamp,
				"block", blockNum,
				"checksum", snapshot.Checksum,
				"size", snapshot.SizeBytes,
				"duration", time.Since(startTime))
		}()

		return snapshot, nil
	} else {
		// Sync mode - original behavior
		s.mu.Lock()
		defer s.mu.Unlock()

		// Calculate size and checksum
		if data, err := json.Marshal(snapshot); err == nil {
			snapshot.SizeBytes = int64(len(data))
			snapshot.Checksum = common.BytesToHash(data).Hex()
		}

		// Write to database
		startTime := time.Now()
		if err := s.writeSnapshot(snapshot); err != nil {
			return nil, fmt.Errorf("failed to write snapshot: %w", err)
		}
		metrics.PersistenceSnapshotTimer.UpdateSince(startTime)
		metrics.PersistenceSnapshotsCounter.Inc(1)
		metrics.PersistenceSnapshotSizeGauge.Update(snapshot.SizeBytes)

		// Update metadata
		s.lastSnapshotBlock = blockNum
		s.snapshotCount++

		if err := s.saveMetadata(); err != nil {
			return nil, fmt.Errorf("failed to save metadata: %w", err)
		}

		log.Info("Snapshot created successfully",
			"id", snapshot.SnapshotID,
			"block", blockNum,
			"size", snapshot.SizeBytes,
			"checksum", snapshot.Checksum)

		return snapshot, nil
	}
}

// captureOrderbookState captures the current state from dispatcher snapshot
func (s *SnapshotManager) captureOrderbookState(dispatcherSnapshot *types.DispatcherSnapshotData) OrderbookState {
	state := OrderbookState{
		DispatcherSnapshot: dispatcherSnapshot,
		CreatedAt:          time.Now(),
	}

	// Calculate totals from all engines
	for _, engineSnapshot := range dispatcherSnapshot.Engines {
		state.TotalOrders += uint64(len(engineSnapshot.Orders))
		// Note: TotalTrades is not tracked in minimal snapshot
	}

	return state
}

// captureEngineState captures the state of a single symbol engine
// Note: captureEngineState has been removed as we now use GetSnapshotData() directly
// which returns types.EngineSnapshotData with minimal required data

// writeSnapshot writes a snapshot to the database
func (s *SnapshotManager) writeSnapshot(snapshot *Snapshot) error {
	// Create key: snapshot:{blockNum}
	key := s.makeSnapshotKey(snapshot.BlockNumber)

	// Serialize snapshot
	value, err := json.Marshal(snapshot)
	if err != nil {
		return fmt.Errorf("failed to marshal snapshot: %w", err)
	}

	// Write to database
	if err := s.db.Put(key, value); err != nil {
		return fmt.Errorf("failed to write snapshot to database: %w", err)
	}

	// Write metadata entry
	metaKey := s.makeSnapshotMetaKey(snapshot.BlockNumber)
	metaValue, _ := json.Marshal(struct {
		ID        string    `json:"id"`
		Block     uint64    `json:"block"`
		Timestamp time.Time `json:"timestamp"`
		Size      int64     `json:"size"`
	}{
		ID:        snapshot.SnapshotID,
		Block:     snapshot.BlockNumber,
		Timestamp: snapshot.Timestamp,
		Size:      snapshot.SizeBytes,
	})

	return s.db.Put(metaKey, metaValue)
}

// LoadSnapshot loads a snapshot by block number
func (s *SnapshotManager) LoadSnapshot(blockNum uint64) (*Snapshot, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	key := s.makeSnapshotKey(blockNum)

	value, err := s.db.Get(key)
	if err != nil {
		return nil, fmt.Errorf("snapshot not found for block %d: %w", blockNum, err)
	}

	var snapshot Snapshot
	if err := json.Unmarshal(value, &snapshot); err != nil {
		return nil, fmt.Errorf("failed to unmarshal snapshot: %w", err)
	}

	return &snapshot, nil
}

// GetLatestSnapshot returns the most recent snapshot
func (s *SnapshotManager) GetLatestSnapshot() (*Snapshot, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if s.lastSnapshotBlock == 0 {
		return nil, fmt.Errorf("no snapshots available")
	}

	return s.LoadSnapshot(s.lastSnapshotBlock)
}

// GetNearestSnapshot finds the nearest snapshot before or at the given block
func (s *SnapshotManager) GetNearestSnapshot(blockNum uint64) (*Snapshot, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	// Find all snapshot blocks
	blocks := s.findSnapshotBlocks()

	// Find the nearest block <= blockNum
	var nearestBlock uint64
	for _, block := range blocks {
		if block <= blockNum && block > nearestBlock {
			nearestBlock = block
		}
	}

	if nearestBlock == 0 {
		return nil, fmt.Errorf("no snapshot found before block %d", blockNum)
	}

	return s.LoadSnapshot(nearestBlock)
}

// ShouldSnapshot determines if a snapshot should be taken at the given block
func (s *SnapshotManager) ShouldSnapshot(blockNum uint64) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if s.snapshotInterval == 0 {
		return false // Snapshots disabled
	}

	// Check if enough blocks have passed since last snapshot
	if s.lastSnapshotBlock == 0 {
		return true // First snapshot
	}

	return blockNum-s.lastSnapshotBlock >= s.snapshotInterval
}

// pruneOldSnapshots removes old snapshots beyond the keep count
// Note: pruneOldSnapshots has been removed for simplicity
// All snapshots are kept indefinitely

// findSnapshotBlocks finds all snapshot block numbers in the database
func (s *SnapshotManager) findSnapshotBlocks() []uint64 {
	blocks := make([]uint64, 0)

	iter := s.db.NewIterator(snapshotMetaPrefix, nil)
	defer iter.Release()

	for iter.Next() {
		// Extract block number from key
		key := iter.Key()
		if len(key) > len(snapshotMetaPrefix) {
			blockBytes := key[len(snapshotMetaPrefix):]
			if len(blockBytes) == 8 {
				block := binary.BigEndian.Uint64(blockBytes)
				blocks = append(blocks, block)
			}
		}
	}

	return blocks
}

// makeSnapshotKey creates a database key for a snapshot
func (s *SnapshotManager) makeSnapshotKey(blockNum uint64) []byte {
	key := make([]byte, len(snapshotPrefix)+8)
	copy(key, snapshotPrefix)
	binary.BigEndian.PutUint64(key[len(snapshotPrefix):], blockNum)
	return key
}

// makeSnapshotMetaKey creates a metadata key for a snapshot
func (s *SnapshotManager) makeSnapshotMetaKey(blockNum uint64) []byte {
	key := make([]byte, len(snapshotMetaPrefix)+8)
	copy(key, snapshotMetaPrefix)
	binary.BigEndian.PutUint64(key[len(snapshotMetaPrefix):], blockNum)
	return key
}

// GetSnapshotInterval returns the snapshot interval
func (s *SnapshotManager) GetSnapshotInterval() uint64 {
	return s.snapshotInterval
}

// SetSnapshotInterval sets the snapshot interval
func (s *SnapshotManager) SetSnapshotInterval(interval uint64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.snapshotInterval = interval
}

// GetLastSnapshotBlock returns the last snapshot block number
func (s *SnapshotManager) GetLastSnapshotBlock() uint64 {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.lastSnapshotBlock
}
