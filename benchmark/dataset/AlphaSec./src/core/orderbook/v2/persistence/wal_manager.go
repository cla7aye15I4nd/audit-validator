package persistence

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/metrics"
	"github.com/ethereum/go-ethereum/ethdb"
	"github.com/ethereum/go-ethereum/log"
)

var (
	// Key prefixes for different data types
	walPrefix  = []byte("wal:")
	metaPrefix = []byte("meta:")

	// Metadata keys
	lastWALSequenceKey = append(metaPrefix, []byte("last_wal_sequence")...)
	lastBlockNumberKey = append(metaPrefix, []byte("last_block_number")...)
)

// WALEntry represents a single entry in the write-ahead log
type WALEntry struct {
	Sequence     uint64     `json:"sequence"`
	Timestamp    time.Time  `json:"timestamp"`
	BlockNumber  uint64     `json:"block_number"`
	RequestType  string     `json:"request_type"`
	RequestData  []byte     `json:"request_data"`
	ResponseData []byte     `json:"response_data,omitempty"`
	Processed    bool       `json:"processed"`
	ProcessedAt  *time.Time `json:"processed_at,omitempty"`
	Error        string     `json:"error,omitempty"`
}

// WALManager manages the write-ahead log using KeyValueStore
type WALManager struct {
	db         ethdb.KeyValueStore
	serializer *RequestSerializer

	// Sequence management
	currentSequence uint64
	currentBlock    uint64

	// Synchronization
	mu sync.RWMutex
}

// NewWALManager creates a new WAL manager
func NewWALManager(db ethdb.KeyValueStore) *WALManager {
	manager := &WALManager{
		db:         db,
		serializer: NewRequestSerializer(),
	}

	// Load last sequence from database
	manager.loadMetadata()

	return manager
}

// Start starts the WAL manager (synchronous version - no background tasks)
func (w *WALManager) Start() {
	log.Debug("WAL manager started (synchronous mode)", "sequence", w.currentSequence, "block", w.currentBlock)
}

// Stop gracefully stops the WAL manager
func (w *WALManager) Stop() error {
	// Save final metadata
	if err := w.saveMetadata(); err != nil {
		return fmt.Errorf("failed to save metadata on stop: %w", err)
	}

	log.Debug("WAL manager stopped")
	return nil
}

// loadMetadata loads WAL metadata from the database
func (w *WALManager) loadMetadata() {
	// Load last sequence
	if data, err := w.db.Get(lastWALSequenceKey); err == nil && len(data) == 8 {
		w.currentSequence = binary.BigEndian.Uint64(data)
	}

	// Load last block
	if data, err := w.db.Get(lastBlockNumberKey); err == nil && len(data) == 8 {
		w.currentBlock = binary.BigEndian.Uint64(data)
	}
}

// saveMetadata saves WAL metadata to the database
func (w *WALManager) saveMetadata() error {
	batch := w.db.NewBatch()

	// Save sequence
	seqBytes := make([]byte, 8)
	binary.BigEndian.PutUint64(seqBytes, w.currentSequence)
	if err := batch.Put(lastWALSequenceKey, seqBytes); err != nil {
		return err
	}

	// Save block number
	blockBytes := make([]byte, 8)
	binary.BigEndian.PutUint64(blockBytes, w.currentBlock)
	if err := batch.Put(lastBlockNumberKey, blockBytes); err != nil {
		return err
	}

	return batch.Write()
}

