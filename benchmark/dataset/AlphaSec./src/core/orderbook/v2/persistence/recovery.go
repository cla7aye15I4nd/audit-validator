package persistence

import (
	"fmt"
	"sort"
	"time"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/ethdb"
	"github.com/ethereum/go-ethereum/log"
)

// RecoveryEngine handles orderbook state recovery from persistence
type RecoveryEngine struct {
	db              ethdb.KeyValueStore
	walManager      *WALManager
	snapshotManager *SnapshotManager
	serializer      *RequestSerializer

	// State provider for replay
	stateProvider StateProvider

	// Recovery statistics
	stats RecoveryStats
}

// StateProvider provides historical state for recovery
type StateProvider interface {
	// GetStateDB returns the StateDB at a specific block
	GetStateDB(blockNum uint64) (types.StateDB, error)

	// GetFeeGetter returns the FeeGetter at a specific block
	GetFeeGetter(blockNum uint64) (types.FeeRetriever, error)
}

// RecoveryStats tracks recovery statistics
type RecoveryStats struct {
	StartTime          time.Time
	EndTime            time.Time
	SnapshotLoaded     bool
	SnapshotBlock      uint64
	WALEntriesReplayed uint64
	LastBlock          uint64
	Errors             []error
}

// NewRecoveryEngine creates a new recovery engine
func NewRecoveryEngine(db ethdb.KeyValueStore, walManager *WALManager, snapshotManager *SnapshotManager, stateProvider StateProvider) *RecoveryEngine {
	return &RecoveryEngine{
		db:              db,
		walManager:      walManager,
		snapshotManager: snapshotManager,
		serializer:      NewRequestSerializer(),
		stateProvider:   stateProvider,
	}
}

// RecoverFromColdStart performs a complete recovery from persistence
func (r *RecoveryEngine) RecoverFromColdStart(dispatcher interfaces.Dispatcher) error {
	r.stats = RecoveryStats{
		StartTime: time.Now(),
		Errors:    make([]error, 0),
	}

	log.Debug("Starting cold recovery")

	// Try to load latest snapshot
	snapshot, err := r.snapshotManager.GetLatestSnapshot()
	if err != nil {
		log.Warn("No snapshot found, recovering from genesis", "error", err)
		//return r.recoverFromGenesis(dispatcher)
		return nil
	}

	// Restore from snapshot
	if err := r.restoreFromSnapshot(dispatcher, snapshot); err != nil {
		return fmt.Errorf("failed to restore from snapshot: %w", err)
	}

	r.stats.SnapshotLoaded = true
	r.stats.SnapshotBlock = snapshot.BlockNumber

	//// Replay WAL from snapshot point
	//entries, err := r.walManager.GetEntriesSince(snapshot.BlockNumber + 1)
	//if err != nil {
	//	return fmt.Errorf("failed to get WAL entries: %w", err)
	//}
	//
	//log.Info("Replaying WAL entries", "count", len(entries), "fromBlock", snapshot.BlockNumber+1)
	//
	//// Use the new batch replay method that groups by block
	//if err := r.replayWALEntries(dispatcher, entries); err != nil {
	//	log.Error("Failed to replay WAL entries", "error", err)
	//}

	r.stats.EndTime = time.Now()

	log.Info("Cold recovery completed",
		"duration", r.stats.EndTime.Sub(r.stats.StartTime),
		"snapshotBlock", r.stats.SnapshotBlock,
		"walEntries", r.stats.WALEntriesReplayed,
		"lastBlock", r.stats.LastBlock,
		"errors", len(r.stats.Errors))

	return nil
}

