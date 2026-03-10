package orderbook

import (
	"container/heap"
	"fmt"
	"os"
	"path"
	"testing"

	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSnapshotManager_CreateAndLoad(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "snapshot_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create snapshot manager
	sm, err := NewPersistenceSnapshotManager(tmpDir, 100)
	require.NoError(t, err)
	require.NotNil(t, sm)

	// Create a test dispatcher with some orders
	dispatcher := createTestDispatcher(t)

	// Request snapshot (now synchronous)
	sm.RequestSnapshot(100, dispatcher)

	// Close manager
	sm.Close()

	// Load the snapshot back
	snapshot, err := sm.LoadLatestSnapshot()
	require.NoError(t, err)
	require.NotNil(t, snapshot)

	// Verify snapshot contents
	assert.Equal(t, uint64(100), snapshot.BlockNumber)
	assert.NotEmpty(t, snapshot.Symbols)
	assert.NotEmpty(t, snapshot.OrderRouting)
	assert.NotEmpty(t, snapshot.Checksum)
}

func TestSnapshotManager_DeepCopy(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "snapshot_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	sm, err := NewPersistenceSnapshotManager(tmpDir, 100)
	require.NoError(t, err)

	// Create dispatcher with orders
	dispatcher := createTestDispatcher(t)
	
	// Get the original order
	engine := dispatcher.engines["ETH/USDT"]
	require.NotNil(t, engine)
	originalOrder := engine.buyQueue[0]
	originalPrice := originalOrder.Price

	// Create snapshot (now synchronous)
	sm.RequestSnapshot(100, dispatcher)

	// Modify the original order
	originalOrder.Price = uint256.NewInt(999999)

	// Load snapshot
	sm.Close()
	snapshot, err := sm.LoadLatestSnapshot()
	require.NoError(t, err)

	// Verify snapshot has the original value (deep copy worked)
	ethSnapshot := snapshot.Symbols["ETH/USDT"]
	require.NotNil(t, ethSnapshot)
	require.NotEmpty(t, ethSnapshot.BuyOrders)
	
	snapshotOrder := ethSnapshot.BuyOrders[0]
	assert.Equal(t, originalPrice.Uint64(), snapshotOrder.Price.Uint64(), 
		"Snapshot should have original price, not modified price")
}

func TestSnapshotManager_MultipleSnapshots(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "snapshot_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	sm, err := NewPersistenceSnapshotManager(tmpDir, 100)
	require.NoError(t, err)

	dispatcher := createTestDispatcher(t)

	// Create multiple snapshots (now synchronous)
	blocks := []uint64{100, 200, 300}
	for _, blockNum := range blocks {
		sm.RequestSnapshot(blockNum, dispatcher)
	}

	sm.Close()

	// Verify all snapshot files exist
	for _, blockNum := range blocks {
		snapFile := path.Join(tmpDir, fmt.Sprintf("snapshot_%d.bin", blockNum))
		_, err := os.Stat(snapFile)
		assert.NoError(t, err, "Snapshot file for block %d should exist", blockNum)
	}

	// Load latest should return block 300
	snapshot, err := sm.LoadLatestSnapshot()
	require.NoError(t, err)
	assert.Equal(t, uint64(300), snapshot.BlockNumber)
}

func TestSnapshotManager_NumericSorting(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "snapshot_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	sm, err := NewPersistenceSnapshotManager(tmpDir, 100)
	require.NoError(t, err)

	dispatcher := createTestDispatcher(t)

	// Create snapshots with tricky numbering (now synchronous)
	blocks := []uint64{2, 10, 100, 20, 200}
	for _, blockNum := range blocks {
		sm.RequestSnapshot(blockNum, dispatcher)
	}

	sm.Close()

	// Latest should be 200, not "20" (lexicographic) or "2" 
	snapshot, err := sm.LoadLatestSnapshot()
	require.NoError(t, err)
	assert.Equal(t, uint64(200), snapshot.BlockNumber, 
		"Should select numerically latest snapshot, not lexicographically")
}

func TestSnapshotManager_Checksum(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "snapshot_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	sm, err := NewPersistenceSnapshotManager(tmpDir, 100)
	require.NoError(t, err)

	dispatcher := createTestDispatcher(t)

	// Create snapshot (now synchronous)
	sm.RequestSnapshot(100, dispatcher)
	sm.Close()

	// Load and verify checksum
	snapshot, err := sm.LoadLatestSnapshot()
	require.NoError(t, err)
	require.NotEmpty(t, snapshot.Checksum)

	// Save original checksum
	originalChecksum := snapshot.Checksum
	
	// Corrupt the snapshot data - modify quantity which is included in checksum
	snapshot.Symbols["ETH/USDT"].BuyOrders[0].Quantity = uint256.NewInt(99999)

	// Recalculate checksum - should be different
	newChecksum := sm.calculateChecksum(snapshot)
	assert.NotEqual(t, originalChecksum, newChecksum, 
		"Checksum should detect data modification")
}

func TestSnapshotManager_Pruning(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "snapshot_test_*")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	sm, err := NewPersistenceSnapshotManager(tmpDir, 100)
	require.NoError(t, err)

	dispatcher := createTestDispatcher(t)

	// Create more than 10 snapshots (pruning keeps 10)
	// Now synchronous, so all will complete immediately
	for i := uint64(100); i <= 1500; i += 100 {
		sm.RequestSnapshot(i, dispatcher)
	}

	sm.Close()

	// Count snapshot files before pruning
	files, _ := os.ReadDir(tmpDir)
	countBefore := len(files)
	// Check we have at least 10 (might be exactly 10 due to queue limit)
	require.GreaterOrEqual(t, countBefore, 10, "Should have created at least 10 snapshots")
	
	// Prune old snapshots (keeps last 10)
	sm.pruneOldSnapshots()

	// Count after pruning
	files, _ = os.ReadDir(tmpDir)
	countAfter := len(files)

	// If we had more than 10, should be reduced to 10
	// If we had exactly 10, should still be 10
	assert.LessOrEqual(t, countAfter, 10, "Should keep at most 10 snapshots after pruning")
	if countBefore > 10 {
		assert.Equal(t, 10, countAfter, "Should keep exactly 10 snapshots when had more")
		assert.Greater(t, countBefore, countAfter, "Should have deleted some snapshots")
	} else {
		assert.Equal(t, countBefore, countAfter, "Should keep all snapshots when had 10 or less")
	}

	// Verify we kept the latest ones
	snapshot, err := sm.LoadLatestSnapshot()
	require.NoError(t, err)
	assert.Equal(t, uint64(1500), snapshot.BlockNumber, "Latest snapshot should be preserved")
}

