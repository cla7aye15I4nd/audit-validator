package orderbook

import "sync"

// SnapshotManager manages order book snapshots for a symbol
type SnapshotManager struct {
	symbol        string
	snapshotBlock uint64
	snapshot      *Aggregated
	snapshotLock  sync.RWMutex
}

// NewSnapshotManager creates a new SnapshotManager instance
func NewSnapshotManager(symbol string) *SnapshotManager {
	return &SnapshotManager{
		symbol:        symbol,
		snapshotBlock: 0,
		snapshot:      &Aggregated{},
	}
}

// MakeSnapshot creates a new snapshot if the block number is newer
func (m *SnapshotManager) MakeSnapshot(block uint64, bids, asks [][]string) {
	m.snapshotLock.Lock()
	defer m.snapshotLock.Unlock()

	if block > m.snapshotBlock {
		m.snapshotBlock = block
		m.snapshot = &Aggregated{
			BlockNumber: block,
			Symbol:      m.symbol,
			Bids:        bids,
			Asks:        asks,
		}
	}
}

// GetSnapshot returns the current snapshot
func (m *SnapshotManager) GetSnapshot() *Aggregated {
	m.snapshotLock.RLock()
	defer m.snapshotLock.RUnlock()

	return m.snapshot
}

// GetSnapshotBlock returns the current snapshot block number
func (m *SnapshotManager) GetSnapshotBlock() uint64 {
	m.snapshotLock.RLock()
	defer m.snapshotLock.RUnlock()

	return m.snapshotBlock
}

// CreateLevel3Snapshot creates a snapshot from Level3 data
func (m *SnapshotManager) CreateLevel3Snapshot(buyQueue BuyQueue, sellQueue SellQueue) *Aggregated {
	level2 := buildLevel2BookFromQueues(buyQueue, sellQueue)
	return &Aggregated{
		BlockNumber: m.snapshotBlock,
		Symbol:      m.symbol,
		Bids:        toSortedLevel2List(level2.Bids, true),
		Asks:        toSortedLevel2List(level2.Asks, false),
	}
}