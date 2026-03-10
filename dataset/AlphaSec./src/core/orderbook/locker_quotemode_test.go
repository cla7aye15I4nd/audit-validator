package orderbook

import (
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
)

// TestMockLocker implements the Locker interface with actual tracking for testing
type TestMockLocker struct {
	balances       map[common.Address]map[string]*uint256.Int
	lockedBalances map[common.Address]map[string]*uint256.Int
}

func NewTestMockLocker() *TestMockLocker {
	return &TestMockLocker{
		balances:       make(map[common.Address]map[string]*uint256.Int),
		lockedBalances: make(map[common.Address]map[string]*uint256.Int),
	}
}

func (m *TestMockLocker) GetTokenBalance(addr common.Address, token string) *uint256.Int {
	if m.balances[addr] == nil || m.balances[addr][token] == nil {
		return uint256.NewInt(0)
	}
	return new(uint256.Int).Set(m.balances[addr][token])
}

func (m *TestMockLocker) AddTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.balances[addr] == nil {
		m.balances[addr] = make(map[string]*uint256.Int)
	}
	if m.balances[addr][token] == nil {
		m.balances[addr][token] = uint256.NewInt(0)
	}
	m.balances[addr][token].Add(m.balances[addr][token], amount)
}

func (m *TestMockLocker) SubTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.balances[addr] != nil && m.balances[addr][token] != nil {
		m.balances[addr][token].Sub(m.balances[addr][token], amount)
	}
}

func (m *TestMockLocker) GetLockedTokenBalance(addr common.Address, token string) *uint256.Int {
	if m.lockedBalances[addr] == nil || m.lockedBalances[addr][token] == nil {
		return uint256.NewInt(0)
	}
	return new(uint256.Int).Set(m.lockedBalances[addr][token])
}

func (m *TestMockLocker) LockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.lockedBalances[addr] == nil {
		m.lockedBalances[addr] = make(map[string]*uint256.Int)
	}
	if m.lockedBalances[addr][token] == nil {
		m.lockedBalances[addr][token] = uint256.NewInt(0)
	}
	m.lockedBalances[addr][token].Add(m.lockedBalances[addr][token], amount)
	m.SubTokenBalance(addr, token, amount)
}

func (m *TestMockLocker) UnlockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.lockedBalances[addr] != nil && m.lockedBalances[addr][token] != nil {
		m.lockedBalances[addr][token].Sub(m.lockedBalances[addr][token], amount)
		m.AddTokenBalance(addr, token, amount)
	}
}

func (m *TestMockLocker) ConsumeLockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	if m.lockedBalances[addr] != nil && m.lockedBalances[addr][token] != nil {
		m.lockedBalances[addr][token].Sub(m.lockedBalances[addr][token], amount)
	}
}

