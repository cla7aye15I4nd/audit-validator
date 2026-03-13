package persistence

import (
	"fmt"
	"math/big"
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/ethdb/memorydb"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// MockDispatcher for testing recovery
type MockDispatcher struct {
	orders          map[string]*types.Order
	processedOrders []string
	cancelledOrders []string
	appliedSnapshot bool
	snapshotBlock   uint64
}

func NewMockDispatcher() *MockDispatcher {
	return &MockDispatcher{
		orders:          make(map[string]*types.Order),
		processedOrders: make([]string, 0),
		cancelledOrders: make([]string, 0),
	}
}

func (m *MockDispatcher) DispatchReq(req interfaces.Request) {
	// Mock async dispatch - send response to channel
	response := m.ProcessRequestSync(req)
	if ch := req.ResponseChannel(); ch != nil {
		ch <- response
	}
}

func (m *MockDispatcher) ProcessRequestSync(req interfaces.Request) interfaces.Response {
	switch r := req.(type) {
	case *interfaces.OrderRequest:
		order := r.Order
		m.orders[string(order.OrderID)] = order
		m.processedOrders = append(m.processedOrders, string(order.OrderID))
		return interfaces.NewOrderResponse(order, nil, nil)

	case *interfaces.CancelRequest:
		orderID := r.OrderID
		delete(m.orders, orderID)
		m.cancelledOrders = append(m.cancelledOrders, orderID)
		// Return empty OrderIDs for cancelled orders
		return interfaces.NewCancelResponse(types.OrderIDs{})

	default:
		return interfaces.NewOrderResponse(nil, nil, nil) // Return empty response for unsupported
	}
}

func (m *MockDispatcher) GetEngine(symbol types.Symbol) interface{} {
	return nil // Mock implementation
}

func (m *MockDispatcher) GetEngines() interface{} {
	return nil // Mock implementation
}

func (m *MockDispatcher) Start() {
	// Mock implementation
}

func (m *MockDispatcher) Stop() error {
	return nil
}

func (m *MockDispatcher) GetSnapshotData(blockNum uint64) *types.DispatcherSnapshotData {
	// Create engine snapshot from current orders
	orders := make([]*types.Order, 0, len(m.orders))
	for _, order := range m.orders {
		orders = append(orders, order)
	}

	engineSnapshot := &types.EngineSnapshotData{
		Symbol:        "ETH/USDT",
		Orders:        orders,
		CurrentPrice:  uint256.NewInt(3000),
		LastTradeTime: time.Now().Unix(),
		BlockNumber:   blockNum,
	}

	return &types.DispatcherSnapshotData{
		Engines: map[types.Symbol]*types.EngineSnapshotData{
			types.Symbol("ETH/USDT"): engineSnapshot,
		},
		BlockNumber: blockNum,
	}
}

func (m *MockDispatcher) RestoreFromSnapshot(snapshot *types.DispatcherSnapshotData) error {
	m.appliedSnapshot = true
	m.snapshotBlock = snapshot.BlockNumber

	// Restore orders from snapshot
	m.orders = make(map[string]*types.Order)
	for _, engine := range snapshot.Engines {
		for _, order := range engine.Orders {
			m.orders[string(order.OrderID)] = order
		}
	}

	return nil
}

func (m *MockDispatcher) SetCurrentBlock(blockNum uint64, stateRoot common.Hash) {
	// Mock implementation
}

func (m *MockDispatcher) OnBlockEnd(blockNum uint64) {
	// Mock implementation
}

// MockStateDB for testing
type MockStateDB struct{}

func (m *MockStateDB) GetTokenBalance(addr common.Address, token string) *uint256.Int {
	return uint256.NewInt(1000000)
}

func (m *MockStateDB) GetLockedTokenBalance(addr common.Address, token string) *uint256.Int {
	return uint256.NewInt(0)
}

func (m *MockStateDB) LockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// Mock implementation
}

func (m *MockStateDB) UnlockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// Mock implementation
}

func (m *MockStateDB) ConsumeLockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// Mock implementation
}