// LogRequest logs a request to the WAL before processing
func (w *WALManager) LogRequest(req interfaces.Request, blockNumber uint64) (uint64, error) {
	w.mu.Lock()
	defer w.mu.Unlock()

	// Increment sequence (mutex already held)
	w.currentSequence++
	sequence := w.currentSequence

	// Update current block if needed
	if blockNumber > w.currentBlock {
		w.currentBlock = blockNumber
	}

	// Serialize request
	requestData, err := w.serializer.SerializeRequest(req, blockNumber)
	if err != nil {
		return 0, fmt.Errorf("failed to serialize request: %w", err)
	}

	// Determine request type
	requestType := w.getRequestType(req)

	// Create WAL entry
	entry := &WALEntry{
		Sequence:    sequence,
		Timestamp:   time.Now(),
		BlockNumber: blockNumber,
		RequestType: requestType,
		RequestData: requestData,
		Processed:   false,
	}

	// Write to database
	startTime := time.Now()
	if err := w.writeEntry(entry); err != nil {
		return 0, fmt.Errorf("failed to write WAL entry: %w", err)
	}
	metrics.PersistenceWALWriteTimer.UpdateSince(startTime)
	metrics.PersistenceWALEntriesCounter.Inc(1)

	return sequence, nil
}

// LogResponse updates a WAL entry with the response after processing
func (w *WALManager) LogResponse(blockNumber, sequence uint64, resp interfaces.Response) error {
	w.mu.Lock()
	defer w.mu.Unlock()

	// Read existing entry
	entry, err := w.readEntry(blockNumber, sequence)
	if err != nil {
		return fmt.Errorf("failed to read WAL entry %d: %w", sequence, err)
	}

	// Serialize response
	responseData, err := w.serializer.SerializeResponse(resp)
	if err != nil {
		return fmt.Errorf("failed to serialize response: %w", err)
	}

	// Update entry
	now := time.Now()
	entry.ResponseData = responseData
	entry.Processed = true
	entry.ProcessedAt = &now

	if resp.Error() != nil {
		entry.Error = resp.Error().Error()
	}

	// Write updated entry
	return w.writeEntry(entry)
}

// writeEntry writes a WAL entry to the database
func (w *WALManager) writeEntry(entry *WALEntry) error {
	// Create key: wal:{blockNum}:{sequence}
	key := w.makeWALKey(entry.BlockNumber, entry.Sequence)

	// Serialize entry
	value, err := json.Marshal(entry)
	if err != nil {
		return fmt.Errorf("failed to marshal WAL entry: %w", err)
	}

	// Write to database
	if err := w.db.Put(key, value); err != nil {
		return fmt.Errorf("failed to write to database: %w", err)
	}

	// Update WAL size metric
	// For now, just use the value size as an approximation
	metrics.PersistenceWALSizeGauge.Update(int64(len(value)))

	// Update metadata
	return w.saveMetadata()
}

// readEntry reads a WAL entry from the database using blockNumber for O(1) lookup
func (w *WALManager) readEntry(blockNumber, sequence uint64) (*WALEntry, error) {
	// Direct O(1) lookup using block number and sequence
	key := w.makeWALKey(blockNumber, sequence)

	value, err := w.db.Get(key)
	if err != nil {
		return nil, fmt.Errorf("WAL entry not found: block %d, sequence %d", blockNumber, sequence)
	}

	var entry WALEntry
	if err := json.Unmarshal(value, &entry); err != nil {
		return nil, fmt.Errorf("failed to unmarshal WAL entry: %w", err)
	}

	return &entry, nil
}

// readEntryBySequence reads a WAL entry when blockNumber is unknown (slower O(n) fallback)
func (w *WALManager) readEntryBySequence(sequence uint64) (*WALEntry, error) {
	iter := w.db.NewIterator(walPrefix, nil)
	defer iter.Release()

	for iter.Next() {
		var entry WALEntry
		if err := json.Unmarshal(iter.Value(), &entry); err != nil {
			continue
		}

		if entry.Sequence == sequence {
			return &entry, nil
		}
	}

	return nil, fmt.Errorf("WAL entry not found: %d", sequence)
}

// GetEntry retrieves a specific WAL entry by sequence number
func (w *WALManager) GetEntry(blockNumber, sequence uint64) (*WALEntry, error) {
	w.mu.RLock()
	defer w.mu.RUnlock()

	startTime := time.Now()
	defer func() {
		metrics.PersistenceWALReadTimer.UpdateSince(startTime)
	}()

	return w.readEntry(blockNumber, sequence)
}