func TestSnapshotManager_OrderCopyMethod(t *testing.T) {
	// Test Order.Copy() method directly without needing snapshot manager

	// Create order with TPSL
	order := &Order{
		OrderID:  "order1",
		UserID:   "user1",
		Symbol:   "ETH/USDT",
		Side:     BUY,
		Price:    uint256.NewInt(1000),
		Quantity: uint256.NewInt(10),
		OrigQty:  uint256.NewInt(10),
		TPSL: &TPSLOrder{
			TPOrder: &StopOrder{
				Order: &Order{
					OrderID: "tp1",
				},
				StopPrice: uint256.NewInt(1100),
			},
			SLOrder: &StopOrder{
				Order: &Order{
					OrderID: "sl1",
				},
				StopPrice: uint256.NewInt(900),
			},
		},
	}

	// Test that Copy() method works correctly
	copied := order.Copy()
	
	// Verify deep copy
	assert.Equal(t, order.OrderID, copied.OrderID)
	assert.NotSame(t, order.Price, copied.Price)
	assert.Equal(t, order.Price.Uint64(), copied.Price.Uint64())
	
	// Verify TPSL deep copy
	assert.NotNil(t, copied.TPSL)
	assert.NotSame(t, order.TPSL, copied.TPSL)
	assert.NotSame(t, order.TPSL.TPOrder, copied.TPSL.TPOrder)
	assert.Equal(t, order.TPSL.TPOrder.StopPrice.Uint64(), 
		copied.TPSL.TPOrder.StopPrice.Uint64())
}

// Helper function to create test dispatcher with orders
func createTestDispatcher(t *testing.T) *Dispatcher {
	dispatcher := NewDispatcher()

	// Create symbol engine
	engine := NewSymbolEngine("ETH/USDT")
	
	// Add some buy orders
	buyOrders := []*Order{
		{
			OrderID:  "buy1",
			UserID:   "user1",
			Symbol:   "ETH/USDT",
			Side:     BUY,
			Price:    uint256.NewInt(1000),
			Quantity: uint256.NewInt(10),
			OrigQty:  uint256.NewInt(10),
		},
		{
			OrderID:  "buy2",
			UserID:   "user2",
			Symbol:   "ETH/USDT",
			Side:     BUY,
			Price:    uint256.NewInt(990),
			Quantity: uint256.NewInt(20),
			OrigQty:  uint256.NewInt(20),
		},
	}

	// Add sell orders
	sellOrders := []*Order{
		{
			OrderID:  "sell1",
			UserID:   "user3",
			Symbol:   "ETH/USDT",
			Side:     SELL,
			Price:    uint256.NewInt(1010),
			Quantity: uint256.NewInt(15),
			OrigQty:  uint256.NewInt(15),
		},
	}

	// Add orders to engine
	for _, order := range buyOrders {
		heap.Push(&engine.buyQueue, order)
		engine.userBook.AddOrder(order)
	}
	for _, order := range sellOrders {
		heap.Push(&engine.sellQueue, order)
		engine.userBook.AddOrder(order)
	}

	// Set market state
	engine.currentPrice = uint256.NewInt(1005)

	// Add engine to dispatcher
	dispatcher.engines["ETH/USDT"] = engine
	dispatcher.symbols["ETH/USDT"] = struct{}{}

	// Add order routing
	dispatcher.orderRouting["buy1"] = OrderRoutingInfo{
		Symbol: "ETH/USDT",
	}
	dispatcher.orderRouting["buy2"] = OrderRoutingInfo{
		Symbol: "ETH/USDT",
	}
	dispatcher.orderRouting["sell1"] = OrderRoutingInfo{
		Symbol: "ETH/USDT",
	}

	return dispatcher
}