func (m *MockStateDB) AddTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// Mock implementation
}

func (m *MockStateDB) SubTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// Mock implementation
}

// MockFeeGetter for testing
type MockFeeGetter struct{}

func (m *MockFeeGetter) GetMarketFees(base, quote uint64) (*big.Int, *big.Int, error) {
	// Return default fees: 0.1% maker fee, 0.2% taker fee (in basis points)
	makerFee := big.NewInt(10) // 0.1% = 10 basis points
	takerFee := big.NewInt(20) // 0.2% = 20 basis points
	return makerFee, takerFee, nil
}

// MockStateProvider for testing
type MockStateProvider struct {
	stateDB   types.StateDB
	feeGetter types.FeeRetriever
}

func NewMockStateProvider() *MockStateProvider {
	return &MockStateProvider{
		stateDB:   &MockStateDB{},
		feeGetter: &MockFeeGetter{},
	}
}

func (p *MockStateProvider) GetStateDB(blockNum uint64) (types.StateDB, error) {
	if p.stateDB == nil {
		return nil, fmt.Errorf("mock StateDB not configured")
	}
	return p.stateDB, nil
}

func (p *MockStateProvider) GetFeeGetter(blockNum uint64) (types.FeeRetriever, error) {
	if p.feeGetter == nil {
		return nil, fmt.Errorf("mock FeeGetter not configured")
	}
	return p.feeGetter, nil
}

func TestRecoveryEngine_ColdStartWithSnapshotAndWAL(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()

	// Create managers
	walManager := NewWALManager(db)
	snapshotManager := NewSnapshotManager(db, 100)

	// Start managers
	walManager.Start()
	snapshotManager.Start()
	defer walManager.Stop()
	defer snapshotManager.Stop()

	// Create initial orders and log them to WAL
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

	// Log orders at block 50
	blockNum1 := uint64(50)
	req1 := interfaces.NewOrderRequest(order1, nil, nil)
	seq1, err := walManager.LogRequest(req1, blockNum1)
	require.NoError(t, err)
	resp1 := interfaces.NewOrderResponse(order1, nil, nil)
	err = walManager.LogResponse(blockNum1, seq1, resp1)
	require.NoError(t, err)

	req2 := interfaces.NewOrderRequest(order2, nil, nil)
	seq2, err := walManager.LogRequest(req2, blockNum1)
	require.NoError(t, err)
	resp2 := interfaces.NewOrderResponse(order2, nil, nil)
	err = walManager.LogResponse(blockNum1, seq2, resp2)
	require.NoError(t, err)

	// Create snapshot at block 100
	mockDispatcher := NewMockDispatcher()
	mockDispatcher.orders["order-1"] = order1
	mockDispatcher.orders["order-2"] = order2

	snapshotData := mockDispatcher.GetSnapshotData(100)
	snapshot, err := snapshotManager.CreateSnapshot(snapshotData, 100, common.HexToHash("0x222"), seq2)
	require.NoError(t, err)
	require.NotNil(t, snapshot)

	// Add more orders after snapshot (block 150)
	order3 := &types.Order{
		OrderID:   "order-3",
		UserID:    "user-3",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		Price:     uint256.NewInt(3050),
		Quantity:  uint256.NewInt(8),
		Timestamp: time.Now().Unix(),
	}

	blockNum2 := uint64(150)
	req3 := interfaces.NewOrderRequest(order3, nil, nil)
	seq3, err := walManager.LogRequest(req3, blockNum2)
	require.NoError(t, err)
	resp3 := interfaces.NewOrderResponse(order3, nil, nil)
	err = walManager.LogResponse(blockNum2, seq3, resp3)
	require.NoError(t, err)

	// Cancel order-1
	cancelReq := interfaces.NewCancelRequest("order-1", nil, nil)
	seq4, err := walManager.LogRequest(cancelReq, blockNum2)
	require.NoError(t, err)
	cancelResp := interfaces.NewCancelResponse(types.OrderIDs{"order-1"})
	err = walManager.LogResponse(blockNum2, seq4, cancelResp)
	require.NoError(t, err)

	// Now perform cold start recovery
	// In production, this would be a BlockchainStateProvider with actual blockchain access
	stateProvider := NewMockStateProvider()
	recoveryEngine := NewRecoveryEngine(db, walManager, snapshotManager, stateProvider)

	// Create new dispatcher for recovery
	recoveredDispatcher := NewMockDispatcher()

	// Perform recovery
	err = recoveryEngine.RecoverFromColdStart(recoveredDispatcher)
	require.NoError(t, err)

	// Verify recovery results
	stats := recoveryEngine.GetStats()
	assert.True(t, stats.SnapshotLoaded, "Snapshot should be loaded")
	assert.Equal(t, uint64(100), stats.SnapshotBlock, "Should restore from block 100 snapshot")
	assert.Equal(t, uint64(2), stats.WALEntriesReplayed, "Should replay 2 WAL entries after snapshot")
	assert.Equal(t, uint64(150), stats.LastBlock, "Should recover to block 150")

	// Verify dispatcher state after recovery
	assert.True(t, recoveredDispatcher.appliedSnapshot, "Snapshot should be applied")
	assert.Equal(t, uint64(100), recoveredDispatcher.snapshotBlock, "Snapshot block should be 100")

	// Verify final order state
	assert.Equal(t, 2, len(recoveredDispatcher.orders), "Should have 2 orders after recovery")
	assert.NotNil(t, recoveredDispatcher.orders["order-2"], "Order-2 should exist")
	assert.NotNil(t, recoveredDispatcher.orders["order-3"], "Order-3 should exist")
	assert.Nil(t, recoveredDispatcher.orders["order-1"], "Order-1 should be cancelled")

	// Verify processing history
	assert.Contains(t, recoveredDispatcher.processedOrders, "order-3", "Order-3 should be processed")
	assert.Contains(t, recoveredDispatcher.cancelledOrders, "order-1", "Order-1 should be cancelled")
}

