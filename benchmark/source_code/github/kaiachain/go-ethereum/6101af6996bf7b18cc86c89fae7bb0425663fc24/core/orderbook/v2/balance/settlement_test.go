package balance

import (
	"math/big"
	"sync"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockFeeRetriever implements types.FeeRetriever for testing
type mockFeeRetriever struct {
	makerFeeBP *big.Int
	takerFeeBP *big.Int
}

func (m *mockFeeRetriever) GetMarketFees(baseID, quoteID uint64) (*big.Int, *big.Int, error) {
	return m.makerFeeBP, m.takerFeeBP, nil
}

// defaultTestFeeRetriever returns a fee retriever with default test fees
func defaultTestFeeRetriever() types.FeeRetriever {
	// ApplyFee expects: 1 = 0.0001%, 1,000,000 = 100%
	// So for 0.1% we need 1000, for 0.3% we need 3000
	return &mockFeeRetriever{
		makerFeeBP: big.NewInt(1000), // 0.1% in the new scale
		takerFeeBP: big.NewInt(3000), // 0.3% in the new scale
	}
}

// noFeeRetriever returns a fee retriever with zero fees
func noFeeRetriever() types.FeeRetriever {
	return &mockFeeRetriever{
		makerFeeBP: big.NewInt(0),
		takerFeeBP: big.NewInt(0),
	}
}

// Test basic trade settlement
func TestManager_SettleTrade_Basic(t *testing.T) {
	stateDB := NewMockStateDB()
	// Create manager without fees for basic test
	config := types.BalanceManagerConfig{
		MaxMarketOrderPercent: 100,
		FeeConfig: types.FeeConfig{
			FeeCollector: common.Address{},
		},
	}
	manager := NewManagerWithConfig(config)
	manager.SetStateDB(stateDB)
	manager.SetFeeRetriever(noFeeRetriever())

	buyer := common.HexToAddress("0x1")
	seller := common.HexToAddress("0x2")

	// Setup initial balances
	// Use numeric token IDs: 2 for base token, 3 for quote token
	stateDB.SetTokenBalance(buyer, "3", e18(10000)) // Quote token (like USDT)
	stateDB.SetTokenBalance(seller, "2", e18(100))  // Base token (like WETH)

	// Lock balances for orders
	buyOrderID := "buy-order-1"
	sellOrderID := "sell-order-1"

	// Buyer locks quote token for buying base token
	err := manager.Lock(buyOrderID, buyer, "3", e18(2000)) // Lock quote token
	require.NoError(t, err)

	// Seller locks base token for selling
	err = manager.Lock(sellOrderID, seller, "2", e18(10)) // Lock base token
	require.NoError(t, err)

	// Create trade
	trade := &types.Trade{
		BuyOrderID:  types.OrderID(buyOrderID),
		SellOrderID: types.OrderID(sellOrderID),
		Symbol:      "2/3",    // base-quote format
		Price:       e18(100), // 100 USDT per WETH
		Quantity:    e18(5),   // 5 WETH
	}

	// Settle trade
	err = manager.SettleTrade(trade)
	assert.NoError(t, err)

	// Verify balances after settlement
	// GetTokenBalance returns available balance (total - locked)
	// Buyer: 10000 total - 500 consumed = 9500 total, 1500 still locked, 8000 available
	buyerQuote := stateDB.GetTokenBalance(buyer, "3") // Quote token balance
	buyerBase := stateDB.GetTokenBalance(buyer, "2")  // Base token balance
	assert.Equal(t, e18(8000), buyerQuote)            // Available: 9500 - 1500 locked
	assert.Equal(t, e18(5), buyerBase)                // Received 5 base tokens

	// Seller: 100 total - 5 consumed = 95 total, 5 still locked, 90 available
	sellerBase := stateDB.GetTokenBalance(seller, "2")  // Base token balance
	sellerQuote := stateDB.GetTokenBalance(seller, "3") // Quote token balance
	assert.Equal(t, e18(90), sellerBase)                // Available: 95 - 5 locked
	assert.Equal(t, e18(500), sellerQuote)              // Received 500 quote tokens

	// Verify locks are updated
	buyLock, exists := manager.GetLock(buyOrderID)
	assert.True(t, exists)
	assert.Equal(t, e18(1500), buyLock.Amount) // 2000 - 500

	sellLock, exists := manager.GetLock(sellOrderID)
	assert.True(t, exists)
	assert.Equal(t, e18(5), sellLock.Amount) // 10 - 5
}

// Test settlement with fees
func TestManager_SettleTrade_WithFees(t *testing.T) {
	stateDB := NewMockStateDB()

	// Create manager with fee config
	// Fees use new scale: 1 = 0.0001%, so 0.3% = 3000
	config := types.BalanceManagerConfig{
		MaxMarketOrderPercent: 100,
		FeeConfig: types.FeeConfig{
			FeeCollector: common.HexToAddress("0xFEE"),
		},
	}
	manager := NewManagerWithConfig(config)
	manager.SetStateDB(stateDB)
	manager.SetFeeRetriever(defaultTestFeeRetriever())

	buyer := common.HexToAddress("0x1")
	seller := common.HexToAddress("0x2")
	feeRecipient := config.FeeConfig.FeeCollector

	// Setup initial balances
	// Use numeric token IDs: 2 for base token, 3 for quote token
	stateDB.SetTokenBalance(buyer, "3", e18(10000)) // Quote token
	stateDB.SetTokenBalance(seller, "2", e18(100))  // Base token

	// Lock balances
	buyOrderID := "buy-order-1"
	sellOrderID := "sell-order-1"

	err := manager.Lock(buyOrderID, buyer, "3", e18(2000)) // Lock quote token
	require.NoError(t, err)

	err = manager.Lock(sellOrderID, seller, "2", e18(10)) // Lock base token
	require.NoError(t, err)

	// Create trade with taker/maker flags
	trade := &types.Trade{
		BuyOrderID:   types.OrderID(buyOrderID),
		SellOrderID:  types.OrderID(sellOrderID),
		Symbol:       "2-3", // base-quote format
		Price:        e18(100),
		Quantity:     e18(5),
		IsBuyerMaker: false, // Buyer is taker, seller is maker
	}

	// Settle trade with fees
	err = manager.SettleTrade(trade)
	assert.NoError(t, err)

	// Calculate expected fees
	// Taker fee (buyer): 5 base * 0.3% = 0.015 base
	// Maker fee (seller): 500 quote * 0.1% = 0.5 quote

	// Verify buyer balances (taker)
	// Pays: 500 quote consumed from lock
	// Receives: 5 base - 0.015 base fee = 4.985 base
	// Available quote: 10000 - 500 = 9500 total, 1500 still locked = 8000 available
	buyerQuote := stateDB.GetTokenBalance(buyer, "3") // Quote token
	buyerBase := stateDB.GetTokenBalance(buyer, "2")  // Base token
	assert.Equal(t, e18(8000), buyerQuote)            // Available: 9500 - 1500 locked

	// Calculate buyer fee: 5 * 10^18 * 3e15 / 10^18 = 15e15 = 0.015 * 10^18
	buyerFeeAmount := uint256.NewInt(15e15)
	expectedBuyerBase := new(uint256.Int).Sub(e18(5), buyerFeeAmount)
	assert.Equal(t, expectedBuyerBase, buyerBase) // 4.985 base tokens

	// Verify seller balances (maker)
	// Pays: 5 base consumed from lock
	// Receives: 500 quote - 0.5 quote fee = 499.5 quote
	// Available base: 100 - 5 = 95 total, 5 still locked = 90 available
	sellerBase := stateDB.GetTokenBalance(seller, "2")  // Base token
	sellerQuote := stateDB.GetTokenBalance(seller, "3") // Quote token
	assert.Equal(t, e18(90), sellerBase)                // Available: 95 - 5 locked

	// Calculate seller fee: 500 * 10^18 * 1e15 / 10^18 = 500e15 = 0.5 * 10^18
	sellerFeeAmount := uint256.NewInt(5e17) // 0.5 * 10^18
	expectedSellerQuote := new(uint256.Int).Sub(e18(500), sellerFeeAmount)
	assert.Equal(t, expectedSellerQuote, sellerQuote) // 499.5 quote tokens

	// Verify fee recipient received fees
	feeBase := stateDB.GetTokenBalance(feeRecipient, "2")  // Base token fees
	feeQuote := stateDB.GetTokenBalance(feeRecipient, "3") // Quote token fees

	assert.Equal(t, buyerFeeAmount, feeBase)   // 0.015 base tokens
	assert.Equal(t, sellerFeeAmount, feeQuote) // 0.5 quote tokens
}

// Test partial fill settlement
func TestManager_SettleTrade_PartialFill(t *testing.T) {
	stateDB := NewMockStateDB()
	// Create manager without fees
	config := types.BalanceManagerConfig{
		MaxMarketOrderPercent: 100,
		FeeConfig: types.FeeConfig{
			FeeCollector: common.Address{},
		},
	}
	manager := NewManagerWithConfig(config)
	manager.SetStateDB(stateDB)
	manager.SetFeeRetriever(noFeeRetriever())

	buyer := common.HexToAddress("0x1")
	seller := common.HexToAddress("0x2")

	stateDB.SetTokenBalance(buyer, "3", e18(10000)) // Quote token
	stateDB.SetTokenBalance(seller, "2", e18(100))  // Base token

	buyOrderID := "buy-order-1"
	sellOrderID := "sell-order-1"

	// Lock larger amounts for partial fills
	err := manager.Lock(buyOrderID, buyer, "3", e18(5000)) // Lock quote token
	require.NoError(t, err)

	err = manager.Lock(sellOrderID, seller, "2", e18(50)) // Lock base token
	require.NoError(t, err)

	// First partial fill
	trade1 := &types.Trade{
		BuyOrderID:  types.OrderID(buyOrderID),
		SellOrderID: types.OrderID(sellOrderID),
		Symbol:      "2/3",
		Price:       e18(100),
		Quantity:    e18(10), // Partial fill
	}

	err = manager.SettleTrade(trade1)
	assert.NoError(t, err)

	// Verify locks after first trade
	buyLock, _ := manager.GetLock(buyOrderID)
	assert.Equal(t, e18(4000), buyLock.Amount) // 5000 - 1000

	sellLock, _ := manager.GetLock(sellOrderID)
	assert.Equal(t, e18(40), sellLock.Amount) // 50 - 10

	// Second partial fill
	trade2 := &types.Trade{
		BuyOrderID:  types.OrderID(buyOrderID),
		SellOrderID: types.OrderID(sellOrderID),
		Symbol:      "2/3",
		Price:       e18(100),
		Quantity:    e18(20), // Another partial fill
	}

	err = manager.SettleTrade(trade2)
	assert.NoError(t, err)

	// Verify final locks
	buyLock, _ = manager.GetLock(buyOrderID)
	assert.Equal(t, e18(2000), buyLock.Amount) // 4000 - 2000

	sellLock, _ = manager.GetLock(sellOrderID)
	assert.Equal(t, e18(20), sellLock.Amount) // 40 - 20

	// Verify final balances (available = total - locked)
	// Buyer: 10000 - 3000 consumed = 7000 total, 2000 still locked = 5000 available
	buyerQuote := stateDB.GetTokenBalance(buyer, "3") // Quote token
	buyerBase := stateDB.GetTokenBalance(buyer, "2")  // Base token
	assert.Equal(t, e18(5000), buyerQuote)            // Available: 7000 - 2000 locked
	assert.Equal(t, e18(30), buyerBase)               // 10 + 20 received

	// Seller: 100 - 30 consumed = 70 total, 20 still locked = 50 available
	sellerBase := stateDB.GetTokenBalance(seller, "2")  // Base token
	sellerQuote := stateDB.GetTokenBalance(seller, "3") // Quote token
	assert.Equal(t, e18(50), sellerBase)                // Available: 70 - 20 locked
	assert.Equal(t, e18(3000), sellerQuote)             // 3000 quote tokens received
}

// Test settlement with fully consumed locks
func TestManager_SettleTrade_FullyConsumed(t *testing.T) {
	stateDB := NewMockStateDB()
	// Create manager without fees
	config := types.BalanceManagerConfig{
		MaxMarketOrderPercent: 100,
		FeeConfig: types.FeeConfig{
			FeeCollector: common.Address{},
		},
	}
	manager := NewManagerWithConfig(config)
	manager.SetStateDB(stateDB)
	manager.SetFeeRetriever(noFeeRetriever())

	buyer := common.HexToAddress("0x1")
	seller := common.HexToAddress("0x2")

	stateDB.SetTokenBalance(buyer, "3", e18(1000)) // Quote token
	stateDB.SetTokenBalance(seller, "2", e18(10))  // Base token

	buyOrderID := "buy-order-1"
	sellOrderID := "sell-order-1"

	// Lock exact amounts that will be fully consumed
	err := manager.Lock(buyOrderID, buyer, "3", e18(500)) // Lock quote token
	require.NoError(t, err)

	err = manager.Lock(sellOrderID, seller, "2", e18(5)) // Lock base token
	require.NoError(t, err)

	// Trade that fully consumes both locks
	trade := &types.Trade{
		BuyOrderID:  types.OrderID(buyOrderID),
		SellOrderID: types.OrderID(sellOrderID),
		Symbol:      "2/3",
		Price:       e18(100),
		Quantity:    e18(5), // Fully consumes both orders
	}

	err = manager.SettleTrade(trade)
	assert.NoError(t, err)

	// Both locks should be removed (fully consumed)
	_, exists := manager.GetLock(buyOrderID)
	assert.False(t, exists, "Buy lock should be removed after full consumption")

	_, exists = manager.GetLock(sellOrderID)
	assert.False(t, exists, "Sell lock should be removed after full consumption")
}

// Test settlement error cases
func TestManager_SettleTrade_Errors(t *testing.T) {
	stateDB := NewMockStateDB()
	// Create manager without fees
	config := types.BalanceManagerConfig{
		MaxMarketOrderPercent: 100,
		FeeConfig: types.FeeConfig{
			FeeCollector: common.Address{},
		},
	}
	manager := NewManagerWithConfig(config)
	manager.SetStateDB(stateDB)
	manager.SetFeeRetriever(noFeeRetriever())

	buyer := common.HexToAddress("0x1")
	seller := common.HexToAddress("0x2")

	stateDB.SetTokenBalance(buyer, "3", e18(10000)) // Quote token
	stateDB.SetTokenBalance(seller, "2", e18(100))  // Base token

	// Test with nil trade
	err := manager.SettleTrade(nil)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "trade cannot be nil")

	// Test with invalid quantity
	trade := &types.Trade{
		BuyOrderID:  "buy-1",
		SellOrderID: "sell-1",
		Symbol:      "2/3",
		Price:       e18(100),
		Quantity:    uint256.NewInt(0),
	}
	err = manager.SettleTrade(trade)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "invalid trade quantity")

	// Test with nil quantity
	trade.Quantity = nil
	err = manager.SettleTrade(trade)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "invalid trade quantity")

	// Test with missing buy order lock
	trade.Quantity = e18(5)
	err = manager.SettleTrade(trade)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "no lock found for buy order")

	// Create buy lock but not sell lock
	err = manager.Lock("buy-1", buyer, "3", e18(1000)) // Lock quote token
	require.NoError(t, err)

	err = manager.SettleTrade(trade)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "no lock found for sell order")

	// Create sell lock
	err = manager.Lock("sell-1", seller, "2", e18(10)) // Lock base token
	require.NoError(t, err)

	// Test with insufficient locked amount for buyer
	bigTrade := &types.Trade{
		BuyOrderID:  "buy-1",
		SellOrderID: "sell-1",
		Symbol:      "2/3",
		Price:       e18(100),
		Quantity:    e18(20), // Would need 2000 USDT, but only 1000 locked
	}
	err = manager.SettleTrade(bigTrade)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "insufficient locked balance for buyer")

	// Test with insufficient locked amount for seller
	// Need to make buyer have enough but seller not enough
	// Lock more for buyer first
	err = manager.CompleteOrder("buy-1")
	require.NoError(t, err)
	err = manager.Lock("buy-1", buyer, "3", e18(5000)) // Lock quote token
	require.NoError(t, err)

	smallTrade := &types.Trade{
		BuyOrderID:  "buy-1",
		SellOrderID: "sell-1",
		Symbol:      "2/3",
		Price:       e18(100),
		Quantity:    e18(15), // Would need 15 WETH, but only 10 locked
	}
	err = manager.SettleTrade(smallTrade)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "insufficient locked balance for seller")
}