// RecoverFromBlock recovers the orderbook state to a specific block
func (r *RecoveryEngine) RecoverFromBlock(dispatcher interfaces.Dispatcher, targetBlock uint64) error {
	r.stats = RecoveryStats{
		StartTime: time.Now(),
		Errors:    make([]error, 0),
	}

	log.Debug("Recovering to block", "target", targetBlock)

	// Find nearest snapshot before target block
	snapshot, err := r.snapshotManager.GetNearestSnapshot(targetBlock)
	if err != nil {
		log.Warn("No snapshot found before target block, recovering from genesis",
			"target", targetBlock, "error", err)
		return r.recoverToBlock(dispatcher, 0, targetBlock)
	}

	// Restore from snapshot
	if err := r.restoreFromSnapshot(dispatcher, snapshot); err != nil {
		return fmt.Errorf("failed to restore from snapshot: %w", err)
	}

	r.stats.SnapshotLoaded = true
	r.stats.SnapshotBlock = snapshot.BlockNumber

	// Replay WAL to target block
	return r.recoverToBlock(dispatcher, snapshot.BlockNumber+1, targetBlock)
}

// recoverFromGenesis recovers from the beginning (no snapshot)
func (r *RecoveryEngine) recoverFromGenesis(dispatcher interfaces.Dispatcher) error {
	// Get all WAL entries from the beginning
	entries, err := r.walManager.GetEntriesSince(0)
	if err != nil {
		return fmt.Errorf("failed to get WAL entries: %w", err)
	}

	log.Debug("Recovering from genesis", "entries", len(entries))

	// Use the new batch replay method that groups by block
	if err := r.replayWALEntries(dispatcher, entries); err != nil {
		log.Error("Failed to replay WAL entries", "error", err)
	}

	return nil
}

// recoverToBlock replays WAL entries from start to target block
func (r *RecoveryEngine) recoverToBlock(dispatcher interfaces.Dispatcher, startBlock, targetBlock uint64) error {
	// Get WAL entries in block range
	entries, err := r.walManager.GetEntriesSince(startBlock)
	if err != nil {
		return fmt.Errorf("failed to get WAL entries: %w", err)
	}

	// Filter entries up to target block
	var filteredEntries []*WALEntry
	for _, entry := range entries {
		if entry.BlockNumber > targetBlock {
			break
		}
		filteredEntries = append(filteredEntries, entry)
	}

	log.Debug("Replaying WAL entries to target block",
		"start", startBlock,
		"target", targetBlock,
		"entries", len(filteredEntries))

	// Use the new batch replay method that groups by block
	if err := r.replayWALEntries(dispatcher, filteredEntries); err != nil {
		log.Error("Failed to replay WAL entries", "error", err)
	}

	return nil
}

// restoreFromSnapshot restores the orderbook state from a snapshot
func (r *RecoveryEngine) restoreFromSnapshot(dispatcher interfaces.Dispatcher, snapshot *Snapshot) error {
	log.Debug("Restoring from snapshot",
		"id", snapshot.SnapshotID,
		"block", snapshot.BlockNumber)

	// Use dispatcher's RestoreFromSnapshot to restore complete state
	// This includes engines, balance manager, routing, and order cache
	if err := dispatcher.RestoreFromSnapshot(snapshot.OrderbookState.DispatcherSnapshot); err != nil {
		return fmt.Errorf("failed to restore dispatcher state: %w", err)
	}

	log.Info("Snapshot restoration completed",
		"engines", len(snapshot.OrderbookState.DispatcherSnapshot.Engines),
		"checksum", snapshot.Checksum,
		"locks", len(snapshot.OrderbookState.DispatcherSnapshot.Locks),
		"routes", len(snapshot.OrderbookState.DispatcherSnapshot.SymbolRouting),
		"cached_orders", len(snapshot.OrderbookState.DispatcherSnapshot.OrderCache))

	return nil
}