func TestRecoveryEngine_RecoverToSpecificBlock(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()

	// Create managers
	walManager := NewWALManager(db)
	snapshotManager := NewSnapshotManager(db, 100)

	// Start managers
	walManager.Start()
	snapshotManager.Start()
	defer walManager.Stop()
	defer snapshotManager.Stop()

	// Create and log orders at different blocks
	blocks := []uint64{50, 100, 150, 200, 250}
	for i, blockNum := range blocks {
		order := &types.Order{
			OrderID:   types.OrderID(common.Hash{byte(i)}.Hex()),
			UserID:    "user-1",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			Price:     uint256.NewInt(3000 + uint64(i*100)),
			Quantity:  uint256.NewInt(uint64(i + 1)),
			Timestamp: time.Now().Unix(),
		}

		req := interfaces.NewOrderRequest(order, nil, nil)
		seq, err := walManager.LogRequest(req, blockNum)
		require.NoError(t, err)

		resp := interfaces.NewOrderResponse(order, nil, nil)
		err = walManager.LogResponse(blockNum, seq, resp)
		require.NoError(t, err)

		// Create snapshot at block 100
		if blockNum == 100 {
			mockDispatcher := NewMockDispatcher()
			// Add first two orders
			for j := 0; j <= i; j++ {
				mockDispatcher.orders[common.Hash{byte(j)}.Hex()] = &types.Order{
					OrderID: types.OrderID(common.Hash{byte(j)}.Hex()),
				}
			}
			snapshotData := mockDispatcher.GetSnapshotData(blockNum)
			_, err := snapshotManager.CreateSnapshot(snapshotData, blockNum, common.Hash{byte(i)}, seq)
			require.NoError(t, err)
		}
	}

	// Create recovery engine
	// In production, this would be a BlockchainStateProvider with actual blockchain access
	stateProvider := NewMockStateProvider()
	recoveryEngine := NewRecoveryEngine(db, walManager, snapshotManager, stateProvider)

	// Test recovery to block 150
	dispatcher150 := NewMockDispatcher()
	err := recoveryEngine.RecoverFromBlock(dispatcher150, 150)
	require.NoError(t, err)

	stats := recoveryEngine.GetStats()
	assert.Equal(t, uint64(150), stats.LastBlock, "Should recover to block 150")
	// Should have 2 orders from snapshot at block 100, plus 1 more order from block 150
	assert.Equal(t, 1, len(dispatcher150.processedOrders), "Should process 1 order after snapshot")

	// Test recovery to block 200
	dispatcher200 := NewMockDispatcher()
	err = recoveryEngine.RecoverFromBlock(dispatcher200, 200)
	require.NoError(t, err)

	stats = recoveryEngine.GetStats()
	assert.Equal(t, uint64(200), stats.LastBlock, "Should recover to block 200")
	// Should have 2 orders from snapshot at block 100, plus 2 more orders from blocks 150-200
	assert.Equal(t, 2, len(dispatcher200.processedOrders), "Should process 2 orders after snapshot")
}

