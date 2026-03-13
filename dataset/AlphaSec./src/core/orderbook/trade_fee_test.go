package orderbook

import (
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTradeFeeInfo(t *testing.T) {
	t.Run("Trade struct contains fee information", func(t *testing.T) {
		trade := &Trade{
			BuyOrderID:    "buy1",
			SellOrderID:   "sell1",
			Price:         toWei("1000"),
			Quantity:      toWei("10"),
			Timestamp:     1234567890,
			BuyFeeTokenID: "1",
			BuyFeeAmount:  mustUint256("100000000000000000"), // 0.1 * 10^18
			SellFeeTokenID: "2",
			SellFeeAmount: toWei("100"),
			IsBuyerMaker:  false,
		}

		assert.Equal(t, "1", trade.BuyFeeTokenID)
		assert.Equal(t, mustUint256("100000000000000000"), trade.BuyFeeAmount)
		assert.Equal(t, "2", trade.SellFeeTokenID)
		assert.Equal(t, toWei("100"), trade.SellFeeAmount)
	})
}

func TestConsumeTradeBalanceWithFees(t *testing.T) {
	t.Run("ConsumeTradeBalance returns fee amounts", func(t *testing.T) {
		mockLocker := newMockLocker()
		makerFee := big.NewInt(25) // 0.000025%
		takerFee := big.NewInt(30) // 0.000030%
		locker := wrapLocker(mockLocker, makerFee, takerFee)
		buyer := common.HexToAddress("0x1234567890123456789012345678901234567890")
		seller := common.HexToAddress("0x2345678901234567890123456789012345678901")
		baseToken := "1"
		quoteToken := "2"
		
		// Setup initial balances
		locker.AddTokenBalance(buyer, quoteToken, toWei("10000"))
		locker.AddTokenBalance(seller, baseToken, toWei("100"))
		
		// Lock balances for trading
		locker.LockTokenBalance(buyer, quoteToken, toWei("1100"))
		locker.LockTokenBalance(seller, baseToken, toWei("10"))
		
		qty := toWei("10")
		cost := toWei("1000")
		
		// Execute trade
		buyerEarn, buyerFee, sellerEarn, sellerFee, err := locker.ConsumeTradeBalance(
			buyer, seller, baseToken, quoteToken, qty, cost, false,
		)
		
		require.NoError(t, err)
		assert.NotNil(t, buyerEarn)
		assert.NotNil(t, buyerFee)
		assert.NotNil(t, sellerEarn)
		assert.NotNil(t, sellerFee)
		
		// Verify fee amounts are returned
		assert.True(t, buyerFee.Sign() >= 0, "Buyer fee should be non-negative")
		assert.True(t, sellerFee.Sign() >= 0, "Seller fee should be non-negative")
		
		// Verify that earn amounts are adjusted for fees
		totalBuyerAmount := new(uint256.Int).Add(buyerEarn, buyerFee)
		assert.Equal(t, qty, totalBuyerAmount, "Buyer earn + fee should equal quantity")
		
		totalSellerAmount := new(uint256.Int).Add(sellerEarn, sellerFee)
		assert.Equal(t, cost, totalSellerAmount, "Seller earn + fee should equal cost")
	})

	t.Run("ConsumeTradeBalance with maker buyer", func(t *testing.T) {
		mockLocker := newMockLocker()
		makerFee := big.NewInt(25) // 0.000025%
		takerFee := big.NewInt(30) // 0.000030%
		locker := wrapLocker(mockLocker, makerFee, takerFee)
		buyer := common.HexToAddress("0x1234567890123456789012345678901234567890")
		seller := common.HexToAddress("0x2345678901234567890123456789012345678901")
		baseToken := "1"
		quoteToken := "2"
		
		// Setup initial balances
		locker.AddTokenBalance(buyer, quoteToken, toWei("10000"))
		locker.AddTokenBalance(seller, baseToken, toWei("100"))
		
		// Lock balances for trading
		locker.LockTokenBalance(buyer, quoteToken, toWei("1100"))
		locker.LockTokenBalance(seller, baseToken, toWei("10"))
		
		qty := toWei("10")
		cost := toWei("1000")
		
		// Execute trade with buyer as maker
		buyerEarn, buyerFee, sellerEarn, sellerFee, err := locker.ConsumeTradeBalance(
			buyer, seller, baseToken, quoteToken, qty, cost, true,
		)
		
		require.NoError(t, err)
		assert.NotNil(t, buyerEarn)
		assert.NotNil(t, buyerFee)
		assert.NotNil(t, sellerEarn)
		assert.NotNil(t, sellerFee)
		
		// Verify fee amounts are returned
		assert.True(t, buyerFee.Sign() >= 0, "Buyer fee should be non-negative")
		assert.True(t, sellerFee.Sign() >= 0, "Seller fee should be non-negative")
	})

	t.Run("ConsumeTradeBalance with insufficient buyer balance", func(t *testing.T) {
		mockLocker := newMockLocker()
		makerFee := big.NewInt(25) // 0.000025%
		takerFee := big.NewInt(30) // 0.000030%
		locker := wrapLocker(mockLocker, makerFee, takerFee)
		buyer := common.HexToAddress("0x1234567890123456789012345678901234567890")
		seller := common.HexToAddress("0x2345678901234567890123456789012345678901")
		baseToken := "1"
		quoteToken := "2"
		
		// Setup with insufficient buyer balance
		locker.AddTokenBalance(buyer, quoteToken, toWei("100"))
		locker.AddTokenBalance(seller, baseToken, toWei("100"))
		
		// Lock insufficient balance for buyer
		locker.LockTokenBalance(buyer, quoteToken, toWei("100"))
		locker.LockTokenBalance(seller, baseToken, toWei("10"))
		
		qty := toWei("10")
		cost := toWei("1000") // Cost exceeds locked balance
		
		// Execute trade - should fail
		buyerEarn, buyerFee, sellerEarn, sellerFee, err := locker.ConsumeTradeBalance(
			buyer, seller, baseToken, quoteToken, qty, cost, false,
		)
		
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "insufficient locked balance for buyer")
		assert.Nil(t, buyerEarn)
		assert.Nil(t, buyerFee)
		assert.Nil(t, sellerEarn)
		assert.Nil(t, sellerFee)
	})

	t.Run("ConsumeTradeBalance with insufficient seller balance", func(t *testing.T) {
		mockLocker := newMockLocker()
		makerFee := big.NewInt(25) // 0.000025%
		takerFee := big.NewInt(30) // 0.000030%
		locker := wrapLocker(mockLocker, makerFee, takerFee)
		buyer := common.HexToAddress("0x1234567890123456789012345678901234567890")
		seller := common.HexToAddress("0x2345678901234567890123456789012345678901")
		baseToken := "1"
		quoteToken := "2"
		
		// Setup with insufficient seller balance
		locker.AddTokenBalance(buyer, quoteToken, toWei("10000"))
		locker.AddTokenBalance(seller, baseToken, toWei("1"))
		
		// Lock balances
		locker.LockTokenBalance(buyer, quoteToken, toWei("1100"))
		locker.LockTokenBalance(seller, baseToken, toWei("1")) // Insufficient for qty
		
		qty := toWei("10") // Quantity exceeds seller's locked balance
		cost := toWei("1000")
		
		// Execute trade - should fail
		buyerEarn, buyerFee, sellerEarn, sellerFee, err := locker.ConsumeTradeBalance(
			buyer, seller, baseToken, quoteToken, qty, cost, false,
		)
		
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "insufficient locked balance for seller")
		assert.Nil(t, buyerEarn)
		assert.Nil(t, buyerFee)
		assert.Nil(t, sellerEarn)
		assert.Nil(t, sellerFee)
	})
}

