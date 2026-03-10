package persistence

import (
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/ethdb/memorydb"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSnapshotManager_Basic(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create snapshot manager with interval of 100 blocks in sync mode
	sm := NewSnapshotManagerWithConfig(db, 100, false)
	require.NotNil(t, sm)
	
	// Start snapshot manager
	sm.Start()
	defer sm.Stop()
	
	// Test initial state
	assert.Equal(t, uint64(100), sm.snapshotInterval)
	assert.Equal(t, uint64(0), sm.lastSnapshotBlock)
}

func TestSnapshotManager_CreateSnapshot(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create and start snapshot manager in sync mode
	sm := NewSnapshotManagerWithConfig(db, 100, false)
	sm.Start()
	defer sm.Stop()
	
	// Create test dispatcher snapshot data
	order1 := &types.Order{
		OrderID:   "order-1",
		UserID:    "user-1",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		Price:     uint256.NewInt(3000),
		Quantity:  uint256.NewInt(10),
		Timestamp: time.Now().Unix(),
	}
	
	order2 := &types.Order{
		OrderID:   "order-2",
		UserID:    "user-2",
		Symbol:    "ETH/USDT",
		Side:      types.SELL,
		Price:     uint256.NewInt(3100),
		Quantity:  uint256.NewInt(5),
		Timestamp: time.Now().Unix(),
	}
	
	// Create engine snapshot with orders
	engineSnapshot := &types.EngineSnapshotData{
		Symbol:      "ETH/USDT",
		Orders:      []*types.Order{order1, order2},
		CurrentPrice: uint256.NewInt(3050),
		LastTradeTime: time.Now().Unix(),
		BlockNumber: 100,
	}
	
	dispatcherData := &types.DispatcherSnapshotData{
		Engines: map[types.Symbol]*types.EngineSnapshotData{
			types.Symbol("ETH/USDT"): engineSnapshot,
		},
		BlockNumber: 100,
	}
	
	// Create snapshot
	blockNum := uint64(100)
	stateRoot := common.HexToHash("0xabc123")
	walSequence := uint64(50)
	
	snapshot, err := sm.CreateSnapshot(dispatcherData, blockNum, stateRoot, walSequence)
	require.NoError(t, err)
	require.NotNil(t, snapshot)
	
	// Verify snapshot fields
	assert.Equal(t, blockNum, snapshot.BlockNumber)
	assert.Equal(t, stateRoot, snapshot.StateRoot)
	assert.Equal(t, walSequence, snapshot.LastWALSequence)
	assert.NotZero(t, snapshot.Timestamp)
	assert.Equal(t, 1, len(snapshot.OrderbookState.DispatcherSnapshot.Engines))
	
	// Verify last snapshot block was updated
	assert.Equal(t, blockNum, sm.GetLastSnapshotBlock())
}

func TestSnapshotManager_GetSnapshot(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create and start snapshot manager in sync mode
	sm := NewSnapshotManagerWithConfig(db, 100, false)
	sm.Start()
	defer sm.Stop()
	
	// Create test data
	order := &types.Order{
		OrderID:   "order-1",
		UserID:    "user-1",
		Symbol:    "BTC/USDT",
		Side:      types.BUY,
		Price:     uint256.NewInt(50000),
		Quantity:  uint256.NewInt(1),
		Timestamp: time.Now().Unix(),
	}
	
	engineSnapshot := &types.EngineSnapshotData{
		Symbol:      "BTC/USDT",
		Orders:      []*types.Order{order},
		CurrentPrice: uint256.NewInt(50000),
		LastTradeTime: time.Now().Unix(),
		BlockNumber: 200,
	}
	
	dispatcherData := &types.DispatcherSnapshotData{
		Engines: map[types.Symbol]*types.EngineSnapshotData{
			types.Symbol("BTC/USDT"): engineSnapshot,
		},
		BlockNumber: 200,
	}
	
	// Create snapshot
	blockNum := uint64(200)
	stateRoot := common.HexToHash("0xdef456")
	walSequence := uint64(100)
	
	createdSnapshot, err := sm.CreateSnapshot(dispatcherData, blockNum, stateRoot, walSequence)
	require.NoError(t, err)
	
	// Retrieve snapshot
	retrievedSnapshot, err := sm.LoadSnapshot(blockNum)
	require.NoError(t, err)
	require.NotNil(t, retrievedSnapshot)
	
	// Verify retrieved snapshot matches created one
	assert.Equal(t, createdSnapshot.BlockNumber, retrievedSnapshot.BlockNumber)
	assert.Equal(t, createdSnapshot.StateRoot, retrievedSnapshot.StateRoot)
	assert.Equal(t, createdSnapshot.LastWALSequence, retrievedSnapshot.LastWALSequence)
	// Don't compare timestamps directly due to marshaling of monotonic time
	assert.Equal(t, len(createdSnapshot.OrderbookState.DispatcherSnapshot.Engines), len(retrievedSnapshot.OrderbookState.DispatcherSnapshot.Engines))
}

