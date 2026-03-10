package balance

import (
	"fmt"
	"sync"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Helper to create large uint256 values
func e18(n uint64) *uint256.Int {
	return new(uint256.Int).Mul(uint256.NewInt(n), uint256.NewInt(1e18))
}

// === BASIC LOCK/UNLOCK TESTS ===

// TestManager_BasicLockUnlock tests basic lock and unlock functionality
func TestManager_BasicLockUnlock(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	user := common.HexToAddress("0x1")
	token := "USDT"
	amount := e18(100)

	// Setup balance
	stateDB.SetTokenBalance(user, token, e18(1000))

	// Test successful lock
	err := manager.Lock("order1", user, token, amount)
	assert.NoError(t, err)

	// Verify lock exists
	lock, exists := manager.GetLock("order1")
	assert.True(t, exists)
	assert.Equal(t, "order1", lock.OrderID)
	assert.Equal(t, user, lock.UserAddr)
	assert.Equal(t, token, lock.Token)
	assert.Equal(t, amount, lock.Amount)

	// Verify locked balance in state
	locked := stateDB.GetLockedTokenBalance(user, token)
	assert.Equal(t, amount.String(), locked.String())

	// Test unlock
	err = manager.CompleteOrder("order1")
	assert.NoError(t, err)

	// Verify lock removed
	_, exists = manager.GetLock("order1")
	assert.False(t, exists)

	locked = stateDB.GetLockedTokenBalance(user, token)
	assert.Equal(t, uint256.NewInt(0).String(), locked.String())
}

// TestManager_DuplicateLock tests duplicate lock attempts
func TestManager_DuplicateLock(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	user := common.HexToAddress("0x1")
	token := "USDT"
	amount := e18(100)

	stateDB.SetTokenBalance(user, token, e18(1000))

	// First lock should succeed
	err := manager.Lock("order1", user, token, amount)
	assert.NoError(t, err)

	// Second lock with same ID should fail
	err = manager.Lock("order1", user, token, amount)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "already has a lock")
}

// TestManager_InsufficientBalance tests insufficient balance scenarios
func TestManager_InsufficientBalance(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	user := common.HexToAddress("0x1")
	token := "USDT"

	// Set low balance
	stateDB.SetTokenBalance(user, token, e18(50))

	// Try to lock more than available
	err := manager.Lock("order1", user, token, e18(100))
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "insufficient balance")
}

// TestManager_ConsumeLock tests consuming locked balance
func TestManager_ConsumeLock(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	user := common.HexToAddress("0x1")
	token := "USDT"
	totalAmount := e18(1000)
	lockAmount := e18(500)

	stateDB.SetTokenBalance(user, token, totalAmount)

	// Lock tokens
	err := manager.Lock("order1", user, token, lockAmount)
	require.NoError(t, err)

	// Consume part of lock
	consumeAmount := e18(200)
	err = manager.ConsumeLock("order1", consumeAmount)
	assert.NoError(t, err)

	// Verify remaining lock and balance
	lock, exists := manager.GetLock("order1")
	assert.True(t, exists)
	assert.Equal(t, e18(300), lock.Amount)

	// Available balance should be total - locked
	// Total: 1000 - 200 consumed = 800
	// Locked: 500 - 200 consumed = 300
	// Available: 800 - 300 = 500
	balance := stateDB.GetTokenBalance(user, token)
	assert.Equal(t, e18(500), balance) // Available balance after consume

	// Verify balance was consumed
	totalBalance := stateDB.GetTokenBalance(user, token)
	lockedBalance := stateDB.GetLockedTokenBalance(user, token)
	// Total should be 800 (1000 - 200 consumed)
	assert.Equal(t, e18(800).String(),
		new(uint256.Int).Add(totalBalance, lockedBalance).String())
}

// === INVALID AMOUNT TESTS ===

// TestManager_InvalidAmounts tests invalid amount handling
func TestManager_InvalidAmounts(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	user := common.HexToAddress("0x1")
	token := "USDT"

	stateDB.SetTokenBalance(user, token, e18(1000))

	// Test nil amount
	err := manager.Lock("order1", user, token, nil)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "invalid lock amount")

	// Test zero amount
	err = manager.Lock("order1", user, token, uint256.NewInt(0))
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "invalid lock amount")

	// Test negative amount (though uint256 can't be negative, test edge case)
	negAmount := new(uint256.Int).Sub(uint256.NewInt(0), uint256.NewInt(1))
	err = manager.Lock("order1", user, token, negAmount)
	assert.Error(t, err)
}

// === USER OPERATIONS ===