func TestTradeMatcherFeePopulation(t *testing.T) {
	t.Run("TradeMatcher populates fee info in Trade", func(t *testing.T) {
		// Create a symbol engine with mock dependencies
		engine := NewSymbolEngine("1/2")
		mockLocker := newMockLocker()
		makerFee := big.NewInt(25) // 0.000025%
		takerFee := big.NewInt(30) // 0.000030%
		locker := wrapLocker(mockLocker, makerFee, takerFee)
		matcher := NewTradeMatcher("1/2")
		
		// Create buyer and seller addresses
		buyer := common.HexToAddress("0x1234567890123456789012345678901234567890")
		seller := common.HexToAddress("0x2345678901234567890123456789012345678901")
		
		// Setup initial balances
		locker.AddTokenBalance(buyer, "2", toWei("10000"))
		locker.AddTokenBalance(seller, "1", toWei("100"))
		
		// Create buy and sell orders
		buyOrder := &Order{
			OrderID:   "buy1",
			UserID:    buyer.Hex(),
			Symbol:    "1/2",
			Price:     toWei("1000"),
			Quantity:  toWei("10"),
			OrigQty:   toWei("10"),
			Side:      BUY,
			OrderType: LIMIT,
		}
		
		sellOrder := &Order{
			OrderID:   "sell1",
			UserID:    seller.Hex(),
			Symbol:    "1/2",
			Price:     toWei("1000"),
			Quantity:  toWei("10"),
			OrigQty:   toWei("10"),
			Side:      SELL,
			OrderType: LIMIT,
		}
		
		// Lock required balances
		locker.LockTokenBalance(buyer, "2", toWei("10000"))
		locker.LockTokenBalance(seller, "1", toWei("10"))
		
		// Create a trade
		trade := &Trade{
			Symbol:       "1/2",
			BuyOrderID:   buyOrder.OrderID,
			SellOrderID:  sellOrder.OrderID,
			Price:        toWei("1000"),
			Quantity:     toWei("10"),
			Timestamp:    1234567890,
			IsBuyerMaker: false,
		}
		
		// Process the trade using processSingleTrade
		// Add orders to engine's userbook first
		engine.userBook.AddOrder(buyOrder)
		engine.userBook.AddOrder(sellOrder)
		
		// Process the trade
		matcher.processSingleTrade(trade, engine, locker)
		
		// Verify fee information is populated
		assert.NotEmpty(t, trade.BuyFeeTokenID, "Buy fee token ID should be populated")
		assert.NotNil(t, trade.BuyFeeAmount, "Buy fee amount should be populated")
		assert.NotEmpty(t, trade.SellFeeTokenID, "Sell fee token ID should be populated")
		assert.NotNil(t, trade.SellFeeAmount, "Sell fee amount should be populated")
		
		// Verify fee token IDs match expected tokens
		assert.Equal(t, "1", trade.BuyFeeTokenID, "Buyer receives base tokens, fee in base")
		assert.Equal(t, "2", trade.SellFeeTokenID, "Seller receives quote tokens, fee in quote")
	})

	t.Run("TradeMatcher handles multiple trades with fees", func(t *testing.T) {
		engine := NewSymbolEngine("1/2")
		mockLocker := newMockLocker()
		makerFee := big.NewInt(25) // 0.000025%
		takerFee := big.NewInt(30) // 0.000030%
		locker := wrapLocker(mockLocker, makerFee, takerFee)
		matcher := NewTradeMatcher("1/2")
		
		// Create multiple buyers and sellers
		buyer1 := common.HexToAddress("0x1111111111111111111111111111111111111111")
		buyer2 := common.HexToAddress("0x2222222222222222222222222222222222222222")
		seller1 := common.HexToAddress("0x3333333333333333333333333333333333333333")
		seller2 := common.HexToAddress("0x4444444444444444444444444444444444444444")
		
		// Setup balances for all participants
		locker.AddTokenBalance(buyer1, "2", toWei("10000"))
		locker.AddTokenBalance(buyer2, "2", toWei("10000"))
		locker.AddTokenBalance(seller1, "1", toWei("100"))
		locker.AddTokenBalance(seller2, "1", toWei("100"))
		
		// Lock balances
		locker.LockTokenBalance(buyer1, "2", toWei("5000"))
		locker.LockTokenBalance(buyer2, "2", toWei("5000"))
		locker.LockTokenBalance(seller1, "1", toWei("50"))
		locker.LockTokenBalance(seller2, "1", toWei("50"))
		
		// Create multiple trades
		trades := []*Trade{
			{
				Symbol:       "1/2",
				BuyOrderID:   "buy1",
				SellOrderID:  "sell1",
				Price:        toWei("1000"),
				Quantity:     toWei("5"),
				Timestamp:    1234567890,
				IsBuyerMaker: false,
			},
			{
				Symbol:       "1/2",
				BuyOrderID:   "buy2",
				SellOrderID:  "sell2",
				Price:        toWei("1100"),
				Quantity:     toWei("3"),
				Timestamp:    1234567891,
				IsBuyerMaker: true,
			},
		}
		
		// Create orders for the trades
		buyOrder1 := &Order{
			OrderID:  "buy1",
			UserID:   buyer1.Hex(),
			Symbol:   "1/2",
			Price:    toWei("1000"),
			Quantity: toWei("5"),
			OrigQty:  toWei("5"),
			Side:     BUY,
		}
		sellOrder1 := &Order{
			OrderID:  "sell1",
			UserID:   seller1.Hex(),
			Symbol:   "1/2",
			Price:    toWei("1000"),
			Quantity: toWei("5"),
			OrigQty:  toWei("5"),
			Side:     SELL,
		}
		buyOrder2 := &Order{
			OrderID:  "buy2",
			UserID:   buyer2.Hex(),
			Symbol:   "1/2",
			Price:    toWei("1100"),
			Quantity: toWei("3"),
			OrigQty:  toWei("3"),
			Side:     BUY,
		}
		sellOrder2 := &Order{
			OrderID:  "sell2",
			UserID:   seller2.Hex(),
			Symbol:   "1/2",
			Price:    toWei("1100"),
			Quantity: toWei("3"),
			OrigQty:  toWei("3"),
			Side:     SELL,
		}
		
		// Add orders to engine's userbook
		engine.userBook.AddOrder(buyOrder1)
		engine.userBook.AddOrder(sellOrder1)
		engine.userBook.AddOrder(buyOrder2)
		engine.userBook.AddOrder(sellOrder2)
		
		// Process all trades
		for _, trade := range trades {
			matcher.processSingleTrade(trade, engine, locker)
		}
		
		// Verify all trades have fee information populated
		for i, trade := range trades {
			assert.NotEmpty(t, trade.BuyFeeTokenID, "Trade %d: Buy fee token ID should be populated", i)
			assert.NotNil(t, trade.BuyFeeAmount, "Trade %d: Buy fee amount should be populated", i)
			assert.NotEmpty(t, trade.SellFeeTokenID, "Trade %d: Sell fee token ID should be populated", i)
			assert.NotNil(t, trade.SellFeeAmount, "Trade %d: Sell fee amount should be populated", i)
			
			// Verify token IDs
			assert.Equal(t, "1", trade.BuyFeeTokenID, "Trade %d: Buyer fee should be in base token", i)
			assert.Equal(t, "2", trade.SellFeeTokenID, "Trade %d: Seller fee should be in quote token", i)
		}
	})
}

