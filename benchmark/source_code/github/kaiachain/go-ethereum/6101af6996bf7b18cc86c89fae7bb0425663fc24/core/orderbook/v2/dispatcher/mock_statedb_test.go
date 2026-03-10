package dispatcher

import (
	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
)

// mockStateDB implements balance.StateDB interface for testing
type mockStateDB struct {
	balances       map[string]map[string]*uint256.Int // user -> token -> balance
	lockedBalances map[string]map[string]*uint256.Int // user -> token -> locked
}

func newMockStateDB() *mockStateDB {
	return &mockStateDB{
		balances:       make(map[string]map[string]*uint256.Int),
		lockedBalances: make(map[string]map[string]*uint256.Int),
	}
}

func (m *mockStateDB) GetTokenBalance(addr common.Address, token string) *uint256.Int {
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
	if locked == nil {
		return clone(balance)
	}

	available, _ := safeSub(balance, locked)
	if available == nil {
		return uint256.NewInt(0)
	}
	return available
}

func (m *mockStateDB) GetLockedTokenBalance(addr common.Address, token string) *uint256.Int {
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

func (m *mockStateDB) LockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.lockedBalances[addr.Hex()] == nil {
		m.lockedBalances[addr.Hex()] = make(map[string]*uint256.Int)
	}

	current := m.lockedBalances[addr.Hex()][token]
	if current == nil {
		current = uint256.NewInt(0)
	}

	m.lockedBalances[addr.Hex()][token], _ = safeAdd(current, amount)
}

func (m *mockStateDB) UnlockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.lockedBalances[addr.Hex()] == nil {
		return
	}

	current := m.lockedBalances[addr.Hex()][token]
	if current == nil {
		return
	}

	newLocked, err := safeSub(current, amount)
	if err != nil {
		m.lockedBalances[addr.Hex()][token] = uint256.NewInt(0)
	} else {
		m.lockedBalances[addr.Hex()][token] = newLocked
	}
}

func (m *mockStateDB) ConsumeLockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// Consume from locked balance (reduce locked amount)
	m.UnlockTokenBalance(addr, token, amount)
	// Deduct from total balance (the consumed amount is actually spent)
	m.SubTokenBalance(addr, token, amount)
}

func (m *mockStateDB) AddTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.balances[addr.Hex()] == nil {
		m.balances[addr.Hex()] = make(map[string]*uint256.Int)
	}

	current := m.balances[addr.Hex()][token]
	if current == nil {
		current = uint256.NewInt(0)
	}

	m.balances[addr.Hex()][token], _ = safeAdd(current, amount)
}

func (m *mockStateDB) SubTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.balances[addr.Hex()] == nil {
		return
	}

	current := m.balances[addr.Hex()][token]
	if current == nil {
		return
	}

	newBalance, err := safeSub(current, amount)
	if err != nil {
		m.balances[addr.Hex()][token] = uint256.NewInt(0)
	} else {
		m.balances[addr.Hex()][token] = newBalance
	}
}

// SetBalance helper for testing
func (m *mockStateDB) SetBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.balances[addr.Hex()] == nil {
		m.balances[addr.Hex()] = make(map[string]*uint256.Int)
	}
	m.balances[addr.Hex()][token] = clone(amount)
}

// GetBalance helper for testing - returns the total balance (not available)
func (m *mockStateDB) GetBalance(addr common.Address, token string) *uint256.Int {
	userBalances := m.balances[addr.Hex()]
	if userBalances == nil {
		return uint256.NewInt(0)
	}
	balance := userBalances[token]
	if balance == nil {
		return uint256.NewInt(0)
	}
	return clone(balance)
}

// GetLockedBalance helper for testing - returns locked balance
func (m *mockStateDB) GetLockedBalance(addr common.Address, token string) *uint256.Int {
	return m.GetLockedTokenBalance(addr, token)
}

// Helper functions
func clone(x *uint256.Int) *uint256.Int {
	if x == nil {
		return nil
	}
	return new(uint256.Int).Set(x)
}

func safeAdd(a, b *uint256.Int) (*uint256.Int, error) {
	if a == nil || b == nil {
		return nil, nil
	}
	result, overflow := new(uint256.Int).AddOverflow(a, b)
	if overflow {
		return nil, nil
	}
	return result, nil
}

func safeSub(a, b *uint256.Int) (*uint256.Int, error) {
	if a == nil || b == nil {
		return nil, nil
	}
	if a.Cmp(b) < 0 {
		return nil, nil
	}
	result := new(uint256.Int).Sub(a, b)
	return result, nil
}