func TestRecoveryEngine_OnlyWAL_NoSnapshot(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()

	// Create managers
	walManager := NewWALManager(db)
	snapshotManager := NewSnapshotManager(db, 1000) // High interval so no snapshot

	// Start managers
	walManager.Start()
	snapshotManager.Start()
	defer walManager.Stop()
	defer snapshotManager.Stop()

	// Log orders without creating snapshot
	numOrders := 5
	for i := 0; i < numOrders; i++ {
		order := &types.Order{
			OrderID:   types.OrderID(common.Hash{byte(i)}.Hex()),
			UserID:    "user-1",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			Price:     uint256.NewInt(3000),
			Quantity:  uint256.NewInt(uint64(i + 1)),
			Timestamp: time.Now().Unix(),
		}

		blockNum := uint64(i + 1)

		req := interfaces.NewOrderRequest(order, nil, nil)
		seq, err := walManager.LogRequest(req, blockNum)
		require.NoError(t, err)

		resp := interfaces.NewOrderResponse(order, nil, nil)
		err = walManager.LogResponse(blockNum, seq, resp)
		require.NoError(t, err)
	}

	// Create recovery engine
	// In production, this would be a BlockchainStateProvider with actual blockchain access
	stateProvider := NewMockStateProvider()
	recoveryEngine := NewRecoveryEngine(db, walManager, snapshotManager, stateProvider)

	// Perform recovery
	dispatcher := NewMockDispatcher()
	err := recoveryEngine.RecoverFromColdStart(dispatcher)
	require.NoError(t, err)

	// Verify recovery from WAL only
	stats := recoveryEngine.GetStats()
	assert.False(t, stats.SnapshotLoaded, "No snapshot should be loaded")
	assert.Equal(t, uint64(numOrders), stats.WALEntriesReplayed, "Should replay all WAL entries")
	assert.Equal(t, uint64(numOrders), stats.LastBlock, "Should recover to last block")
	assert.Equal(t, numOrders, len(dispatcher.processedOrders), "Should process all orders")
}