// Test settlement with different price levels
func TestManager_SettleTrade_DifferentPrices(t *testing.T) {
	stateDB := NewMockStateDB()
	// Create manager without fees
	config := types.BalanceManagerConfig{
		MaxMarketOrderPercent: 100,
		FeeConfig: types.FeeConfig{
			FeeCollector: common.Address{},
		},
	}
	manager := NewManagerWithConfig(config)
	manager.SetStateDB(stateDB)
	manager.SetFeeRetriever(noFeeRetriever())

	buyer := common.HexToAddress("0x1")
	seller := common.HexToAddress("0x2")

	stateDB.SetTokenBalance(buyer, "3", e18(100000)) // Quote token
	stateDB.SetTokenBalance(seller, "2", e18(100))   // Base token

	// Lock balances
	err := manager.Lock("buy-1", buyer, "3", e18(50000)) // Lock quote token
	require.NoError(t, err)

	err = manager.Lock("sell-1", seller, "2", e18(50)) // Lock base token
	require.NoError(t, err)

	// Test trades at different prices
	testCases := []struct {
		name     string
		price    *uint256.Int
		quantity *uint256.Int
		expCost  *uint256.Int
	}{
		{
			name:     "Low price trade",
			price:    e18(50), // 50 USDT per WETH
			quantity: e18(2),
			expCost:  e18(100), // 2 * 50
		},
		{
			name:     "Medium price trade",
			price:    e18(100), // 100 USDT per WETH
			quantity: e18(5),
			expCost:  e18(500), // 5 * 100
		},
		{
			name:     "High price trade",
			price:    e18(200), // 200 USDT per WETH
			quantity: e18(10),
			expCost:  e18(2000), // 10 * 200
		},
		{
			name:     "Fractional price",
			price:    new(uint256.Int).Div(e18(150), uint256.NewInt(100)), // 1.5 USDT per WETH
			quantity: e18(4),
			expCost:  e18(6), // 4 * 1.5
		},
	}

	totalUSDTConsumed := uint256.NewInt(0)
	totalWETHConsumed := uint256.NewInt(0)

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			trade := &types.Trade{
				BuyOrderID:  "buy-1",
				SellOrderID: "sell-1",
				Symbol:      "2/3",
				Price:       tc.price,
				Quantity:    tc.quantity,
			}

			err := manager.SettleTrade(trade)
			assert.NoError(t, err)

			totalUSDTConsumed = new(uint256.Int).Add(totalUSDTConsumed, tc.expCost)
			totalWETHConsumed = new(uint256.Int).Add(totalWETHConsumed, tc.quantity)
		})
	}

	// Verify final lock amounts
	buyLock, _ := manager.GetLock("buy-1")
	expectedBuyLock := new(uint256.Int).Sub(e18(50000), totalUSDTConsumed)
	assert.Equal(t, expectedBuyLock, buyLock.Amount)

	sellLock, _ := manager.GetLock("sell-1")
	expectedSellLock := new(uint256.Int).Sub(e18(50), totalWETHConsumed)
	assert.Equal(t, expectedSellLock, sellLock.Amount)
}

