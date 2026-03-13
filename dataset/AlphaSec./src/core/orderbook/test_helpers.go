package orderbook

import (
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
)

// mockFeeGetter is a mock implementation of FeeRetriever for testing
type mockFeeGetter struct {
	makerFee *big.Int
	takerFee *big.Int
}

func newMockFeeGetter() *mockFeeGetter {
	return &mockFeeGetter{
		makerFee: big.NewInt(25), // 0.000025%
		takerFee: big.NewInt(30), // 0.000030%
	}
}

func (m *mockFeeGetter) GetMarketFees(base, quote uint64) (*big.Int, *big.Int, error) {
	return m.makerFee, m.takerFee, nil
}

// mockLocker is a mock implementation of Locker for testing
type mockLocker struct {
	balances       map[common.Address]map[string]*uint256.Int
	lockedBalances map[common.Address]map[string]*uint256.Int
}

func newMockLocker() *mockLocker {
	return &mockLocker{
		balances:       make(map[common.Address]map[string]*uint256.Int),
		lockedBalances: make(map[common.Address]map[string]*uint256.Int),
	}
}

func (m *mockLocker) AddTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.balances[addr] == nil {
		m.balances[addr] = make(map[string]*uint256.Int)
	}
	if m.balances[addr][token] == nil {
		m.balances[addr][token] = new(uint256.Int)
	}
	m.balances[addr][token].Add(m.balances[addr][token], amount)
}

func (m *mockLocker) ConsumeLockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// For testing, just reduce the locked balance
	if m.lockedBalances[addr] != nil && m.lockedBalances[addr][token] != nil {
		if m.lockedBalances[addr][token].Cmp(amount) >= 0 {
			m.lockedBalances[addr][token].Sub(m.lockedBalances[addr][token], amount)
		}
	}
}

func (m *mockLocker) GetTokenBalance(addr common.Address, token string) *uint256.Int {
	if m.balances[addr] == nil || m.balances[addr][token] == nil {
		return uint256.NewInt(0)
	}
	return new(uint256.Int).Set(m.balances[addr][token])
}

func (m *mockLocker) LockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.lockedBalances[addr] == nil {
		m.lockedBalances[addr] = make(map[string]*uint256.Int)
	}
	if m.lockedBalances[addr][token] == nil {
		m.lockedBalances[addr][token] = new(uint256.Int)
	}
	m.lockedBalances[addr][token].Add(m.lockedBalances[addr][token], amount)
	
	// Also reduce from available balance
	if m.balances[addr] != nil && m.balances[addr][token] != nil {
		if m.balances[addr][token].Cmp(amount) >= 0 {
			m.balances[addr][token].Sub(m.balances[addr][token], amount)
		}
	}
}

func (m *mockLocker) UnlockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.lockedBalances[addr] != nil && m.lockedBalances[addr][token] != nil {
		if m.lockedBalances[addr][token].Cmp(amount) >= 0 {
			m.lockedBalances[addr][token].Sub(m.lockedBalances[addr][token], amount)
		}
	}
	
	// Add back to available balance
	m.AddTokenBalance(addr, token, amount)
}

func (m *mockLocker) GetLockedTokenBalance(addr common.Address, token string) *uint256.Int {
	if m.lockedBalances[addr] == nil || m.lockedBalances[addr][token] == nil {
		return uint256.NewInt(0)
	}
	return new(uint256.Int).Set(m.lockedBalances[addr][token])
}