func TestSnapshotManager_GetLatestSnapshot(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create and start snapshot manager in sync mode
	sm := NewSnapshotManagerWithConfig(db, 100, false)
	sm.Start()
	defer sm.Stop()
	
	// Create multiple snapshots
	for i := uint64(1); i <= 3; i++ {
		order := &types.Order{
			OrderID:   types.OrderID("order-" + string(rune('0'+i))),
			UserID:    "user-1",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			Price:     uint256.NewInt(3000 * i),
			Quantity:  uint256.NewInt(i),
			Timestamp: time.Now().Unix(),
		}
		
		engineSnapshot := &types.EngineSnapshotData{
			Symbol:      "ETH/USDT",
			Orders:      []*types.Order{order},
			CurrentPrice: uint256.NewInt(3000 * i),
			LastTradeTime: time.Now().Unix(),
			BlockNumber: i * 100,
		}
		
		dispatcherData := &types.DispatcherSnapshotData{
			Engines: map[types.Symbol]*types.EngineSnapshotData{
				types.Symbol("ETH/USDT"): engineSnapshot,
			},
			BlockNumber: i * 100,
		}
		
		blockNum := i * 100
		stateRoot := common.HexToHash("0x" + string(rune('a'+i-1)))
		walSequence := i * 50
		
		_, err := sm.CreateSnapshot(dispatcherData, blockNum, stateRoot, walSequence)
		require.NoError(t, err)
	}
	
	// Get latest snapshot
	latest, err := sm.GetLatestSnapshot()
	require.NoError(t, err)
	require.NotNil(t, latest)
	
	// Verify it's the last one created
	assert.Equal(t, uint64(300), latest.BlockNumber)
	assert.Equal(t, uint64(150), latest.LastWALSequence)
}

func TestSnapshotManager_ShouldSnapshot(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create snapshot manager with interval of 100 blocks in sync mode
	sm := NewSnapshotManagerWithConfig(db, 100, false)
	sm.Start()
	defer sm.Stop()
	
	// Test cases
	testCases := []struct {
		blockNum     uint64
		lastSnapshot uint64
		shouldSnap   bool
		description  string
	}{
		{100, 0, true, "First snapshot at any block when no previous snapshot"},
		{99, 0, true, "Block 99 should also trigger first snapshot"},
		{200, 100, true, "Next snapshot at block 200"},
		{150, 100, false, "Block 150 is between intervals"},
		{199, 100, false, "Block 199 is just before interval"},
		{300, 200, true, "Snapshot at block 300"},
	}
	
	for _, tc := range testCases {
		t.Run(tc.description, func(t *testing.T) {
			sm.lastSnapshotBlock = tc.lastSnapshot
			result := sm.ShouldSnapshot(tc.blockNum)
			assert.Equal(t, tc.shouldSnap, result, tc.description)
		})
	}
}