// replayWALEntries replays multiple WAL entries, grouping by block for state management
func (r *RecoveryEngine) replayWALEntries(dispatcher interfaces.Dispatcher, entries []*WALEntry) error {
	if len(entries) == 0 {
		return nil
	}

	// Group entries by block number
	entriesByBlock := make(map[uint64][]*WALEntry)
	for _, entry := range entries {
		entriesByBlock[entry.BlockNumber] = append(
			entriesByBlock[entry.BlockNumber],
			entry,
		)
	}

	// Get sorted block numbers to process in order
	var blockNums []uint64
	for blockNum := range entriesByBlock {
		blockNums = append(blockNums, blockNum)
	}
	// Sort block numbers to ensure consistent processing order
	sort.Slice(blockNums, func(i, j int) bool {
		return blockNums[i] < blockNums[j]
	})

	// Process each block's entries in order
	for _, blockNum := range blockNums {
		blockEntries := entriesByBlock[blockNum]

		// Get state once per block
		stateDB, err := r.stateProvider.GetStateDB(blockNum)
		if err != nil {
			log.Error("Failed to get StateDB for block", "block", blockNum, "error", err)
			r.stats.Errors = append(r.stats.Errors, fmt.Errorf("failed to get StateDB for block %d: %w", blockNum, err))
			continue
		}

		feeGetter, err := r.stateProvider.GetFeeGetter(blockNum)
		if err != nil {
			log.Error("Failed to get FeeGetter for block", "block", blockNum, "error", err)
			r.stats.Errors = append(r.stats.Errors, fmt.Errorf("failed to get FeeGetter for block %d: %w", blockNum, err))
			continue
		}

		if stateDB == nil {
			log.Error("StateDB is nil for block", "block", blockNum)
			continue
		}

		// Replay all entries in this block with the same state
		for _, entry := range blockEntries {
			if err := r.replayWALEntry(dispatcher, entry, stateDB, feeGetter); err != nil {
				log.Error("Failed to replay WAL entry",
					"sequence", entry.Sequence,
					"block", blockNum,
					"error", err)
				r.stats.Errors = append(r.stats.Errors, err)
			}
			r.stats.WALEntriesReplayed++
			r.stats.LastBlock = blockNum
		}
	}

	return nil
}

// replayWALEntry replays a single WAL entry with provided state
func (r *RecoveryEngine) replayWALEntry(dispatcher interfaces.Dispatcher, entry *WALEntry, stateDB types.StateDB, feeGetter types.FeeRetriever) error {
	// Skip if already processed
	if !entry.Processed {
		log.Warn("Skipping unprocessed WAL entry", "sequence", entry.Sequence)
		return nil
	}

	// Deserialize request with provided state
	request, blockNum, err := r.serializer.DeserializeRequest(entry.RequestData, stateDB, feeGetter)
	if err != nil {
		return fmt.Errorf("failed to deserialize request: %w", err)
	}

	// Verify block number matches
	if blockNum != entry.BlockNumber {
		return fmt.Errorf("block number mismatch: expected %d, got %d",
			entry.BlockNumber, blockNum)
	}

	// Process request through dispatcher
	// Note: This is synchronous replay, not async
	resp := dispatcher.ProcessRequestSync(request)

	// Verify response matches if we have response data
	if len(entry.ResponseData) > 0 {
		// TODO: Implement response verification
		log.Debug("Response verification not yet implemented")
	}

	// Check for errors
	if resp.Error() != nil && entry.Error == "" {
		return fmt.Errorf("replay produced error but original didn't: %w", resp.Error())
	}

	return nil
}

// VerifyIntegrity verifies the integrity of the recovered state
func (r *RecoveryEngine) VerifyIntegrity(dispatcher interfaces.Dispatcher, blockNum uint64) error {
	log.Debug("Verifying orderbook integrity", "block", blockNum)

	// Get current state
	stateDB, err := r.stateProvider.GetStateDB(blockNum)
	if err != nil {
		return fmt.Errorf("cannot get StateDB for block %d: %w", blockNum, err)
	}
	if stateDB == nil {
		return fmt.Errorf("StateDB is nil for block %d", blockNum)
	}

	// TODO: Implement integrity verification
	// - Compare order counts
	// - Verify balance consistency
	// - Check order queue integrity

	log.Debug("Integrity verification completed")
	return nil
}

// GetStats returns recovery statistics
func (r *RecoveryEngine) GetStats() RecoveryStats {
	return r.stats
}
