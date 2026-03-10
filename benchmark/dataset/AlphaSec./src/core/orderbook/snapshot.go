package orderbook

import (
	"compress/gzip"
	"encoding/gob"
	"fmt"
	"os"
	"path"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// OrderbookSnapshot represents complete DEX state at a specific block
type OrderbookSnapshot struct {
	BlockNumber uint64
	Timestamp   int64
	
	// Per-symbol engine state
	Symbols map[string]*SymbolSnapshot
	
	// Global order routing (orderID -> routing info)
	OrderRouting map[string]OrderRoutingInfo
	
	// Checksum for validation
	Checksum string
}

// SymbolSnapshot represents complete state of a single symbol engine
type SymbolSnapshot struct {
	Symbol string
	
	// Order queues (preserved in price-time priority order)
	BuyOrders  []*Order
	SellOrders []*Order
	
	// TPSL orders (not yet triggered)
	TPSLOrders []*TPSLOrder
	
	// User book mappings
	UserOrders map[string][]string // userID -> orderIDs
	
	// Market state
	LastPrice     *uint256.Int

	// Triggered orders (for reference)
	TriggeredOrders []string
}

// PersistenceSnapshotManager handles periodic snapshots of orderbook state for persistence
type PersistenceSnapshotManager struct {
	dataDir          string
	snapshotInterval uint64 // Blocks between snapshots
	
	// State
	lastSnapshot     uint64
	snapshotsCreated uint64
	mu               sync.Mutex
}

type snapshotRequest struct {
	blockNum   uint64
	dispatcher *Dispatcher
}

// NewPersistenceSnapshotManager creates a new persistence snapshot manager
func NewPersistenceSnapshotManager(dataDir string, snapshotInterval uint64) (*PersistenceSnapshotManager, error) {
	// Ensure directory exists
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create snapshot directory: %w", err)
	}

	sm := &PersistenceSnapshotManager{
		dataDir:          dataDir,
		snapshotInterval: snapshotInterval,
	}

	return sm, nil
}

// RequestSnapshot creates a snapshot synchronously at the given block
// TODO-Orderbook: Consider making this async with proper state isolation:
//   - Option 1: Deep copy entire dispatcher state upfront (high memory)
//   - Option 2: Use versioned/immutable data structures
//   - Option 3: Pause order processing briefly during critical sections
//   - Current approach: Synchronous to ensure consistency
func (sm *PersistenceSnapshotManager) RequestSnapshot(blockNum uint64, dispatcher *Dispatcher) {
	// Check if snapshot is needed
	sm.mu.Lock()
	if blockNum <= sm.lastSnapshot {
		sm.mu.Unlock()
		return // Already have snapshot for this or later block
	}
	sm.mu.Unlock()

	startTime := time.Now()
	log.Info("Creating snapshot synchronously", "block", blockNum)

	req := &snapshotRequest{
		blockNum:   blockNum,
		dispatcher: dispatcher,
	}

	// Create snapshot synchronously to ensure consistency
	if err := sm.createSnapshot(req); err != nil {
		log.Error("Failed to create snapshot", 
			"block", req.blockNum,
			"error", err)
	} else {
		sm.mu.Lock()
		sm.lastSnapshot = req.blockNum
		sm.snapshotsCreated++
		sm.mu.Unlock()
		
		log.Info("Snapshot created", 
			"block", req.blockNum,
			"duration", time.Since(startTime),
			"total", sm.snapshotsCreated)
	}
}

