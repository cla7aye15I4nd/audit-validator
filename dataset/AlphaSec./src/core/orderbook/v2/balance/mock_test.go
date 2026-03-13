package balance

import (
	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
)

// NewMockStateDB creates a new mock state database for testing
func NewMockStateDB() *MockStateDB {
	return &MockStateDB{
		balances:       make(map[string]map[string]*uint256.Int),
		lockedBalances: make(map[string]map[string]*uint256.Int),
	}
}

// MockStateDB implements types.StateDB interface for testing
type MockStateDB struct {
	balances       map[string]map[string]*uint256.Int // user -> token -> balance
	lockedBalances map[string]map[string]*uint256.Int // user -> token -> locked
}

func (m *MockStateDB) GetTokenBalance(addr common.Address, token string) *uint256.Int {
	userBalances := m.balances[addr.Hex()]
	if userBalances == nil {
		return uint256.NewInt(0)
	}
	
	balance := userBalances[token]
	if balance == nil {
		return uint256.NewInt(0)
	}
	
	// Return available balance (total - locked)
	locked := m.GetLockedTokenBalance(addr, token)
	if locked == nil || locked.IsZero() {
		return clone(balance)
	}
	
	available := new(uint256.Int).Sub(balance, locked)
	if available.Sign() < 0 {
		return uint256.NewInt(0)
	}
	return available
}

func (m *MockStateDB) GetLockedTokenBalance(addr common.Address, token string) *uint256.Int {
	userLocked := m.lockedBalances[addr.Hex()]
	if userLocked == nil {
		return uint256.NewInt(0)
	}
	locked := userLocked[token]
	if locked == nil {
		return uint256.NewInt(0)
	}
	return clone(locked)
}

func (m *MockStateDB) LockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.lockedBalances[addr.Hex()] == nil {
		m.lockedBalances[addr.Hex()] = make(map[string]*uint256.Int)
	}
	
	current := m.lockedBalances[addr.Hex()][token]
	if current == nil {
		current = uint256.NewInt(0)
	}
	
	m.lockedBalances[addr.Hex()][token] = new(uint256.Int).Add(current, amount)
}

func (m *MockStateDB) UnlockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.lockedBalances[addr.Hex()] == nil {
		return
	}
	
	current := m.lockedBalances[addr.Hex()][token]
	if current == nil {
		return
	}
	
	newLocked := new(uint256.Int).Sub(current, amount)
	if newLocked.Sign() <= 0 {
		m.lockedBalances[addr.Hex()][token] = uint256.NewInt(0)
	} else {
		m.lockedBalances[addr.Hex()][token] = newLocked
	}
}

func (m *MockStateDB) ConsumeLockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// Consume from locked balance
	m.UnlockTokenBalance(addr, token, amount)
	// Also deduct from total balance
	m.SubTokenBalance(addr, token, amount)
}

func (m *MockStateDB) AddTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.balances[addr.Hex()] == nil {
		m.balances[addr.Hex()] = make(map[string]*uint256.Int)
	}
	
	current := m.balances[addr.Hex()][token]
	if current == nil {
		current = uint256.NewInt(0)
	}
	
	m.balances[addr.Hex()][token] = new(uint256.Int).Add(current, amount)
}

func (m *MockStateDB) SubTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.balances[addr.Hex()] == nil {
		return
	}
	
	current := m.balances[addr.Hex()][token]
	if current == nil {
		return
	}
	
	newBalance := new(uint256.Int).Sub(current, amount)
	if newBalance.Sign() < 0 {
		m.balances[addr.Hex()][token] = uint256.NewInt(0)
	} else {
		m.balances[addr.Hex()][token] = newBalance
	}
}

// SetTokenBalance helper for testing
func (m *MockStateDB) SetTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.balances[addr.Hex()] == nil {
		m.balances[addr.Hex()] = make(map[string]*uint256.Int)
	}
	m.balances[addr.Hex()][token] = clone(amount)
}

// Helper function
func clone(x *uint256.Int) *uint256.Int {
	if x == nil {
		return nil
	}
	return new(uint256.Int).Set(x)
}