// TestManager_UnlockAllForUser tests unlocking all orders for a user
func TestManager_UnlockAllForUser(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	user1 := common.HexToAddress("0x1")
	user2 := common.HexToAddress("0x2")

	stateDB.SetTokenBalance(user1, "USDT", e18(1000))
	stateDB.SetTokenBalance(user1, "WETH", e18(10))
	stateDB.SetTokenBalance(user2, "USDT", e18(1000))

	// Create multiple orders for user1
	require.NoError(t, manager.Lock("order1", user1, "USDT", e18(100)))
	require.NoError(t, manager.Lock("order2", user1, "USDT", e18(200)))
	require.NoError(t, manager.Lock("order3", user1, "WETH", e18(5)))

	// Create order for user2
	require.NoError(t, manager.Lock("order4", user2, "USDT", e18(300)))

	// Unlock all for user1
	unlockedOrders := manager.UnlockAllForUser(user1.Hex())
	assert.Len(t, unlockedOrders, 3)
	assert.Contains(t, unlockedOrders, "order1")
	assert.Contains(t, unlockedOrders, "order2")
	assert.Contains(t, unlockedOrders, "order3")

	// Verify user1 orders are unlocked
	_, exists := manager.GetLock("order1")
	assert.False(t, exists)
	_, exists = manager.GetLock("order2")
	assert.False(t, exists)
	_, exists = manager.GetLock("order3")
	assert.False(t, exists)

	// Verify user2 order still locked
	_, exists = manager.GetLock("order4")
	assert.True(t, exists)
}

// === ORDER-SPECIFIC LOCKING ===

// TestManager_LockForOrder tests automatic lock calculation for orders
func TestManager_LockForOrder(t *testing.T) {
	tests := []struct {
		name        string
		orderType   types.OrderType
		orderMode   types.OrderMode
		side        types.OrderSide
		quantity    *uint256.Int
		price       *uint256.Int
		symbol      types.Symbol
		expectedAmt *uint256.Int
		expectedTok string
		expectErr   bool
	}{
		{
			name:        "Limit Buy Base Mode",
			orderType:   types.LIMIT,
			orderMode:   types.BASE_MODE,
			side:        types.BUY,
			quantity:    e18(10),  // 10 base tokens
			price:       e18(100), // price 100
			symbol:      "WETH-USDT",
			expectedAmt: e18(1000), // 10 * 100
			expectedTok: "USDT",
			expectErr:   false,
		},
		{
			name:        "Limit Sell Base Mode",
			orderType:   types.LIMIT,
			orderMode:   types.BASE_MODE,
			side:        types.SELL,
			quantity:    e18(10), // 10 base tokens
			price:       e18(100),
			symbol:      "WETH-USDT",
			expectedAmt: e18(10),
			expectedTok: "WETH",
			expectErr:   false,
		},
		{
			name:      "Market Buy Quote Mode",
			orderType: types.MARKET,
			orderMode: types.QUOTE_MODE,
			side:      types.BUY,
			quantity:  e18(1000), // 1000 USDT to spend
			symbol:    "WETH-USDT",
			expectErr: false,
		},
		{
			name:      "Market Sell Base Mode",
			orderType: types.MARKET,
			orderMode: types.BASE_MODE,
			side:      types.SELL,
			quantity:  e18(10), // 10 WETH to sell
			symbol:    "WETH-USDT",
			expectErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			stateDB := NewMockStateDB()
			manager := NewManager()
			manager.SetStateDB(stateDB)

			user := common.HexToAddress("0x1")
			userID := types.UserID(user.Hex())

			// Setup balances
			stateDB.SetTokenBalance(user, "USDT", e18(10000))
			stateDB.SetTokenBalance(user, "WETH", e18(100))

			order := &types.Order{
				OrderID:   "test-order",
				UserID:    userID,
				Symbol:    tt.symbol,
				OrderType: tt.orderType,
				OrderMode: tt.orderMode,
				Side:      tt.side,
				Quantity:  tt.quantity,
				Price:     tt.price,
			}

			err := manager.LockForOrder(order)
			if tt.expectErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)

				lock, exists := manager.GetLock("test-order")
				assert.True(t, exists)

				if tt.orderType == types.LIMIT {
					assert.Equal(t, tt.expectedAmt, lock.Amount)
					assert.Equal(t, tt.expectedTok, lock.Token)
				}
				// For market orders, just verify a lock was created
			}
		})
	}
}

// === ORDER MODIFICATION ===