// createSnapshot creates a complete snapshot of the orderbook state
// NOTE: This runs synchronously to ensure consistency across all symbol engines
func (sm *PersistenceSnapshotManager) createSnapshot(req *snapshotRequest) error {
	snapshot := &OrderbookSnapshot{
		BlockNumber:  req.blockNum,
		Timestamp:    time.Now().Unix(),
		Symbols:      make(map[string]*SymbolSnapshot),
		OrderRouting: make(map[string]OrderRoutingInfo),
	}

	// Get engines and order routing while locked
	engines := req.dispatcher.GetEngines()
	routing := req.dispatcher.GetOrderRouting()

	// Copy global order routing (this already contains all order-symbol mappings)
	for _, route := range routing {
		snapshot.OrderRouting[route.OrderId] = OrderRoutingInfo{
			Symbol: route.Symbol,
		}
	}
	
	// Capture symbol snapshots in parallel (safe because snapshot is synchronous)
	// Since RequestSnapshot is now synchronous, engines won't be modified during capture
	type symbolResult struct {
		symbol string
		snap   *SymbolSnapshot
	}
	
	results := make(chan symbolResult, len(engines))
	var wg sync.WaitGroup
	
	// Determine number of workers
	numWorkers := len(engines)
	if numWorkers > 100 {
		numWorkers = 100 // Cap at 100 parallel workers
	}
	
	// Create work queue
	workQueue := make(chan struct{symbol string; engine *SymbolEngine}, len(engines))
	
	// Start workers
	for i := 0; i < numWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for work := range workQueue {
				// Each worker captures symbol snapshots
				symbolSnap := sm.captureSymbolSnapshot(work.symbol, work.engine)
				results <- symbolResult{
					symbol: work.symbol,
					snap:   symbolSnap,
				}
			}
		}()
	}
	
	// Queue work
	for symbol, engine := range engines {
		workQueue <- struct{symbol string; engine *SymbolEngine}{symbol, engine}
	}
	close(workQueue)
	
	// Close results channel when all workers are done
	go func() {
		wg.Wait()
		close(results)
	}()
	
	// Collect results
	for result := range results {
		snapshot.Symbols[result.symbol] = result.snap
	}
	
	// TODO-Orderbook: Future improvements for snapshot system:
	//   1. Make disk I/O async while keeping snapshot capture sync
	//   2. Implement incremental snapshots (delta-based)
	//   3. Consider copy-on-write data structures for zero-copy snapshots
	//   4. Add compression options (lz4 vs gzip tradeoff)

	// Calculate checksum
	snapshot.Checksum = sm.calculateChecksum(snapshot)

	// TODO-Orderbook: Make disk I/O async while keeping snapshot capture sync
	//   This would reduce the blocking time while maintaining consistency
	
	// Save to disk
	return sm.saveSnapshot(snapshot)
}

// captureSymbolSnapshot captures the state of a single symbol engine
func (sm *PersistenceSnapshotManager) captureSymbolSnapshot(symbol string, engine *SymbolEngine) *SymbolSnapshot {
	// Lock the engine for reading
	engine.stateMu.RLock()
	defer engine.stateMu.RUnlock()

	snapshot := &SymbolSnapshot{
		Symbol:          symbol,
		BuyOrders:       make([]*Order, 0),
		SellOrders:      make([]*Order, 0),
		TPSLOrders:      make([]*TPSLOrder, 0),
		UserOrders:      make(map[string][]string),
		TriggeredOrders: make([]string, 0),
	}

	// Deep copy buy queue using Order.Copy() method (maintaining heap order)
	snapshot.BuyOrders = make([]*Order, len(engine.buyQueue))
	for i, order := range engine.buyQueue {
		snapshot.BuyOrders[i] = order.Copy()
	}

	// Deep copy sell queue using Order.Copy() method (maintaining heap order)
	snapshot.SellOrders = make([]*Order, len(engine.sellQueue))
	for i, order := range engine.sellQueue {
		snapshot.SellOrders[i] = order.Copy()
	}

	// Deep copy conditional orders using TPSLOrder.Copy() method
	if engine.conditionalOrderManager != nil {
		conditionalOrders := engine.conditionalOrderManager.GetOrders()
		snapshot.TPSLOrders = make([]*TPSLOrder, len(conditionalOrders))
		for i, tpsl := range conditionalOrders {
			snapshot.TPSLOrders[i] = tpsl.Copy()
		}
	}

	// Copy user book
	if engine.userBook != nil {
		// UserBook stores orders by orderID, we need to group by userID
		userOrderMap := make(map[string][]string)
		for orderId, order := range engine.userBook.Orders {
			if order != nil {
				if _, exists := userOrderMap[order.UserID]; !exists {
					userOrderMap[order.UserID] = make([]string, 0)
				}
				userOrderMap[order.UserID] = append(userOrderMap[order.UserID], orderId)
			}
		}
		snapshot.UserOrders = userOrderMap
	}

	// Copy triggered orders
	snapshot.TriggeredOrders = make([]string, len(engine.triggered))
	for i, triggered := range engine.triggered {
		if triggered != nil && triggered.order != nil {
			snapshot.TriggeredOrders[i] = triggered.order.OrderID
		}
	}

	// Copy market state
	if engine.currentPrice != nil {
		snapshot.LastPrice = new(uint256.Int).Set(engine.currentPrice)
	}

	return snapshot
}