func TestSnapshotManager_GetNearestSnapshot(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create and start snapshot manager in sync mode
	sm := NewSnapshotManagerWithConfig(db, 100, false)
	sm.Start()
	defer sm.Stop()
	
	// Create snapshots at blocks 100, 200, 300
	for i := uint64(1); i <= 3; i++ {
		dispatcherData := &types.DispatcherSnapshotData{
			Engines: map[types.Symbol]*types.EngineSnapshotData{},
			BlockNumber: i * 100,
		}
		
		blockNum := i * 100
		_, err := sm.CreateSnapshot(dispatcherData, blockNum, common.Hash{}, i*10)
		require.NoError(t, err)
	}
	
	// Test GetNearestSnapshot
	testCases := []struct {
		targetBlock uint64
		expectBlock uint64
		expectError bool
		description string
	}{
		{50, 0, true, "Block 50 should error (no snapshot before it)"},
		{150, 100, false, "Block 150 should get snapshot at 100"},
		{250, 200, false, "Block 250 should get snapshot at 200"},
		{350, 300, false, "Block 350 should get snapshot at 300"},
	}
	
	for _, tc := range testCases {
		t.Run(tc.description, func(t *testing.T) {
			snapshot, err := sm.GetNearestSnapshot(tc.targetBlock)
			if tc.expectError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				require.NotNil(t, snapshot)
				assert.Equal(t, tc.expectBlock, snapshot.BlockNumber)
			}
		})
	}
}


func TestSnapshotManager_Restart(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// First session - create snapshots in sync mode
	sm1 := NewSnapshotManagerWithConfig(db, 100, false)
	sm1.Start()
	
	// Create snapshots
	for i := uint64(1); i <= 3; i++ {
		dispatcherData := &types.DispatcherSnapshotData{
			Engines: map[types.Symbol]*types.EngineSnapshotData{},
			BlockNumber: i * 100,
		}
		_, err := sm1.CreateSnapshot(dispatcherData, i*100, common.Hash{}, i*50)
		require.NoError(t, err)
	}
	
	lastBlock1 := sm1.GetLastSnapshotBlock()
	assert.Equal(t, uint64(300), lastBlock1)
	
	// Stop first manager
	err := sm1.Stop()
	require.NoError(t, err)
	
	// Second session - verify persistence
	sm2 := NewSnapshotManagerWithConfig(db, 100, false)
	sm2.Start()
	defer sm2.Stop()
	
	// Verify last snapshot block is restored
	lastBlock2 := sm2.GetLastSnapshotBlock()
	assert.Equal(t, lastBlock1, lastBlock2)
	
	// Verify all snapshots are accessible
	for i := uint64(1); i <= 3; i++ {
		snapshot, err := sm2.LoadSnapshot(i * 100)
		require.NoError(t, err)
		require.NotNil(t, snapshot)
		assert.Equal(t, i*100, snapshot.BlockNumber)
		assert.Equal(t, i*50, snapshot.LastWALSequence)
	}
	
	// Create new snapshot in second session
	dispatcherData := &types.DispatcherSnapshotData{
		Engines: map[types.Symbol]*types.EngineSnapshotData{},
		BlockNumber: 400,
	}
	_, err = sm2.CreateSnapshot(dispatcherData, 400, common.Hash{}, 200)
	require.NoError(t, err)
	
	// Verify new snapshot
	assert.Equal(t, uint64(400), sm2.GetLastSnapshotBlock())
}

func TestSnapshotManager_EmptyDispatcherData(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create and start snapshot manager in sync mode
	sm := NewSnapshotManagerWithConfig(db, 100, false)
	sm.Start()
	defer sm.Stop()
	
	// Create snapshot with empty dispatcher data
	emptyData := &types.DispatcherSnapshotData{
		Engines:     map[types.Symbol]*types.EngineSnapshotData{},
		BlockNumber: 100,
	}
	
	blockNum := uint64(100)
	stateRoot := common.HexToHash("0xabc")
	walSequence := uint64(10)
	
	snapshot, err := sm.CreateSnapshot(emptyData, blockNum, stateRoot, walSequence)
	require.NoError(t, err)
	require.NotNil(t, snapshot)
	
	// Verify snapshot was created with empty data
	assert.Equal(t, blockNum, snapshot.BlockNumber)
	assert.Empty(t, snapshot.OrderbookState.DispatcherSnapshot.Engines)
	
	// Retrieve and verify
	retrieved, err := sm.LoadSnapshot(blockNum)
	require.NoError(t, err)
	require.NotNil(t, retrieved)
	assert.Empty(t, retrieved.OrderbookState.DispatcherSnapshot.Engines)
}