// GetEntriesRange retrieves WAL entries in a sequence range
func (w *WALManager) GetEntriesRange(start, end uint64) ([]*WALEntry, error) {
	w.mu.RLock()
	defer w.mu.RUnlock()

	startTime := time.Now()
	defer func() {
		metrics.PersistenceWALReadTimer.UpdateSince(startTime)
	}()

	entries := make([]*WALEntry, 0)

	iter := w.db.NewIterator(walPrefix, nil)
	defer iter.Release()

	for iter.Next() {
		var entry WALEntry
		if err := json.Unmarshal(iter.Value(), &entry); err != nil {
			continue
		}

		if entry.Sequence >= start && entry.Sequence <= end {
			entries = append(entries, &entry)
		}
	}

	return entries, nil
}

// GetEntriesSince retrieves all WAL entries since a specific block number
func (w *WALManager) GetEntriesSince(blockNum uint64) ([]*WALEntry, error) {
	w.mu.RLock()
	defer w.mu.RUnlock()

	entries := make([]*WALEntry, 0)

	// Iterate through all WAL entries with the prefix
	iter := w.db.NewIterator(walPrefix, nil)
	defer iter.Release()

	for iter.Next() {
		var entry WALEntry
		if err := json.Unmarshal(iter.Value(), &entry); err != nil {
			continue
		}

		// Only include entries from the specified block number or later
		if entry.BlockNumber >= blockNum {
			entries = append(entries, &entry)
		}
	}

	return entries, nil
}

// Flush ensures all pending writes are persisted
func (w *WALManager) Flush() error {
	// In synchronous mode, all writes are immediate
	// This method is here for API compatibility
	return nil
}

// Compact removes old WAL entries before a specific block
func (w *WALManager) Compact(beforeBlock uint64) error {
	w.mu.Lock()
	defer w.mu.Unlock()

	log.Debug("Compacting WAL", "beforeBlock", beforeBlock)

	batch := w.db.NewBatch()
	count := 0

	iter := w.db.NewIterator(walPrefix, nil)
	defer iter.Release()

	for iter.Next() {
		var entry WALEntry
		if err := json.Unmarshal(iter.Value(), &entry); err != nil {
			continue
		}

		if entry.BlockNumber < beforeBlock {
			if err := batch.Delete(iter.Key()); err != nil {
				return fmt.Errorf("failed to delete entry: %w", err)
			}
			count++
		}
	}

	if err := batch.Write(); err != nil {
		return fmt.Errorf("failed to write batch: %w", err)
	}

	log.Debug("WAL compaction completed", "removed", count)
	return nil
}

// GetLastSequence returns the last WAL sequence number
func (w *WALManager) GetLastSequence() uint64 {
	return atomic.LoadUint64(&w.currentSequence)
}

// GetLastBlock returns the last block number seen
func (w *WALManager) GetLastBlock() uint64 {
	return atomic.LoadUint64(&w.currentBlock)
}

// makeWALKey creates a database key for a WAL entry
func (w *WALManager) makeWALKey(blockNum uint64, sequence uint64) []byte {
	key := make([]byte, len(walPrefix)+8+8)
	copy(key, walPrefix)

	offset := len(walPrefix)
	binary.BigEndian.PutUint64(key[offset:], blockNum)
	offset += 8
	binary.BigEndian.PutUint64(key[offset:], sequence)

	return key
}

// getRequestType determines the type of request
func (w *WALManager) getRequestType(req interfaces.Request) string {
	switch req.(type) {
	case *interfaces.OrderRequest:
		return "ORDER"
	case *interfaces.CancelRequest:
		return "CANCEL"
	case *interfaces.CancelAllRequest:
		return "CANCEL_ALL"
	case *interfaces.ModifyRequest:
		return "MODIFY"
	case *interfaces.StopOrderRequest:
		return "STOP_ORDER"
	default:
		return "UNKNOWN"
	}
}