// calculateChecksum generates a checksum for validation
func (sm *PersistenceSnapshotManager) calculateChecksum(snapshot *OrderbookSnapshot) string {
	// Simple checksum based on order counts and totals
	var orderCount int
	var totalVolume uint256.Int

	for _, symbolSnap := range snapshot.Symbols {
		orderCount += len(symbolSnap.BuyOrders)
		orderCount += len(symbolSnap.SellOrders)
		orderCount += len(symbolSnap.TPSLOrders)
		
		for _, order := range symbolSnap.BuyOrders {
			if order.Quantity != nil {
				totalVolume.Add(&totalVolume, order.Quantity)
			}
		}
		for _, order := range symbolSnap.SellOrders {
			if order.Quantity != nil {
				totalVolume.Add(&totalVolume, order.Quantity)
			}
		}
	}

	return fmt.Sprintf("%d:%d:%s", snapshot.BlockNumber, orderCount, totalVolume.String())
}

// saveSnapshot writes snapshot to disk
func (sm *PersistenceSnapshotManager) saveSnapshot(snapshot *OrderbookSnapshot) error {
	filename := fmt.Sprintf("snapshot_%d.bin", snapshot.BlockNumber)
	filepath := path.Join(sm.dataDir, filename)
	tempPath := filepath + ".tmp"

	// Write to temp file first
	file, err := os.Create(tempPath)
	if err != nil {
		return fmt.Errorf("failed to create snapshot file: %w", err)
	}
	defer file.Close()

	// Use gzip compression
	gzWriter := gzip.NewWriter(file)
	defer gzWriter.Close()

	// Encode with gob
	encoder := gob.NewEncoder(gzWriter)
	if err := encoder.Encode(snapshot); err != nil {
		os.Remove(tempPath)
		return fmt.Errorf("failed to encode snapshot: %w", err)
	}

	// Ensure data is written
	if err := gzWriter.Close(); err != nil {
		os.Remove(tempPath)
		return fmt.Errorf("failed to finalize snapshot: %w", err)
	}
	
	if err := file.Sync(); err != nil {
		os.Remove(tempPath)
		return fmt.Errorf("failed to sync snapshot: %w", err)
	}

	// Atomic rename
	if err := os.Rename(tempPath, filepath); err != nil {
		os.Remove(tempPath)
		return fmt.Errorf("failed to move snapshot: %w", err)
	}

	// Clean up old snapshots (keep last 10)
	sm.pruneOldSnapshots()

	return nil
}

// LoadLatestSnapshot loads the most recent snapshot
func (sm *PersistenceSnapshotManager) LoadLatestSnapshot() (*OrderbookSnapshot, error) {
	files, err := os.ReadDir(sm.dataDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read snapshot directory: %w", err)
	}

	type snapshotFile struct {
		name     string
		blockNum uint64
	}

	// Find snapshot files and parse block numbers
	var snapshotFiles []snapshotFile
	for _, file := range files {
		if strings.HasPrefix(file.Name(), "snapshot_") && strings.HasSuffix(file.Name(), ".bin") {
			// Extract block number from filename
			var blockNum uint64
			_, err := fmt.Sscanf(file.Name(), "snapshot_%d.bin", &blockNum)
			if err != nil {
				log.Warn("Failed to parse snapshot filename", "file", file.Name(), "error", err)
				continue
			}
			
			snapshotFiles = append(snapshotFiles, snapshotFile{
				name:     file.Name(),
				blockNum: blockNum,
			})
		}
	}

	if len(snapshotFiles) == 0 {
		return nil, nil // No snapshots found
	}

	// Sort by block number to get latest (numeric sort)
	sort.Slice(snapshotFiles, func(i, j int) bool {
		return snapshotFiles[i].blockNum > snapshotFiles[j].blockNum  // Descending order
	})

	// Load the latest snapshot
	latestFile := snapshotFiles[0].name
	return sm.loadSnapshot(latestFile)
}