// ============ ASYNC MODE TESTS ============

func TestSnapshotManager_CreateSnapshot_Async(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()

	// Create and start snapshot manager in ASYNC mode
	sm := NewSnapshotManagerWithConfig(db, 100, true) // async = true
	sm.Start()
	defer sm.Stop()

	// Create test dispatcher snapshot data (same as sync test)
	order1 := &types.Order{
		OrderID:   "order-1",
		UserID:    "user-1",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		Price:     uint256.NewInt(3000),
		Quantity:  uint256.NewInt(10),
		Timestamp: time.Now().Unix(),
	}

	order2 := &types.Order{
		OrderID:   "order-2",
		UserID:    "user-2",
		Symbol:    "ETH/USDT",
		Side:      types.SELL,
		Price:     uint256.NewInt(3100),
		Quantity:  uint256.NewInt(5),
		Timestamp: time.Now().Unix(),
	}

	// Create engine snapshot with orders
	engineSnapshot := &types.EngineSnapshotData{
		Symbol:      "ETH/USDT",
		Orders:      []*types.Order{order1, order2},
		CurrentPrice: uint256.NewInt(3050),
		LastTradeTime: time.Now().Unix(),
		BlockNumber: 100,
	}

	dispatcherData := &types.DispatcherSnapshotData{
		Engines: map[types.Symbol]*types.EngineSnapshotData{
			types.Symbol("ETH/USDT"): engineSnapshot,
		},
		BlockNumber: 100,
	}

	// Create snapshot
	blockNum := uint64(100)
	stateRoot := common.HexToHash("0xabc123")
	walSequence := uint64(50)

	snapshot, err := sm.CreateSnapshot(dispatcherData, blockNum, stateRoot, walSequence)
	require.NoError(t, err)
	require.NotNil(t, snapshot)

	// Verify immediate return values
	assert.Equal(t, blockNum, snapshot.BlockNumber)
	assert.Equal(t, stateRoot, snapshot.StateRoot)
	assert.Equal(t, walSequence, snapshot.LastWALSequence)

	// Wait for async write to complete
	time.Sleep(100 * time.Millisecond)

	// Verify snapshot was persisted
	loaded, err := sm.LoadSnapshot(blockNum)
	require.NoError(t, err)
	require.NotNil(t, loaded)

	// Verify loaded snapshot matches original
	assert.Equal(t, blockNum, loaded.BlockNumber)
	assert.Equal(t, stateRoot, loaded.StateRoot)
	assert.Equal(t, walSequence, loaded.LastWALSequence)
	assert.Equal(t, 1, len(loaded.OrderbookState.DispatcherSnapshot.Engines))

	// Verify last snapshot block was updated
	assert.Equal(t, blockNum, sm.GetLastSnapshotBlock())
}

