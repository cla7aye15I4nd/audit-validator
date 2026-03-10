package balance

import (
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/mocks"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockTestFeeRetriever implements types.FeeRetriever for testing
type mockTestFeeRetriever struct{}

func (m *mockTestFeeRetriever) GetMarketFees(base, quote uint64) (*big.Int, *big.Int, error) {
	// ApplyFee expects: 1 = 0.0001%, 1,000,000 = 100%
	// 0.1% maker = 1000, 0.3% taker = 3000
	return big.NewInt(1000), big.NewInt(3000), nil
}

func TestSettleTrade_TPSLLockInheritance(t *testing.T) {
	tests := []struct {
		name                 string
		buyOrderHasTPSL      bool
		sellOrderHasTPSL     bool
		buyOrderFullyFilled  bool
		sellOrderFullyFilled bool
		expectedBuyerLock    bool
		expectedSellerLock   bool
	}{
		{
			name:                 "Both orders have TPSL and fully filled",
			buyOrderHasTPSL:      true,
			sellOrderHasTPSL:     true,
			buyOrderFullyFilled:  true,
			sellOrderFullyFilled: true,
			expectedBuyerLock:    false, // TPSL locks now created in symbol engine, not settlement
			expectedSellerLock:   false, // TPSL locks now created in symbol engine, not settlement
		},
		{
			name:                 "Only buyer has TPSL and fully filled",
			buyOrderHasTPSL:      true,
			sellOrderHasTPSL:     false,
			buyOrderFullyFilled:  true,
			sellOrderFullyFilled: true,
			expectedBuyerLock:    false, // TPSL locks now created in symbol engine, not settlement
			expectedSellerLock:   false,
		},
		{
			name:                 "Buyer has TPSL but not fully filled",
			buyOrderHasTPSL:      true,
			sellOrderHasTPSL:     false,
			buyOrderFullyFilled:  false,
			sellOrderFullyFilled: true,
			expectedBuyerLock:    false,
			expectedSellerLock:   false,
		},
		{
			name:                 "No TPSL on either order",
			buyOrderHasTPSL:      false,
			sellOrderHasTPSL:     false,
			buyOrderFullyFilled:  true,
			sellOrderFullyFilled: true,
			expectedBuyerLock:    false,
			expectedSellerLock:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup
			stateDB := mocks.NewMockStateDB()
			manager := NewManager()
			manager.SetStateDB(stateDB)
			manager.SetFeeRetriever(&mockTestFeeRetriever{})

			buyer := common.HexToAddress("0x1234")
			seller := common.HexToAddress("0x5678")

			// Setup initial balances and locks (using 18 decimals)
			baseAmount := uint256.MustFromDecimal("500000000000000000")      // 0.5 ETH (18 decimals)
			price := uint256.MustFromDecimal("2000000000000000000")          // 2000 USDT per ETH
			quoteAmount := common.Uint256MulScaledDecimal(price, baseAmount) // Calculate cost: 1000 USDT

			// Create initial locks for the orders
			buyOrderID := "BUY_ORDER_1"
			sellOrderID := "SELL_ORDER_1"

			// Buyer locks quote token (token 3)
			stateDB.SetTokenBalance(buyer, "3", quoteAmount)
			stateDB.LockTokenBalance(buyer, "3", quoteAmount)
			manager.locks[buyOrderID] = &types.LockInfo{
				OrderID:  buyOrderID,
				UserAddr: buyer,
				Token:    "3",
				Amount:   quoteAmount,
			}

			// Seller locks base token (token 2)
			stateDB.SetTokenBalance(seller, "2", baseAmount)
			stateDB.LockTokenBalance(seller, "2", baseAmount)
			manager.locks[sellOrderID] = &types.LockInfo{
				OrderID:  sellOrderID,
				UserAddr: seller,
				Token:    "2",
				Amount:   baseAmount,
			}

			// Create trade
			trade := &types.Trade{
				TradeID:              "TRADE_1",
				Symbol:               "2/3",
				Price:                price,
				Quantity:             baseAmount,
				BuyOrderID:           types.OrderID(buyOrderID),
				SellOrderID:          types.OrderID(sellOrderID),
				IsBuyerMaker:         false,
				BuyOrderFullyFilled:  tt.buyOrderFullyFilled,
				SellOrderFullyFilled: tt.sellOrderFullyFilled,
				BuyOrderHasTPSL:      tt.buyOrderHasTPSL,
				SellOrderHasTPSL:     tt.sellOrderHasTPSL,
			}

			// Execute trade settlement
			err := manager.SettleTrade(trade)
			require.NoError(t, err)

			// Verify TPSL locks
			buyerTPSLLockID := buyOrderID + "_TPSL"
			sellerTPSLLockID := sellOrderID + "_TPSL"

			// Check buyer TPSL lock
			buyerLock, buyerLockExists := manager.locks[buyerTPSLLockID]
			assert.Equal(t, tt.expectedBuyerLock, buyerLockExists, "Buyer TPSL lock existence mismatch")
			if tt.expectedBuyerLock {
				assert.NotNil(t, buyerLock)
				assert.Equal(t, "2", buyerLock.Token) // Buyer receives base token (2)
				assert.Equal(t, buyer, buyerLock.UserAddr)
				// Note: Amount should be buyerReceives (baseAmount minus fees)
			}

			// Check seller TPSL lock
			sellerLock, sellerLockExists := manager.locks[sellerTPSLLockID]
			assert.Equal(t, tt.expectedSellerLock, sellerLockExists, "Seller TPSL lock existence mismatch")
			if tt.expectedSellerLock {
				assert.NotNil(t, sellerLock)
				assert.Equal(t, "3", sellerLock.Token) // Seller receives quote token (3)
				assert.Equal(t, seller, sellerLock.UserAddr)
				// Note: Amount should be sellerReceives (quoteAmount minus fees)
			}
		})
	}
}