// loadSnapshot loads a specific snapshot file
func (sm *PersistenceSnapshotManager) loadSnapshot(filename string) (*OrderbookSnapshot, error) {
	filepath := path.Join(sm.dataDir, filename)
	
	file, err := os.Open(filepath)
	if err != nil {
		return nil, fmt.Errorf("failed to open snapshot file: %w", err)
	}
	defer file.Close()

	// Decompress
	gzReader, err := gzip.NewReader(file)
	if err != nil {
		return nil, fmt.Errorf("failed to create gzip reader: %w", err)
	}
	defer gzReader.Close()

	// Decode
	var snapshot OrderbookSnapshot
	decoder := gob.NewDecoder(gzReader)
	if err := decoder.Decode(&snapshot); err != nil {
		return nil, fmt.Errorf("failed to decode snapshot: %w", err)
	}

	// Validate checksum
	expectedChecksum := sm.calculateChecksum(&snapshot)
	if snapshot.Checksum != expectedChecksum {
		return nil, fmt.Errorf("snapshot checksum mismatch: expected %s, got %s", 
			expectedChecksum, snapshot.Checksum)
	}

	log.Info("Loaded snapshot", 
		"block", snapshot.BlockNumber,
		"symbols", len(snapshot.Symbols),
		"orders", len(snapshot.OrderRouting))

	return &snapshot, nil
}

// pruneOldSnapshots removes old snapshot files, keeping the most recent ones
func (sm *PersistenceSnapshotManager) pruneOldSnapshots() {
	files, err := os.ReadDir(sm.dataDir)
	if err != nil {
		log.Warn("Failed to read directory for pruning", "error", err)
		return
	}

	type snapshotFile struct {
		name     string
		blockNum uint64
	}

	var snapshotFiles []snapshotFile
	for _, file := range files {
		if strings.HasPrefix(file.Name(), "snapshot_") && strings.HasSuffix(file.Name(), ".bin") {
			// Extract block number from filename
			var blockNum uint64
			_, err := fmt.Sscanf(file.Name(), "snapshot_%d.bin", &blockNum)
			if err != nil {
				log.Warn("Failed to parse snapshot filename for pruning", "file", file.Name(), "error", err)
				continue
			}
			
			snapshotFiles = append(snapshotFiles, snapshotFile{
				name:     file.Name(),
				blockNum: blockNum,
			})
		}
	}

	// Keep last 10 snapshots
	if len(snapshotFiles) <= 10 {
		return
	}

	// Sort by block number (oldest first)
	sort.Slice(snapshotFiles, func(i, j int) bool {
		return snapshotFiles[i].blockNum < snapshotFiles[j].blockNum
	})

	// Remove old ones
	toRemove := len(snapshotFiles) - 10
	for i := 0; i < toRemove; i++ {
		filepath := path.Join(sm.dataDir, snapshotFiles[i].name)
		if err := os.Remove(filepath); err != nil {
			log.Warn("Failed to remove old snapshot", "file", snapshotFiles[i].name, "error", err)
		} else {
			log.Info("Pruned old snapshot", "file", snapshotFiles[i].name)
		}
	}
}

// Close shuts down the snapshot manager
func (sm *PersistenceSnapshotManager) Close() error {
	log.Info("Snapshot manager closed", 
		"snapshotsCreated", sm.snapshotsCreated,
		"lastSnapshot", sm.lastSnapshot)
	
	return nil
}

// ListSnapshots returns a list of all snapshot files
func (sm *PersistenceSnapshotManager) ListSnapshots() ([]string, error) {
	files, err := os.ReadDir(sm.dataDir)
	if err != nil {
		return nil, err
	}

	var snapshots []string
	for _, file := range files {
		if strings.HasPrefix(file.Name(), "snapshot_") && strings.HasSuffix(file.Name(), ".bin") {
			snapshots = append(snapshots, file.Name())
		}
	}

	return snapshots, nil
}