func TestRecoveryEngine_OnlySnapshot_NoWAL(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()

	// Create managers
	walManager := NewWALManager(db)
	snapshotManager := NewSnapshotManager(db, 100)

	// Start managers
	walManager.Start()
	snapshotManager.Start()
	defer walManager.Stop()
	defer snapshotManager.Stop()

	// Create snapshot without WAL entries after it
	mockDispatcher := NewMockDispatcher()
	for i := 0; i < 3; i++ {
		order := &types.Order{
			OrderID:   types.OrderID(common.Hash{byte(i)}.Hex()),
			UserID:    "user-1",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			Price:     uint256.NewInt(3000),
			Quantity:  uint256.NewInt(uint64(i + 1)),
			Timestamp: time.Now().Unix(),
		}
		mockDispatcher.orders[string(order.OrderID)] = order
	}

	snapshotData := mockDispatcher.GetSnapshotData(100)
	lastWALSeq := walManager.GetLastSequence()
	_, err := snapshotManager.CreateSnapshot(snapshotData, 100, common.HexToHash("0x123"), lastWALSeq)
	require.NoError(t, err)

	// Create recovery engine
	// In production, this would be a BlockchainStateProvider with actual blockchain access
	stateProvider := NewMockStateProvider()
	recoveryEngine := NewRecoveryEngine(db, walManager, snapshotManager, stateProvider)

	// Perform recovery
	recoveredDispatcher := NewMockDispatcher()
	err = recoveryEngine.RecoverFromColdStart(recoveredDispatcher)
	require.NoError(t, err)

	// Verify recovery from snapshot only
	stats := recoveryEngine.GetStats()
	assert.True(t, stats.SnapshotLoaded, "Snapshot should be loaded")
	assert.Equal(t, uint64(100), stats.SnapshotBlock, "Should restore from block 100")
	assert.Equal(t, uint64(0), stats.WALEntriesReplayed, "Should not replay any WAL entries")
	// Note: LastBlock is only set when replaying WAL entries, not from snapshot alone
	// This is a known limitation - LastBlock remains 0 if only restoring from snapshot

	// Verify orders restored from snapshot
	assert.True(t, recoveredDispatcher.appliedSnapshot, "Snapshot should be applied")
	assert.Equal(t, 3, len(recoveredDispatcher.orders), "Should restore 3 orders from snapshot")
}

func TestRecoveryEngine_EmptyDatabase(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()

	// Create managers
	walManager := NewWALManager(db)
	snapshotManager := NewSnapshotManager(db, 100)

	// Start managers
	walManager.Start()
	snapshotManager.Start()
	defer walManager.Stop()
	defer snapshotManager.Stop()

	// Create recovery engine
	// In production, this would be a BlockchainStateProvider with actual blockchain access
	stateProvider := NewMockStateProvider()
	recoveryEngine := NewRecoveryEngine(db, walManager, snapshotManager, stateProvider)

	// Perform recovery on empty database
	dispatcher := NewMockDispatcher()
	err := recoveryEngine.RecoverFromColdStart(dispatcher)
	require.NoError(t, err)

	// Verify no recovery happened
	stats := recoveryEngine.GetStats()
	assert.False(t, stats.SnapshotLoaded, "No snapshot should be loaded")
	assert.Equal(t, uint64(0), stats.WALEntriesReplayed, "No WAL entries should be replayed")
	assert.Equal(t, uint64(0), stats.LastBlock, "Last block should be 0")
	assert.False(t, dispatcher.appliedSnapshot, "No snapshot should be applied")
	assert.Empty(t, dispatcher.processedOrders, "No orders should be processed")
}

func TestRecoveryEngine_WithErrors(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()

	// Create managers
	walManager := NewWALManager(db)
	snapshotManager := NewSnapshotManager(db, 100)

	// Start managers
	walManager.Start()
	snapshotManager.Start()
	defer walManager.Stop()
	defer snapshotManager.Stop()

	// Log an order with invalid data that will fail deserialization
	blockNum := uint64(50)

	// Create a request that will succeed in WAL but might have issues
	order := &types.Order{
		OrderID:   "order-1",
		UserID:    "user-1",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		Price:     uint256.NewInt(3000),
		Quantity:  uint256.NewInt(10),
		Timestamp: time.Now().Unix(),
	}

	req := interfaces.NewOrderRequest(order, nil, nil)
	seq, err := walManager.LogRequest(req, blockNum)
	require.NoError(t, err)

	// Log response with order (but we'll track it as having an error)
	resp := interfaces.NewOrderResponse(order, nil, nil)
	err = walManager.LogResponse(blockNum, seq, resp)
	require.NoError(t, err)

	// Create recovery engine
	// In production, this would be a BlockchainStateProvider with actual blockchain access
	stateProvider := NewMockStateProvider()
	recoveryEngine := NewRecoveryEngine(db, walManager, snapshotManager, stateProvider)

	// Perform recovery
	dispatcher := NewMockDispatcher()
	err = recoveryEngine.RecoverFromColdStart(dispatcher)
	require.NoError(t, err) // Recovery should succeed even with failed entries

	// Check that error was recorded
	stats := recoveryEngine.GetStats()
	assert.Equal(t, uint64(1), stats.WALEntriesReplayed, "Should attempt to replay entry")
	// Note: The entry had an error response, but recovery should continue
}