// TestManager_ModifyOrderLock tests order modification scenarios
func TestManager_ModifyOrderLock(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	user := common.HexToAddress("0x1")
	userID := types.UserID(user.Hex())

	stateDB.SetTokenBalance(user, "USDT", e18(10000))
	stateDB.SetTokenBalance(user, "WETH", e18(100))

	// Create initial order
	oldOrder := &types.Order{
		OrderID:   "order1",
		UserID:    userID,
		Symbol:    "WETH-USDT",
		OrderType: types.LIMIT,
		OrderMode: types.BASE_MODE,
		Side:      types.BUY,
		Quantity:  e18(10),
		Price:     e18(100),
	}

	// Lock for initial order
	err := manager.LockForOrder(oldOrder)
	require.NoError(t, err)

	// Test increase amount (same token)
	newOrder1 := &types.Order{
		OrderID:   "order2",
		UserID:    userID,
		Symbol:    "WETH-USDT",
		OrderType: types.LIMIT,
		OrderMode: types.BASE_MODE,
		Side:      types.BUY,
		Quantity:  e18(20), // Increase quantity
		Price:     e18(100),
	}

	err = manager.ModifyOrderLock("order1", newOrder1)
	assert.NoError(t, err)

	lock, exists := manager.GetLock("order2")
	assert.True(t, exists)
	assert.Equal(t, e18(2000), lock.Amount) // 20 * 100

	// Old order should not exist
	_, exists = manager.GetLock("order1")
	assert.False(t, exists)

	// Test decrease amount (same token)
	newOrder2 := &types.Order{
		OrderID:   "order3",
		UserID:    userID,
		Symbol:    "WETH-USDT",
		OrderType: types.LIMIT,
		OrderMode: types.BASE_MODE,
		Side:      types.BUY,
		Quantity:  e18(5), // Decrease quantity
		Price:     e18(100),
	}

	err = manager.ModifyOrderLock("order2", newOrder2)
	assert.NoError(t, err)

	lock, exists = manager.GetLock("order3")
	assert.True(t, exists)
	assert.Equal(t, e18(500), lock.Amount) // 5 * 100
}

// TestManager_ModifyOrderLock_TokenChange tests token change rejection
func TestManager_ModifyOrderLock_TokenChange(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	user := common.HexToAddress("0x1")
	userID := types.UserID(user.Hex())

	stateDB.SetTokenBalance(user, "USDT", e18(10000))
	stateDB.SetTokenBalance(user, "WETH", e18(100))

	// Create initial buy order (locks USDT)
	oldOrder := &types.Order{
		OrderID:   "order1",
		UserID:    userID,
		Symbol:    "WETH-USDT",
		OrderType: types.LIMIT,
		OrderMode: types.BASE_MODE,
		Side:      types.BUY,
		Quantity:  e18(10),
		Price:     e18(100),
	}

	err := manager.LockForOrder(oldOrder)
	require.NoError(t, err)

	// Try to modify to sell order (would lock WETH instead of USDT)
	newOrder := &types.Order{
		OrderID:   "order2",
		UserID:    userID,
		Symbol:    "WETH-USDT",
		OrderType: types.LIMIT,
		OrderMode: types.BASE_MODE,
		Side:      types.SELL, // Changed to SELL
		Quantity:  e18(10),
		Price:     e18(100),
	}

	err = manager.ModifyOrderLock("order1", newOrder)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "token change not allowed")
	assert.Contains(t, err.Error(), "Cancel and place new order instead")

	// Original lock should still exist
	lock, exists := manager.GetLock("order1")
	assert.True(t, exists)
	assert.Equal(t, "USDT", lock.Token)
}

// === CONCURRENT OPERATIONS ===