func TestFeeCalculationAccuracy(t *testing.T) {
	t.Run("Fee amounts are correctly calculated", func(t *testing.T) {
		mockLocker := newMockLocker()
		makerFee := big.NewInt(25) // 0.000025%
		takerFee := big.NewInt(30) // 0.000030%
		locker := wrapLocker(mockLocker, makerFee, takerFee)
		buyer := common.HexToAddress("0x1234567890123456789012345678901234567890")
		seller := common.HexToAddress("0x2345678901234567890123456789012345678901")
		baseToken := "1"
		quoteToken := "2"
		
		// Setup large balances to avoid insufficiency
		locker.AddTokenBalance(buyer, quoteToken, toWei("1000000"))
		locker.AddTokenBalance(seller, baseToken, toWei("10000"))
		
		// Lock balances
		locker.LockTokenBalance(buyer, quoteToken, toWei("100000"))
		locker.LockTokenBalance(seller, baseToken, toWei("1000"))
		
		// Test with specific quantities
		testCases := []struct {
			name         string
			qty          *uint256.Int
			cost         *uint256.Int
			isBuyerMaker bool
		}{
			{
				name:         "Small trade",
				qty:          toWei("1"),
				cost:         toWei("100"),
				isBuyerMaker: false,
			},
			{
				name:         "Medium trade",
				qty:          toWei("10"),
				cost:         toWei("1000"),
				isBuyerMaker: true,
			},
			{
				name:         "Large trade",
				qty:          toWei("100"),
				cost:         toWei("10000"),
				isBuyerMaker: false,
			},
		}
		
		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				buyerEarn, buyerFee, sellerEarn, sellerFee, err := locker.ConsumeTradeBalance(
					buyer, seller, baseToken, quoteToken, tc.qty, tc.cost, tc.isBuyerMaker,
				)
				
				require.NoError(t, err)
				
				// Verify fees are calculated
				assert.NotNil(t, buyerFee, "Buyer fee should not be nil")
				assert.NotNil(t, sellerFee, "Seller fee should not be nil")
				
				// Verify total amounts match expected values
				totalBuyer := new(uint256.Int).Add(buyerEarn, buyerFee)
				totalSeller := new(uint256.Int).Add(sellerEarn, sellerFee)
				
				assert.Equal(t, tc.qty, totalBuyer, "Total buyer amount should equal quantity")
				assert.Equal(t, tc.cost, totalSeller, "Total seller amount should equal cost")
			})
		}
	})
}