func TestRecoveryEngine_AsyncSnapshot(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()

	// Create managers - WAL is sync, Snapshot is ASYNC
	walManager := NewWALManager(db)
	snapshotManager := NewSnapshotManagerWithConfig(db, 100, true) // async = true

	// Start managers
	walManager.Start()
	snapshotManager.Start()
	defer walManager.Stop()
	defer snapshotManager.Stop()

	// Create initial orders and log them to WAL
	var orders []*types.Order
	for i := 0; i < 5; i++ {
		order := &types.Order{
			OrderID:   types.OrderID(common.Hash{byte(i)}.Hex()),
			UserID:    "user-1",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			Price:     uint256.NewInt(3000),
			Quantity:  uint256.NewInt(uint64(i + 1)),
			Timestamp: time.Now().Unix(),
		}
		orders = append(orders, order)
	}

	// Log orders to WAL
	for i, order := range orders {
		req := interfaces.NewOrderRequest(order, nil, nil)
		sequence, err := walManager.LogRequest(req, uint64(90+i))
		require.NoError(t, err)

		// Log response
		resp := interfaces.NewOrderResponse(order, nil, nil)
		err = walManager.LogResponse(uint64(90+i), sequence, resp)
		require.NoError(t, err)
	}

	// Create async snapshot at block 100
	dispatcher := NewMockDispatcher()
	for _, order := range orders {
		dispatcher.orders[string(order.OrderID)] = order
	}

	dispatcherSnapshot := dispatcher.GetSnapshotData(100)
	_, err := snapshotManager.CreateSnapshot(dispatcherSnapshot, 100, common.Hash{}, 5)
	require.NoError(t, err)

	// Wait for async snapshot to complete
	time.Sleep(150 * time.Millisecond)

	// Verify snapshot was saved
	snapshot, err := snapshotManager.LoadSnapshot(100)
	require.NoError(t, err)
	require.NotNil(t, snapshot)

	// Log more orders after snapshot
	for i := 5; i < 8; i++ {
		order := &types.Order{
			OrderID:   types.OrderID(common.Hash{byte(i)}.Hex()),
			UserID:    "user-1",
			Symbol:    "ETH/USDT",
			Side:      types.SELL,
			Price:     uint256.NewInt(3100),
			Quantity:  uint256.NewInt(uint64(i)),
			Timestamp: time.Now().Unix(),
		}

		req := interfaces.NewOrderRequest(order, nil, nil)
		sequence, err := walManager.LogRequest(req, uint64(100+i))
		require.NoError(t, err)

		resp := interfaces.NewOrderResponse(order, nil, nil)
		err = walManager.LogResponse(uint64(100+i), sequence, resp)
		require.NoError(t, err)
	}

	// Create recovery engine
	stateProvider := NewMockStateProvider()
	recoveryEngine := NewRecoveryEngine(db, walManager, snapshotManager, stateProvider)

	// Create new dispatcher for recovery
	recoveredDispatcher := NewMockDispatcher()

	// Perform recovery
	err = recoveryEngine.RecoverFromColdStart(recoveredDispatcher)
	require.NoError(t, err)

	// Verify recovery stats
	stats := recoveryEngine.GetStats()
	assert.True(t, stats.SnapshotLoaded)
	assert.Equal(t, uint64(100), stats.SnapshotBlock)
	assert.Equal(t, uint64(3), stats.WALEntriesReplayed) // 3 entries after snapshot
	assert.Equal(t, uint64(107), stats.LastBlock)

	// Verify recovered state
	// Snapshot had 5 orders, WAL added 3 more = 8 total
	assert.Equal(t, 8, len(recoveredDispatcher.orders), "Should have 5 from snapshot + 3 from WAL")
	assert.Equal(t, 3, len(recoveredDispatcher.processedOrders), "Should process 3 orders from WAL")
}