func TestLockStopOrder_QuoteMode(t *testing.T) {
	mockLocker := NewTestMockLocker()
	locker := wrapLocker(mockLocker, big.NewInt(0), big.NewInt(0))
	user := common.HexToAddress("0x1234")
	baseToken := "1"
	quoteToken := "2"
	
	// Fund the user
	mockLocker.AddTokenBalance(user, baseToken, uint256.NewInt(1000000))
	mockLocker.AddTokenBalance(user, quoteToken, uint256.NewInt(1000000))

	t.Run("BuyStopOrder_QuoteMode", func(t *testing.T) {
		// Create a BUY stop order in quote mode
		// Quantity represents quote tokens to spend
		order := &Order{
			UserID:    user.Hex(),
			Symbol:    baseToken + "/" + quoteToken,
			Side:      BUY,
			OrderType: LIMIT,
			OrderMode: QUOTE_MODE,
			Price:     uint256.NewInt(100), // Price in scaled units
			Quantity:  uint256.NewInt(500), // 500 quote tokens to spend
		}
		stopPrice := uint256.NewInt(110)

		// Lock the order
		locker.LockStopOrder(order, stopPrice)

		// Should lock 500 quote tokens (the quantity itself in quote mode)
		lockedQuote := mockLocker.GetLockedTokenBalance(user, quoteToken)
		assert.Equal(t, uint256.NewInt(500), lockedQuote, "should lock quantity as quote tokens")

		// Unlock the order
		locker.UnlockStopOrder(order, stopPrice)
		
		// Should have no locked tokens
		lockedQuote = mockLocker.GetLockedTokenBalance(user, quoteToken)
		assert.Equal(t, uint256.NewInt(0), lockedQuote, "should unlock all quote tokens")
	})

	t.Run("SellStopOrder_QuoteMode", func(t *testing.T) {
		// Create a SELL stop order in quote mode
		// Quantity represents quote tokens to receive
		price := uint256.NewInt(100)
		quoteQty := uint256.NewInt(500) // Want to receive 500 quote tokens
		// Need to lock: 500 / 100 = 5 base tokens (with scaling)
		expectedLocked := common.Uint256DivScaledDecimal(quoteQty, price)
		
		order := &Order{
			UserID:    user.Hex(),
			Symbol:    baseToken + "/" + quoteToken,
			Side:      SELL,
			OrderType: LIMIT,
			OrderMode: QUOTE_MODE,
			Price:     price,
			Quantity:  quoteQty,
		}
		stopPrice := uint256.NewInt(90)

		// Lock the order
		locker.LockStopOrder(order, stopPrice)

		// Should lock base tokens calculated from quote/price
		lockedBase := mockLocker.GetLockedTokenBalance(user, baseToken)
		assert.Equal(t, expectedLocked, lockedBase, "should lock calculated base tokens")

		// Unlock the order
		locker.UnlockStopOrder(order, stopPrice)
		
		// Should have no locked tokens
		lockedBase = mockLocker.GetLockedTokenBalance(user, baseToken)
		assert.Equal(t, uint256.NewInt(0), lockedBase, "should unlock all base tokens")
	})

	t.Run("MarketStopOrder_QuoteMode", func(t *testing.T) {
		// Test market stop order in quote mode
		stopPrice := uint256.NewInt(100)
		quoteQty := uint256.NewInt(500)
		
		// BUY market stop in quote mode
		buyOrder := &Order{
			UserID:    user.Hex(),
			Symbol:    baseToken + "/" + quoteToken,
			Side:      BUY,
			OrderType: MARKET,
			OrderMode: QUOTE_MODE,
			Price:     uint256.NewInt(0), // Market orders have no price
			Quantity:  quoteQty,           // 500 quote tokens to spend
		}

		locker.LockStopOrder(buyOrder, stopPrice)
		lockedQuote := mockLocker.GetLockedTokenBalance(user, quoteToken)
		assert.Equal(t, quoteQty, lockedQuote, "should lock quote quantity for market buy")
		locker.UnlockStopOrder(buyOrder, stopPrice)

		// SELL market stop in quote mode
		// Need to calculate base tokens: 500 / 100 = 5 (with scaling)
		expectedBase := common.Uint256DivScaledDecimal(quoteQty, stopPrice)
		
		sellOrder := &Order{
			UserID:    user.Hex(),
			Symbol:    baseToken + "/" + quoteToken,
			Side:      SELL,
			OrderType: MARKET,
			OrderMode: QUOTE_MODE,
			Price:     uint256.NewInt(0),
			Quantity:  quoteQty, // Want to receive 500 quote tokens
		}

		locker.LockStopOrder(sellOrder, stopPrice)
		lockedBase := mockLocker.GetLockedTokenBalance(user, baseToken)
		assert.Equal(t, expectedBase, lockedBase, "should lock calculated base for market sell")
		locker.UnlockStopOrder(sellOrder, stopPrice)
	})

	t.Run("BaseMode_Compatibility", func(t *testing.T) {
		// Ensure BASE_MODE orders still work correctly
		order := &Order{
			UserID:    user.Hex(),
			Symbol:    baseToken + "/" + quoteToken,
			Side:      BUY,
			OrderType: LIMIT,
			OrderMode: BASE_MODE, // Explicitly base mode
			Price:     uint256.NewInt(100),
			Quantity:  uint256.NewInt(10), // 10 base tokens
		}
		stopPrice := uint256.NewInt(110)

		// Lock the order
		locker.LockStopOrder(order, stopPrice)

		// Should lock price * quantity = 100 * 10 (with scaling)
		expectedLocked := common.Uint256MulScaledDecimal(order.Price, order.Quantity)
		lockedQuote := mockLocker.GetLockedTokenBalance(user, quoteToken)
		assert.Equal(t, expectedLocked, lockedQuote, "base mode should lock price*quantity")

		// Unlock
		locker.UnlockStopOrder(order, stopPrice)
		lockedQuote = mockLocker.GetLockedTokenBalance(user, quoteToken)
		assert.Equal(t, uint256.NewInt(0), lockedQuote, "should unlock all tokens")
	})
}