// TestManager_ConcurrentOperations tests thread safety
func TestManager_ConcurrentOperations(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	numUsers := 10
	numOrdersPerUser := 10

	// Setup balances
	for i := 0; i < numUsers; i++ {
		user := common.HexToAddress(string(rune('0' + i)))
		stateDB.SetTokenBalance(user, "USDT", e18(10000))
	}

	var wg sync.WaitGroup

	// Concurrent locks
	for i := 0; i < numUsers; i++ {
		wg.Add(1)
		go func(userIdx int) {
			defer wg.Done()
			user := common.HexToAddress(string(rune('0' + userIdx)))

			for j := 0; j < numOrdersPerUser; j++ {
				orderID := fmt.Sprintf("%d-order-%d", userIdx, j)
				err := manager.Lock(orderID, user, "USDT", e18(10))
				assert.NoError(t, err)
			}
		}(i)
	}

	wg.Wait()

	// Verify all locks created
	for i := 0; i < numUsers; i++ {
		for j := 0; j < numOrdersPerUser; j++ {
			orderID := fmt.Sprintf("%d-order-%d", i, j)
			_, exists := manager.GetLock(orderID)
			assert.True(t, exists, "Lock should exist for %s", orderID)
		}
	}

	// Concurrent unlocks
	for i := 0; i < numUsers; i++ {
		wg.Add(1)
		go func(userIdx int) {
			defer wg.Done()

			for j := 0; j < numOrdersPerUser; j++ {
				orderID := fmt.Sprintf("%d-order-%d", userIdx, j)
				err := manager.CompleteOrder(orderID)
				assert.NoError(t, err)
			}
		}(i)
	}

	wg.Wait()

	// Verify all locks removed
	for i := 0; i < numUsers; i++ {
		for j := 0; j < numOrdersPerUser; j++ {
			orderID := fmt.Sprintf("%d-order-%d", i, j)
			_, exists := manager.GetLock(orderID)
			assert.False(t, exists, "Lock should not exist for %s", orderID)
		}
	}
}

// === EDGE CASES ===

// TestManager_ConsumeLock_EdgeCases tests edge cases for consume lock
func TestManager_ConsumeLock_EdgeCases(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	user := common.HexToAddress("0x1")
	stateDB.SetTokenBalance(user, "USDT", e18(1000))

	// Lock tokens
	err := manager.Lock("order1", user, "USDT", e18(500))
	require.NoError(t, err)

	// Try to consume more than locked
	err = manager.ConsumeLock("order1", e18(600))
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "exceeds locked amount")

	// Try to consume from non-existent order
	err = manager.ConsumeLock("non-existent", e18(100))
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "no lock found")

	// Try to consume with nil amount
	err = manager.ConsumeLock("order1", nil)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "invalid consume amount")

	// Try to consume with zero amount
	err = manager.ConsumeLock("order1", uint256.NewInt(0))
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "invalid consume amount")
}

// TestManager_ModifyOrderLock_EdgeCases tests edge cases for order modification
func TestManager_ModifyOrderLock_EdgeCases(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	user := common.HexToAddress("0x1")
	userID := types.UserID(user.Hex())

	stateDB.SetTokenBalance(user, "USDT", e18(1000))

	// Try to modify non-existent order
	newOrder := &types.Order{
		OrderID:   "order2",
		UserID:    userID,
		Symbol:    "WETH-USDT",
		OrderType: types.LIMIT,
		OrderMode: types.BASE_MODE,
		Side:      types.BUY,
		Quantity:  e18(10),
		Price:     e18(100),
	}

	err := manager.ModifyOrderLock("non-existent", newOrder)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "no lock found")

	// Try to modify with nil order
	err = manager.ModifyOrderLock("order1", nil)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "new order cannot be nil")

	// Create an order to modify
	oldOrder := &types.Order{
		OrderID:   "order1",
		UserID:    userID,
		Symbol:    "WETH-USDT",
		OrderType: types.LIMIT,
		OrderMode: types.BASE_MODE,
		Side:      types.BUY,
		Quantity:  e18(5),
		Price:     e18(100),
	}

	err = manager.LockForOrder(oldOrder)
	require.NoError(t, err)

	// Try to modify with insufficient balance for increase
	bigOrder := &types.Order{
		OrderID:   "order2",
		UserID:    userID,
		Symbol:    "WETH-USDT",
		OrderType: types.LIMIT,
		OrderMode: types.BASE_MODE,
		Side:      types.BUY,
		Quantity:  e18(100), // Would need 10000 USDT
		Price:     e18(100),
	}

	err = manager.ModifyOrderLock("order1", bigOrder)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "insufficient balance")
}

// TestManager_ZeroPriceHandling tests zero price handling
func TestManager_ZeroPriceHandling(t *testing.T) {
	stateDB := NewMockStateDB()
	manager := NewManager()
	manager.SetStateDB(stateDB)

	user := common.HexToAddress("0x1")
	userID := types.UserID(user.Hex())

	stateDB.SetTokenBalance(user, "USDT", e18(10000))
	stateDB.SetTokenBalance(user, "WETH", e18(100))

	// Buy order with zero price in base mode (should fail)
	order := &types.Order{
		OrderID:   "order1",
		UserID:    userID,
		Symbol:    "WETH-USDT",
		OrderType: types.LIMIT,
		OrderMode: types.BASE_MODE,
		Side:      types.BUY,
		Quantity:  e18(10),
		Price:     uint256.NewInt(0),
	}

	err := manager.LockForOrder(order)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "price required")

}