// Test concurrent settlements
func TestManager_SettleTrade_Concurrent(t *testing.T) {
	stateDB := NewMockStateDB()
	// Create manager without fees
	config := types.BalanceManagerConfig{
		MaxMarketOrderPercent: 100,
		FeeConfig: types.FeeConfig{
			FeeCollector: common.Address{},
		},
	}
	manager := NewManagerWithConfig(config)
	manager.SetStateDB(stateDB)
	manager.SetFeeRetriever(noFeeRetriever())

	numTraders := 10

	// Setup traders with balances
	for i := 0; i < numTraders; i++ {
		trader := common.HexToAddress(string(rune('0' + i)))
		stateDB.SetTokenBalance(trader, "3", e18(10000)) // Quote token
		stateDB.SetTokenBalance(trader, "2", e18(100))   // Base token

		// Create buy and sell orders for each trader
		buyOrderID := string(rune('0'+i)) + "-buy"
		sellOrderID := string(rune('0'+i)) + "-sell"

		err := manager.Lock(buyOrderID, trader, "3", e18(5000)) // Lock quote token
		require.NoError(t, err)

		err = manager.Lock(sellOrderID, trader, "2", e18(50)) // Lock base token
		require.NoError(t, err)
	}

	var wg sync.WaitGroup

	// Execute concurrent trades
	for i := 0; i < numTraders-1; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()

			buyOrderID := string(rune('0'+idx)) + "-buy"
			sellOrderID := string(rune('0'+idx+1)) + "-sell" // Trade with next trader

			trade := &types.Trade{
				BuyOrderID:  types.OrderID(buyOrderID),
				SellOrderID: types.OrderID(sellOrderID),
				Symbol:      "2/3",
				Price:       e18(100),
				Quantity:    e18(1), // Small trades to avoid conflicts
			}

			err := manager.SettleTrade(trade)
			assert.NoError(t, err)
		}(i)
	}

	wg.Wait()

	// Verify all trades completed successfully
	for i := 0; i < numTraders-1; i++ {
		buyOrderID := string(rune('0'+i)) + "-buy"
		buyLock, exists := manager.GetLock(buyOrderID)
		assert.True(t, exists)
		assert.Equal(t, e18(4900), buyLock.Amount) // 5000 - 100

		sellOrderID := string(rune('0'+i+1)) + "-sell"
		sellLock, exists := manager.GetLock(sellOrderID)
		assert.True(t, exists)
		assert.Equal(t, e18(49), sellLock.Amount) // 50 - 1
	}
}