func TestSettleTrade_TPSLLockAmount(t *testing.T) {
	// Setup
	stateDB := mocks.NewMockStateDB()
	config := types.BalanceManagerConfig{
		FeeConfig: types.FeeConfig{
			FeeCollector: common.HexToAddress("0xFEE"),
		},
	}
	manager := NewManagerWithConfig(config)
	manager.SetStateDB(stateDB)
	manager.SetFeeRetriever(&mockTestFeeRetriever{})

	buyer := common.HexToAddress("0x1234")
	seller := common.HexToAddress("0x5678")

	// Trade amounts (using 18 decimals)
	oneETH := uint256.MustFromDecimal("1000000000000000000") // 1 ETH
	price := uint256.MustFromDecimal("2000000000000000000")  // 2000 USDT per ETH
	cost := common.Uint256MulScaledDecimal(price, oneETH)    // 2000 USDT

	// Create initial locks
	buyOrderID := "BUY_ORDER_1"
	sellOrderID := "SELL_ORDER_1"

	// Buyer locks quote token (3)
	stateDB.SetTokenBalance(buyer, "3", cost)
	stateDB.LockTokenBalance(buyer, "3", cost)
	manager.locks[buyOrderID] = &types.LockInfo{
		OrderID:  buyOrderID,
		UserAddr: buyer,
		Token:    "3",
		Amount:   cost,
	}

	// Seller locks base token (2)
	stateDB.SetTokenBalance(seller, "2", oneETH)
	stateDB.LockTokenBalance(seller, "2", oneETH)
	manager.locks[sellOrderID] = &types.LockInfo{
		OrderID:  sellOrderID,
		UserAddr: seller,
		Token:    "2",
		Amount:   oneETH,
	}

	// Create trade with TPSL
	trade := &types.Trade{
		TradeID:              "TRADE_1",
		Symbol:               "2/3",
		Price:                price,
		Quantity:             oneETH,
		BuyOrderID:           types.OrderID(buyOrderID),
		SellOrderID:          types.OrderID(sellOrderID),
		IsBuyerMaker:         false, // Buyer is taker
		BuyOrderFullyFilled:  true,
		SellOrderFullyFilled: true,
		BuyOrderHasTPSL:      true,
		SellOrderHasTPSL:     true,
	}

	// Execute settlement
	err := manager.SettleTrade(trade)
	require.NoError(t, err)

	// TPSL locks are NOT created during settlement anymore
	// They are created when the actual TPSL order is placed
	// So we verify that no TPSL locks exist after settlement
	buyerTPSLLock := manager.locks[buyOrderID+"_TPSL"]
	assert.Nil(t, buyerTPSLLock, "TPSL lock should not be created during settlement")

	sellerTPSLLock := manager.locks[sellOrderID+"_TPSL"]
	assert.Nil(t, sellerTPSLLock, "TPSL lock should not be created during settlement")
}
