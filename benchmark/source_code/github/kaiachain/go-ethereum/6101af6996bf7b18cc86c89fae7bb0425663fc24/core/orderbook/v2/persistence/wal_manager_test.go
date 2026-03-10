package persistence

import (
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

func TestWALManager_Basic(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create WAL manager
	wal := NewWALManager(db)
	require.NotNil(t, wal)
	
	// Start WAL manager (no return value)
	wal.Start()
	defer wal.Stop()
	
	// Test that WAL manager is initialized
	// Note: currentSequence starts at 0 and increments when logging
	assert.Equal(t, uint64(0), wal.currentSequence)
	assert.Equal(t, uint64(0), wal.currentBlock)
}

func TestWALManager_LogRequest(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create and start WAL manager
	wal := NewWALManager(db)
	wal.Start()
	defer wal.Stop()
	
	// Create block number
	blockNum := uint64(100)
	
	// Create a test order request
	order := &types.Order{
		OrderID:   "order-123",
		UserID:    "user-456",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		Price:     uint256.NewInt(3000),
		Quantity:  uint256.NewInt(1),
		Timestamp: time.Now().Unix(),
	}
	
	req := interfaces.NewOrderRequest(order, nil, nil)
	
	// Log the request with block number
	sequence, err := wal.LogRequest(req, blockNum)
	require.NoError(t, err)
	assert.Greater(t, sequence, uint64(0))
	
	// Log another request and verify sequence increments
	order2 := &types.Order{
		OrderID:   "order-124",
		UserID:    "user-456",
		Symbol:    "ETH/USDT",
		Side:      types.SELL,
		Price:     uint256.NewInt(3100),
		Quantity:  uint256.NewInt(2),
		Timestamp: time.Now().Unix(),
	}
	
	req2 := interfaces.NewOrderRequest(order2, nil, nil)
	sequence2, err := wal.LogRequest(req2, blockNum)
	require.NoError(t, err)
	assert.Equal(t, sequence+1, sequence2)
}

func TestWALManager_LogResponse(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create and start WAL manager
	wal := NewWALManager(db)
	wal.Start()
	defer wal.Stop()
	
	// Create block number
	blockNum := uint64(100)
	
	// Create and log a request first
	order := &types.Order{
		OrderID:   "order-125",
		UserID:    "user-789",
		Symbol:    "BTC/USDT",
		Side:      types.BUY,
		Price:     uint256.NewInt(50000),
		Quantity:  uint256.NewInt(1),
		Timestamp: time.Now().Unix(),
	}
	
	req := interfaces.NewOrderRequest(order, nil, nil)
	sequence, err := wal.LogRequest(req, blockNum)
	require.NoError(t, err)
	
	// Create a response
	resp := interfaces.NewOrderResponse(order, nil, nil)
	
	// Log the response
	err = wal.LogResponse(blockNum, sequence, resp)
	require.NoError(t, err)
}

func TestWALManager_GetEntry(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create and start WAL manager
	wal := NewWALManager(db)
	wal.Start()
	defer wal.Stop()
	
	// Create block number
	blockNum := uint64(100)
	
	// Log a request
	order := &types.Order{
		OrderID:   "order-126",
		UserID:    "user-001",
		Symbol:    "ETH/USDT",
		Side:      types.BUY,
		Price:     uint256.NewInt(3000),
		Quantity:  uint256.NewInt(1),
		Timestamp: time.Now().Unix(),
	}
	
	req := interfaces.NewOrderRequest(order, nil, nil)
	sequence, err := wal.LogRequest(req, blockNum)
	require.NoError(t, err)
	
	// Retrieve the entry
	entry, err := wal.GetEntry(blockNum, sequence)
	require.NoError(t, err)
	require.NotNil(t, entry)
	
	// Verify entry contents
	assert.Equal(t, sequence, entry.Sequence)
	assert.Equal(t, blockNum, entry.BlockNumber)
	// TxIndex removed from BlockContext
	assert.Equal(t, "ORDER", entry.RequestType)
	assert.NotNil(t, entry.RequestData)
	assert.Nil(t, entry.ResponseData) // No response logged yet
}

func TestWALManager_GetEntriesRange(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create and start WAL manager
	wal := NewWALManager(db)
	wal.Start()
	defer wal.Stop()
	
	// Create block number
	blockNum := uint64(100)
	
	// Log multiple requests
	var sequences []uint64
	for i := 0; i < 5; i++ {
		order := &types.Order{
			OrderID:   types.OrderID(common.Hash{byte(i)}.Hex()),
			UserID:    "user-001",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			Price:     uint256.NewInt(3000),
			Quantity:  uint256.NewInt(1),
			Timestamp: time.Now().Unix(),
		}
		
		req := interfaces.NewOrderRequest(order, nil, nil)
		
		// TxIndex removed, each request still tracked by sequence
		sequence, err := wal.LogRequest(req, blockNum)
		require.NoError(t, err)
		sequences = append(sequences, sequence)
	}
	
	// Get entries in range
	entries, err := wal.GetEntriesRange(sequences[1], sequences[3])
	require.NoError(t, err)
	assert.Len(t, entries, 3) // Should get entries at sequences[1], sequences[2], sequences[3]
	
	// Verify entries are in order
	for i, entry := range entries {
		assert.Equal(t, sequences[i+1], entry.Sequence)
	}
}

func TestWALManager_GetEntriesSince(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// Create and start WAL manager
	wal := NewWALManager(db)
	wal.Start()
	defer wal.Stop()
	
	// Log requests in different blocks
	blocks := []uint64{100, 100, 101, 101, 102}
	for i, blockNum := range blocks {
		order := &types.Order{
			OrderID:   types.OrderID(common.Hash{byte(i)}.Hex()),
			UserID:    "user-001",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			Price:     uint256.NewInt(3000),
			Quantity:  uint256.NewInt(1),
			Timestamp: time.Now().Unix(),
		}
		
		req := interfaces.NewOrderRequest(order, nil, nil)
		_, err := wal.LogRequest(req, blockNum)
		require.NoError(t, err)
	}
	
	// Get entries since block 101
	entries, err := wal.GetEntriesSince(101)
	require.NoError(t, err)
	assert.Len(t, entries, 3) // Should get entries from blocks 101 and 102
	
	// Verify all entries are from block 101 or later
	for _, entry := range entries {
		assert.GreaterOrEqual(t, entry.BlockNumber, uint64(101))
	}
}

func TestWALManager_Restart(t *testing.T) {
	// Create in-memory database
	db := memorydb.New()
	
	// First session
	wal1 := NewWALManager(db)
	wal1.Start()
	
	blockNum := uint64(100)
	
	// Log some requests
	var lastSequence uint64
	for i := 0; i < 5; i++ {
		order := &types.Order{
			OrderID:   types.OrderID(common.Hash{byte(i)}.Hex()),
			UserID:    "user-1",
			Symbol:    "ETH/USDT",
			Side:      types.BUY,
			Price:     uint256.NewInt(3000),
			Quantity:  uint256.NewInt(1),
			Timestamp: time.Now().Unix(),
		}
		req := interfaces.NewOrderRequest(order, nil, nil)
		lastSequence, _ = wal1.LogRequest(req, blockNum)
	}
	
	// Stop first WAL manager
	err := wal1.Stop()
	require.NoError(t, err)
	
	// Create new WAL manager with same database
	wal2 := NewWALManager(db)
	wal2.Start()
	defer wal2.Stop()
	
	// The sequence should continue from where it left off
	blockNum2 := uint64(101)
	
	order := &types.Order{
		OrderID:   "new-order",
		UserID:    "user-2",
		Symbol:    "BTC/USDT",
		Side:      types.SELL,
		Price:     uint256.NewInt(50000),
		Quantity:  uint256.NewInt(1),
		Timestamp: time.Now().Unix(),
	}
	req := interfaces.NewOrderRequest(order, nil, nil)
	newSequence, err := wal2.LogRequest(req, blockNum2)
	require.NoError(t, err)
	
	// New sequence should be greater than last sequence from previous session
	assert.Greater(t, newSequence, lastSequence)
	assert.Equal(t, lastSequence+1, newSequence)
}