func TestSnapshotManager_MultipleSnapshots_Async(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()

	// Create and start snapshot manager in ASYNC mode
	sm := NewSnapshotManagerWithConfig(db, 100, true) // async = true
	sm.Start()
	defer sm.Stop()

	// Create multiple snapshots rapidly
	for i := uint64(1); i <= 3; i++ {
		order := &types.Order{
			OrderID:   types.OrderID("order-" + string(rune('0'+i))),
			UserID:    "user-1",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			Price:     uint256.NewInt(3000 * i),
			Quantity:  uint256.NewInt(i),
			Timestamp: time.Now().Unix(),
		}

		engineSnapshot := &types.EngineSnapshotData{
			Symbol:      "ETH/USDT",
			Orders:      []*types.Order{order},
			CurrentPrice: uint256.NewInt(3000 * i),
			LastTradeTime: time.Now().Unix(),
			BlockNumber: i * 100,
		}

		dispatcherData := &types.DispatcherSnapshotData{
			Engines: map[types.Symbol]*types.EngineSnapshotData{
				types.Symbol("ETH/USDT"): engineSnapshot,
			},
			BlockNumber: i * 100,
		}

		blockNum := i * 100
		stateRoot := common.HexToHash("0x" + string(rune('a'+i-1)))
		walSequence := i * 50

		_, err := sm.CreateSnapshot(dispatcherData, blockNum, stateRoot, walSequence)
		require.NoError(t, err)

		// Small delay between snapshots to avoid concurrent snapshot error
		time.Sleep(50 * time.Millisecond)
	}

	// Wait for all async operations to complete
	time.Sleep(200 * time.Millisecond)

	// Verify all snapshots were saved
	for i := uint64(1); i <= 3; i++ {
		snapshot, err := sm.LoadSnapshot(i * 100)
		require.NoError(t, err, "Failed to load snapshot for block %d", i*100)
		assert.Equal(t, i*100, snapshot.BlockNumber)
		assert.Equal(t, i*50, snapshot.LastWALSequence)
	}

	// Verify last snapshot block
	assert.Equal(t, uint64(300), sm.GetLastSnapshotBlock())
}

func TestSnapshotManager_AsyncRestart(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()

	// First session - create snapshots in ASYNC mode
	sm1 := NewSnapshotManagerWithConfig(db, 100, true) // async = true
	sm1.Start()

	// Create snapshots
	for i := uint64(1); i <= 3; i++ {
		dispatcherData := &types.DispatcherSnapshotData{
			Engines: map[types.Symbol]*types.EngineSnapshotData{},
			BlockNumber: i * 100,
		}
		_, err := sm1.CreateSnapshot(dispatcherData, i*100, common.Hash{}, i*50)
		require.NoError(t, err)
		time.Sleep(30 * time.Millisecond) // Avoid concurrent snapshot
	}

	// Wait for async operations
	time.Sleep(200 * time.Millisecond)

	lastBlock1 := sm1.GetLastSnapshotBlock()
	assert.Equal(t, uint64(300), lastBlock1)

	// Stop first manager (should wait for async operations)
	err := sm1.Stop()
	require.NoError(t, err)

	// Second session - verify persistence (can be sync or async)
	sm2 := NewSnapshotManagerWithConfig(db, 100, false) // sync mode for verification
	sm2.Start()
	defer sm2.Stop()

	// Verify last snapshot block is restored
	lastBlock2 := sm2.GetLastSnapshotBlock()
	assert.Equal(t, lastBlock1, lastBlock2)

	// Verify all snapshots are accessible
	for i := uint64(1); i <= 3; i++ {
		snapshot, err := sm2.LoadSnapshot(i * 100)
		require.NoError(t, err)
		require.NotNil(t, snapshot)
		assert.Equal(t, i*100, snapshot.BlockNumber)
		assert.Equal(t, i*50, snapshot.LastWALSequence)
	}
}

func TestSnapshotManager_ConcurrentSnapshotPrevention(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()

	// Create snapshot manager in ASYNC mode
	sm := NewSnapshotManagerWithConfig(db, 100, true) // async = true
	sm.Start()
	defer sm.Stop()

	// Create dispatcher data
	dispatcherData := &types.DispatcherSnapshotData{
		Engines:     map[types.Symbol]*types.EngineSnapshotData{},
		BlockNumber: 100,
	}

	// Try to create two snapshots immediately (second should fail)
	_, err1 := sm.CreateSnapshot(dispatcherData, 100, common.Hash{}, 100)
	require.NoError(t, err1, "First snapshot should succeed")

	// Immediate second attempt should fail
	_, err2 := sm.CreateSnapshot(dispatcherData, 101, common.Hash{}, 101)
	assert.Error(t, err2, "Second snapshot should fail")
	assert.Contains(t, err2.Error(), "snapshot already in progress")

	// Wait for first snapshot to complete
	time.Sleep(100 * time.Millisecond)

	// Now should be able to create another
	_, err3 := sm.CreateSnapshot(dispatcherData, 102, common.Hash{}, 102)
	require.NoError(t, err3, "Third snapshot should succeed after first completes")
}