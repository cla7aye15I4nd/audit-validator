package mocks

import (
	"sync"

	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
)

// MockStateDB is a mock implementation of types.StateDB for testing
type MockStateDB struct {
	mu       sync.RWMutex
	balances map[common.Address]map[string]*uint256.Int // user -> token -> balance
	locked   map[common.Address]map[string]*uint256.Int // user -> token -> locked amount
}

// NewMockStateDB creates a new mock StateDB
func NewMockStateDB() *MockStateDB {
	return &MockStateDB{
		balances: make(map[common.Address]map[string]*uint256.Int),
		locked:   make(map[common.Address]map[string]*uint256.Int),
	}
}

// SetTokenBalance sets a token balance for testing
func (m *MockStateDB) SetTokenBalance(user common.Address, token string, amount *uint256.Int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	if m.balances[user] == nil {
		m.balances[user] = make(map[string]*uint256.Int)
	}
	m.balances[user][token] = new(uint256.Int).Set(amount)
}

// GetTokenBalance returns the available balance (total - locked)
func (m *MockStateDB) GetTokenBalance(user common.Address, token string) *uint256.Int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	if m.balances[user] == nil {
		return uint256.NewInt(0)
	}
	
	total := m.balances[user][token]
	if total == nil {
		return uint256.NewInt(0)
	}
	
	// Subtract locked amount
	if m.locked[user] != nil && m.locked[user][token] != nil {
		available := new(uint256.Int).Sub(total, m.locked[user][token])
		if available.Sign() < 0 {
			return uint256.NewInt(0)
		}
		return available
	}
	
	return new(uint256.Int).Set(total)
}

// LockTokenBalance locks a token balance
func (m *MockStateDB) LockTokenBalance(user common.Address, token string, amount *uint256.Int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	if m.locked[user] == nil {
		m.locked[user] = make(map[string]*uint256.Int)
	}
	
	if m.locked[user][token] == nil {
		m.locked[user][token] = uint256.NewInt(0)
	}
	
	m.locked[user][token] = new(uint256.Int).Add(m.locked[user][token], amount)
}

// UnlockTokenBalance unlocks a token balance
func (m *MockStateDB) UnlockTokenBalance(user common.Address, token string, amount *uint256.Int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	if m.locked[user] == nil || m.locked[user][token] == nil {
		return
	}
	
	m.locked[user][token] = new(uint256.Int).Sub(m.locked[user][token], amount)
	if m.locked[user][token].Sign() <= 0 {
		m.locked[user][token] = uint256.NewInt(0)
	}
}

// ConsumeLockTokenBalance consumes from locked balance (deducts from total)
func (m *MockStateDB) ConsumeLockTokenBalance(user common.Address, token string, amount *uint256.Int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	// Reduce locked amount
	if m.locked[user] != nil && m.locked[user][token] != nil {
		m.locked[user][token] = new(uint256.Int).Sub(m.locked[user][token], amount)
		if m.locked[user][token].Sign() <= 0 {
			m.locked[user][token] = uint256.NewInt(0)
		}
	}
	
	// Reduce total balance
	if m.balances[user] != nil && m.balances[user][token] != nil {
		m.balances[user][token] = new(uint256.Int).Sub(m.balances[user][token], amount)
		if m.balances[user][token].Sign() <= 0 {
			m.balances[user][token] = uint256.NewInt(0)
		}
	}
}

// TransferToken transfers tokens between users
func (m *MockStateDB) TransferToken(from, to common.Address, token string, amount *uint256.Int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	// Deduct from sender
	if m.balances[from] != nil && m.balances[from][token] != nil {
		m.balances[from][token] = new(uint256.Int).Sub(m.balances[from][token], amount)
		if m.balances[from][token].Sign() <= 0 {
			delete(m.balances[from], token)
		}
	}
	
	// Add to receiver
	if m.balances[to] == nil {
		m.balances[to] = make(map[string]*uint256.Int)
	}
	if m.balances[to][token] == nil {
		m.balances[to][token] = uint256.NewInt(0)
	}
	m.balances[to][token] = new(uint256.Int).Add(m.balances[to][token], amount)
}

// GetLockedTokenBalance returns the locked balance
func (m *MockStateDB) GetLockedTokenBalance(user common.Address, token string) *uint256.Int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	if m.locked[user] == nil || m.locked[user][token] == nil {
		return uint256.NewInt(0)
	}
	
	return new(uint256.Int).Set(m.locked[user][token])
}

// AddTokenBalance adds to token balance
func (m *MockStateDB) AddTokenBalance(user common.Address, token string, amount *uint256.Int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	if m.balances[user] == nil {
		m.balances[user] = make(map[string]*uint256.Int)
	}
	if m.balances[user][token] == nil {
		m.balances[user][token] = uint256.NewInt(0)
	}
	m.balances[user][token] = new(uint256.Int).Add(m.balances[user][token], amount)
}

// SubTokenBalance subtracts from token balance
func (m *MockStateDB) SubTokenBalance(user common.Address, token string, amount *uint256.Int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	if m.balances[user] != nil && m.balances[user][token] != nil {
		m.balances[user][token] = new(uint256.Int).Sub(m.balances[user][token], amount)
		if m.balances[user][token].Sign() < 0 {
			m.balances[user][token] = uint256.NewInt(0)
		}
	}
}

// GetTotalBalance returns the total balance (including locked) for testing
func (m *MockStateDB) GetTotalBalance(user common.Address, token string) *uint256.Int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	if m.balances[user] == nil || m.balances[user][token] == nil {
		return uint256.NewInt(0)
	}
	
	return new(uint256.Int).Set(m.balances[user][token])
}