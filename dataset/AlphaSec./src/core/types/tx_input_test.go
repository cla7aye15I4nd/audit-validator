package types

import (
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
)

// Helper function to scale a decimal value to 18 decimals
// e.g., scaleUp(2.5) returns 2500000000000000000 (2.5 * 10^18)
func scaleUp(value float64) *big.Int {
	// Multiply by 10^18
	scaled := new(big.Float).SetFloat64(value)
	scaling := new(big.Float).SetFloat64(1e18)
	scaled.Mul(scaled, scaling)

	result, _ := scaled.Int(nil)
	return result
}

// Helper function to create uint256 from scaled value
func scaleUpUint256(value float64) *uint256.Int {
	return uint256.MustFromBig(scaleUp(value))
}

type MockMarketChecker struct{}

func (m *MockMarketChecker) ContainsMarket(base, quote uint64) (bool, error) { return true, nil }

func NewMockMarketChecker() MarketChecker { return &MockMarketChecker{} }

type MockDispatcher struct{}

func (m *MockDispatcher) GetSymbols() []string                           { return nil }
func (m *MockDispatcher) GetEngines() map[string]*orderbook.SymbolEngine { return nil }
func (m *MockDispatcher) GetOrderRouting() []*orderbook.OrderRoute       { return nil }
func (m *MockDispatcher) AggregateL2DepthUpdate(time int64, blockNum string, prefetch bool) []*orderbook.DepthUpdate {
	return nil
}
func (m *MockDispatcher) DispatchReq(req *orderbook.Request)                       {}
func (m *MockDispatcher) GetOrder(orderId string) (*orderbook.Order, bool)         { return nil, true }
func (m *MockDispatcher) GetStopOrder(orderId string) (*orderbook.StopOrder, bool) { return nil, true }
func (m *MockDispatcher) MakeSnapshot(blockNumber uint64, prefetch bool)           {}
func (m *MockDispatcher) GetSnapshot() []*orderbook.Aggregated                     { return nil }
func (m *MockDispatcher) GetSnapshotFromLvl3() []*orderbook.Aggregated             { return nil }

type MockBalanceGetter struct {
	balances map[string]*uint256.Int
}

func NewMockBalanceGetter() *MockBalanceGetter {
	return &MockBalanceGetter{
		balances: make(map[string]*uint256.Int),
	}
}

func (m *MockBalanceGetter) GetBalance(user common.Address) *uint256.Int {
	return nil
}

func (m *MockBalanceGetter) GetTokenBalance(user common.Address, token string) *uint256.Int {
	if bal, ok := m.balances[token]; ok {
		return bal
	}
	return uint256.NewInt(0)
}

func (m *MockBalanceGetter) GetLockedTokenBalance(user common.Address, token string) *uint256.Int {
	return nil
}

func (m *MockBalanceGetter) GetSessions(addr common.Address) []SessionCommandBytes {
	return nil
}

func (m *MockBalanceGetter) Fund(token string, amount *uint256.Int) {
	if _, ok := m.balances[token]; !ok {
		m.balances[token] = uint256.NewInt(0)
	}
	m.balances[token].Add(m.balances[token], amount)
}

func TestGetInputTxType(t *testing.T) {
	assert.Equal(t, InvalidDexCommand, GetDexCommandType([]byte{}))
	assert.Equal(t, DexCommandTokenTransfer, GetDexCommandType([]byte{DexCommandTokenTransfer}))
	assert.Equal(t, DexCommandNew, GetDexCommandType([]byte{DexCommandNew}))
	assert.Equal(t, DexCommandCancel, GetDexCommandType([]byte{DexCommandCancel}))
}

func TestTokenTransferTxEncodeDecode(t *testing.T) {
	original := &TokenTransferContext{
		L1Owner: common.HexToAddress("0xabc"),
		To:      common.HexToAddress("0xdef"),
		Token:   "BTC",
		Value:   big.NewInt(1000),
	}

	data, err := original.Serialize()
	assert.NoError(t, err)

	var decoded TokenTransferContext
	err = decoded.Deserialize(data)
	assert.NoError(t, err)
	assert.Equal(t, original.L1Owner, decoded.L1Owner)
	assert.Equal(t, original.To, decoded.To)
	assert.Equal(t, original.Token, decoded.Token)
	assert.Equal(t, true, original.Value.Cmp(decoded.Value) == 0)
}

func TestTokenTransferTxValidate(t *testing.T) {
	valid := &TokenTransferContext{
		L1Owner: common.HexToAddress("0x1"),
		To:      common.HexToAddress("0x2"),
		Token:   "ETH",
		Value:   big.NewInt(100),
	}
	mockdb := NewMockBalanceGetter()
	mockdb.Fund("ETH", uint256.NewInt(1000))

	mockChecker := NewMockMarketChecker()

	assert.NoError(t, valid.validate(common.Address{}, mockdb, nil, mockChecker))

	invalid := &TokenTransferContext{}
	assert.Error(t, invalid.validate(common.Address{}, nil, nil, mockChecker))
}

func TestOrderTxEncodeDecode_WithoutTPSL(t *testing.T) {
	original := &OrderContext{
		L1Owner:    common.HexToAddress("0xabc"),
		BaseToken:  "KAIA",
		QuoteToken: "USDT",
		Side:       BUY,
		Price:      big.NewInt(1000),
		Quantity:   big.NewInt(10),
		OrderType:  LIMIT,
	}

	data, err := original.Serialize()
	assert.NoError(t, err)

	var decoded OrderContext
	err = decoded.Deserialize(data)
	assert.NoError(t, err)
	assert.Equal(t, true, original.Price.Cmp(decoded.Price) == 0)
	assert.Equal(t, true, original.Quantity.Cmp(decoded.Quantity) == 0)
	assert.Equal(t, original.L1Owner, decoded.L1Owner)
	assert.Equal(t, original.BaseToken, decoded.BaseToken)
	assert.Equal(t, original.QuoteToken, decoded.QuoteToken)
	assert.Equal(t, original.Side, decoded.Side)
	assert.Equal(t, original.OrderType, decoded.OrderType)
	assert.Equal(t, uint8(0), decoded.OrderMode) // Should default to BASE_MODE (0)
}

func TestOrderTxEncodeDecode_WithTPSL_SLLimit(t *testing.T) {
	original := &OrderContext{
		L1Owner:    common.HexToAddress("0xabc"),
		BaseToken:  "KAIA",
		QuoteToken: "USDT",
		Side:       BUY,
		Price:      big.NewInt(1000),
		Quantity:   big.NewInt(10),
		OrderType:  LIMIT,
		TPSL: &TPSLContext{
			TPLimit:   big.NewInt(1100),
			SLTrigger: big.NewInt(900),
			SLLimit:   big.NewInt(850),
		},
	}

	data, err := original.Serialize()
	assert.NoError(t, err)

	var decoded OrderContext
	err = decoded.Deserialize(data)
	assert.NoError(t, err)
	assert.Equal(t, true, original.Price.Cmp(decoded.Price) == 0)
	assert.Equal(t, true, original.Quantity.Cmp(decoded.Quantity) == 0)
	assert.Equal(t, original.L1Owner, decoded.L1Owner)
	assert.Equal(t, original.BaseToken, decoded.BaseToken)
	assert.Equal(t, original.QuoteToken, decoded.QuoteToken)
	assert.Equal(t, original.Side, decoded.Side)
	assert.Equal(t, original.OrderType, decoded.OrderType)
	assert.Equal(t, original.TPSL.TPLimit, decoded.TPSL.TPLimit)
	assert.Equal(t, original.TPSL.SLTrigger, decoded.TPSL.SLTrigger)
	assert.Equal(t, original.TPSL.SLLimit, decoded.TPSL.SLLimit)
	assert.Equal(t, uint8(0), decoded.OrderMode) // Should default to BASE_MODE (0)
}

func TestOrderTxEncodeDecode_WithTPSL_SLMarket(t *testing.T) {
	original := &OrderContext{
		L1Owner:    common.HexToAddress("0xabc"),
		BaseToken:  "KAIA",
		QuoteToken: "USDT",
		Side:       BUY,
		Price:      big.NewInt(1000),
		Quantity:   big.NewInt(10),
		OrderType:  LIMIT,
		TPSL: &TPSLContext{
			TPLimit:   big.NewInt(1100),
			SLTrigger: big.NewInt(900),
		},
	}

	data, err := original.Serialize()
	assert.NoError(t, err)

	var decoded OrderContext
	err = decoded.Deserialize(data)
	assert.NoError(t, err)
	assert.Equal(t, true, original.Price.Cmp(decoded.Price) == 0)
	assert.Equal(t, true, original.Quantity.Cmp(decoded.Quantity) == 0)
	assert.Equal(t, original.L1Owner, decoded.L1Owner)
	assert.Equal(t, original.BaseToken, decoded.BaseToken)
	assert.Equal(t, original.QuoteToken, decoded.QuoteToken)
	assert.Equal(t, original.Side, decoded.Side)
	assert.Equal(t, original.OrderType, decoded.OrderType)
	assert.Equal(t, original.TPSL.TPLimit, decoded.TPSL.TPLimit)
	assert.Equal(t, original.TPSL.SLTrigger, decoded.TPSL.SLTrigger)
	assert.Equal(t, uint8(0), decoded.OrderMode) // Should default to BASE_MODE (0)
}

func TestOrderTxValidate(t *testing.T) {
	valid := &OrderContext{
		L1Owner:    common.HexToAddress("0x1"),
		BaseToken:  "1",
		QuoteToken: "2",
		Side:       BUY,
		Price:      big.NewInt(1),
		Quantity:   big.NewInt(1),
		OrderType:  LIMIT,
	}

	mockdb := NewMockBalanceGetter()
	mockdb.Fund("2", uint256.NewInt(1000))
	assert.NoError(t, valid.validate(common.Address{}, mockdb, nil, nil))

	invalid := &OrderContext{}
	assert.Error(t, invalid.validate(common.Address{}, nil, nil, nil))
}

func TestCancelTxEncodeDecode(t *testing.T) {
	original := &CancelContext{
		L1Owner: common.HexToAddress("0xabc"),
		OrderId: common.HexToHash("0x123"),
	}

	data, err := original.Serialize()
	assert.NoError(t, err)

	var decoded CancelContext
	err = decoded.Deserialize(data)
	assert.NoError(t, err)
	assert.Equal(t, original.L1Owner, decoded.L1Owner)
	assert.Equal(t, original.OrderId, decoded.OrderId)
}

func TestCancelTxValidate(t *testing.T) {
	valid := &CancelContext{
		L1Owner: common.HexToAddress("0x1"),
		OrderId: common.HexToHash("0x123"),
	}
	mockDispatcher := &MockDispatcher{}
	assert.NoError(t, valid.validate(common.Address{}, nil, mockDispatcher, nil))

	invalid := &CancelContext{}
	assert.Error(t, invalid.validate(common.Address{}, nil, mockDispatcher, nil))
}

func TestOrderContext_QuoteMode(t *testing.T) {
	// Test limit order in quote mode converts to base mode
	quoteLimitOrder := &OrderContext{
		L1Owner:    common.HexToAddress("0xabc"),
		BaseToken:  "1",
		QuoteToken: "2",
		Side:       BUY,
		Price:      scaleUp(2.0),   // 2.0 USDT per token
		Quantity:   scaleUp(100.0), // 100 USDT to spend (quote mode)
		OrderType:  LIMIT,
		OrderMode:  1, // QUOTE_MODE
	}

	order := quoteLimitOrder.ToOrder(common.HexToHash("0x123"))
	assert.Equal(t, orderbook.BASE_MODE, order.OrderMode)
	// Quantity should be converted: 100 / 2.0 = 50 base tokens
	assert.Equal(t, scaleUpUint256(50.0).String(), order.Quantity.String())
	assert.Equal(t, scaleUpUint256(50.0).String(), order.OrigQty.String())

	// Test market order in quote mode stays in quote mode
	quoteMarketOrder := &OrderContext{
		L1Owner:    common.HexToAddress("0xabc"),
		BaseToken:  "1",
		QuoteToken: "2",
		Side:       BUY,
		Price:      big.NewInt(0),  // Market orders have no price
		Quantity:   scaleUp(100.0), // 100 USDT to spend
		OrderType:  MARKET,
		OrderMode:  1, // QUOTE_MODE
	}

	marketOrder := quoteMarketOrder.ToOrder(common.HexToHash("0x456"))
	assert.Equal(t, orderbook.QUOTE_MODE, marketOrder.OrderMode)
	// Quantity should remain unchanged for market orders
	assert.Equal(t, scaleUpUint256(100.0).String(), marketOrder.Quantity.String())
}

func TestStopOrderContext_QuoteMode(t *testing.T) {
	// Test stop limit order in quote mode
	quoteStopOrder := &StopOrderContext{
		L1Owner:    common.HexToAddress("0xabc"),
		BaseToken:  "1",
		QuoteToken: "2",
		Side:       SELL,
		StopPrice:  scaleUp(1.5),  // Stop at 1.5 USDT
		Price:      scaleUp(1.4),  // Sell at 1.4 USDT
		Quantity:   scaleUp(70.0), // Want to receive 70 USDT (quote mode)
		OrderType:  LIMIT,
		OrderMode:  1, // QUOTE_MODE
	}

	stopOrder := quoteStopOrder.ToStopOrder(common.HexToHash("0x789"))
	assert.Equal(t, orderbook.BASE_MODE, stopOrder.Order.OrderMode)
	// Quantity should be converted: 70 / 1.4 = 50 base tokens
	assert.Equal(t, scaleUpUint256(50.0).String(), stopOrder.Order.Quantity.String())
	assert.Equal(t, scaleUpUint256(50.0).String(), stopOrder.Order.OrigQty.String())

	// Test stop market order in quote mode
	quoteStopMarket := &StopOrderContext{
		L1Owner:    common.HexToAddress("0xabc"),
		BaseToken:  "1",
		QuoteToken: "2",
		Side:       BUY,
		StopPrice:  scaleUp(2.0),   // Stop at 2.0 USDT
		Price:      big.NewInt(0),  // Market order
		Quantity:   scaleUp(100.0), // 100 USDT to spend
		OrderType:  MARKET,
		OrderMode:  1, // QUOTE_MODE
	}

	stopMarketOrder := quoteStopMarket.ToStopOrder(common.HexToHash("0xabc"))
	assert.Equal(t, orderbook.QUOTE_MODE, stopMarketOrder.Order.OrderMode)
	// Quantity should remain unchanged for market orders
	assert.Equal(t, scaleUpUint256(100.0).String(), stopMarketOrder.Order.Quantity.String())
}

func TestModifyContext_QuoteMode(t *testing.T) {
	t.Run("ModifyBothPriceAndQuantity", func(t *testing.T) {
		// Test modify order in quote mode with both price and quantity
		quoteModify := &ModifyContext{
			L1Owner:   common.HexToAddress("0xabc"),
			OrderID:   common.HexToHash("0x123"),
			NewPrice:  scaleUp(2.5),   // 2.5 USDT per token
			NewQty:    scaleUp(250.0), // 250 USDT (quote mode)
			OrderMode: 1, // QUOTE_MODE
		}

		modifyArgs := quoteModify.ToModifyArgs(common.HexToHash("0xdef").Hex())
		// For modify, quote quantities are converted using new price: 250 / 2.5 = 100 base tokens
		assert.Equal(t, scaleUpUint256(100.0).String(), modifyArgs.NewQty.String())
		assert.Equal(t, scaleUpUint256(2.5).String(), modifyArgs.NewPrice.String())
	})

	t.Run("ModifyOnlyQuantity_WithOriginalPrice", func(t *testing.T) {
		// Test modify only quantity in quote mode - should use original price
		quoteModify := &ModifyContext{
			L1Owner:       common.HexToAddress("0xabc"),
			OrderID:       common.HexToHash("0x123"),
			NewPrice:      nil,         // No new price
			NewQty:        scaleUp(300.0), // 300 USDT (quote mode)
			OrderMode:     1, // QUOTE_MODE
			originalPrice: scaleUp(3.0), // Original price from validation
		}

		modifyArgs := quoteModify.ToModifyArgs(common.HexToHash("0xdef").Hex())
		// Should use original price for conversion: 300 / 3.0 = 100 base tokens
		assert.Equal(t, scaleUpUint256(100.0).String(), modifyArgs.NewQty.String())
		assert.Nil(t, modifyArgs.NewPrice, "NewPrice should be nil when not modified")
	})

	t.Run("ModifyOnlyPrice", func(t *testing.T) {
		// Test modify only price in quote mode - quantity should not be converted
		quoteModify := &ModifyContext{
			L1Owner:   common.HexToAddress("0xabc"),
			OrderID:   common.HexToHash("0x123"),
			NewPrice:  scaleUp(4.0), // New price only
			NewQty:    nil,           // No new quantity
			OrderMode: 1, // QUOTE_MODE
		}

		modifyArgs := quoteModify.ToModifyArgs(common.HexToHash("0xdef").Hex())
		// No quantity to convert
		assert.Nil(t, modifyArgs.NewQty, "NewQty should be nil when not modified")
		assert.Equal(t, scaleUpUint256(4.0).String(), modifyArgs.NewPrice.String())
	})

	t.Run("ModifyQuantity_WithValidOriginalPrice", func(t *testing.T) {
		// Test modify quantity with different original price values
		quoteModify := &ModifyContext{
			L1Owner:       common.HexToAddress("0xabc"),
			OrderID:       common.HexToHash("0x123"),
			NewPrice:      nil,
			NewQty:        scaleUp(200.0),
			OrderMode:     1, // QUOTE_MODE
			originalPrice: scaleUp(4.0), // Original price = 4.0
		}

		modifyArgs := quoteModify.ToModifyArgs(common.HexToHash("0xdef").Hex())
		// Should use original price: 200 / 4.0 = 50 base tokens
		assert.Equal(t, scaleUpUint256(50.0).String(), modifyArgs.NewQty.String())
	})

	t.Run("ModifyInBaseMode", func(t *testing.T) {
		// Test that base mode modifications don't convert quantities
		baseModify := &ModifyContext{
			L1Owner:   common.HexToAddress("0xabc"),
			OrderID:   common.HexToHash("0x123"),
			NewPrice:  scaleUp(2.0),
			NewQty:    scaleUp(50.0), // 50 base tokens
			OrderMode: 0, // BASE_MODE
		}

		modifyArgs := baseModify.ToModifyArgs(common.HexToHash("0xdef").Hex())
		// Quantity should remain unchanged in base mode
		assert.Equal(t, scaleUpUint256(50.0).String(), modifyArgs.NewQty.String())
		assert.Equal(t, scaleUpUint256(2.0).String(), modifyArgs.NewPrice.String())
	})

	t.Run("ModifyWithFractionalPrice_QuoteMode", func(t *testing.T) {
		// Test with fractional price for precision
		quoteModify := &ModifyContext{
			L1Owner:       common.HexToAddress("0xabc"),
			OrderID:       common.HexToHash("0x123"),
			NewPrice:      scaleUp(1.5), // 1.5 USDT per token
			NewQty:        scaleUp(150.0), // 150 USDT
			OrderMode:     1, // QUOTE_MODE
			originalPrice: scaleUp(2.0),
		}

		modifyArgs := quoteModify.ToModifyArgs(common.HexToHash("0xdef").Hex())
		// 150 / 1.5 = 100 base tokens
		assert.Equal(t, scaleUpUint256(100.0).String(), modifyArgs.NewQty.String())
	})

	t.Run("ModifyLargeQuantity_QuoteMode", func(t *testing.T) {
		// Test with large quantities
		// Note: Due to scaled decimal division, there may be slight precision loss
		quoteModify := &ModifyContext{
			L1Owner:   common.HexToAddress("0xabc"),
			OrderID:   common.HexToHash("0x123"),
			NewPrice:  scaleUp(10.0),     // Price = 10
			NewQty:    scaleUp(10000.0),  // 10K USDT
			OrderMode: 1, // QUOTE_MODE
		}

		modifyArgs := quoteModify.ToModifyArgs(common.HexToHash("0xdef").Hex())
		// 10000 / 10 = 1000 base tokens
		// Due to the way Uint256DivScaledDecimal works, we allow for minimal precision loss
		expected := scaleUpUint256(1000.0)
		actual := modifyArgs.NewQty
		
		// Allow for tiny precision difference (less than 0.001%)
		diff := new(uint256.Int).Sub(expected, actual)
		if diff.Sign() < 0 {
			diff.Neg(diff)
		}
		maxDiff := new(uint256.Int).Div(expected, uint256.NewInt(100000)) // 0.001%
		assert.True(t, diff.Cmp(maxDiff) <= 0, "Precision loss too high: expected %s, got %s", expected.String(), actual.String())
	})

	t.Run("ModifySmallQuantity_QuoteMode", func(t *testing.T) {
		// Test with small quantities for precision
		quoteModify := &ModifyContext{
			L1Owner:   common.HexToAddress("0xabc"),
			OrderID:   common.HexToHash("0x123"),
			NewPrice:  scaleUp(0.5),   // 0.5 USDT per token
			NewQty:    scaleUp(1.0),   // 1 USDT
			OrderMode: 1, // QUOTE_MODE
		}

		modifyArgs := quoteModify.ToModifyArgs(common.HexToHash("0xdef").Hex())
		// 1.0 / 0.5 = 2 base tokens
		assert.Equal(t, scaleUpUint256(2.0).String(), modifyArgs.NewQty.String())
	})
}

func TestOrderContext_BaseMode(t *testing.T) {
	// Test that base mode (default) orders remain unchanged
	baseOrder := &OrderContext{
		L1Owner:    common.HexToAddress("0xabc"),
		BaseToken:  "1",
		QuoteToken: "2",
		Side:       BUY,
		Price:      scaleUp(2.0),  // 2.0 USDT per token
		Quantity:   scaleUp(50.0), // 50 base tokens
		OrderType:  LIMIT,
		// OrderMode not set, defaults to BASE_MODE (0)
	}

	order := baseOrder.ToOrder(common.HexToHash("0x123"))
	assert.Equal(t, orderbook.BASE_MODE, order.OrderMode)
	// Quantity should remain unchanged
	assert.Equal(t, scaleUpUint256(50.0).String(), order.Quantity.String())
	assert.Equal(t, scaleUpUint256(50.0).String(), order.OrigQty.String())
}

func TestOrderContext_QuoteModeWithTPSL(t *testing.T) {
	// Test quote mode order with TPSL
	quoteOrderWithTPSL := &OrderContext{
		L1Owner:    common.HexToAddress("0xabc"),
		BaseToken:  "1",
		QuoteToken: "2",
		Side:       BUY,
		Price:      scaleUp(2.0),   // 2.0 USDT per token
		Quantity:   scaleUp(100.0), // 100 USDT to spend (quote mode)
		OrderType:  LIMIT,
		OrderMode:  1, // QUOTE_MODE
		TPSL: &TPSLContext{
			TPLimit:   scaleUp(2.2), // Take profit at 2.2 USDT
			SLTrigger: scaleUp(1.8), // Stop loss trigger at 1.8 USDT
			SLLimit:   scaleUp(1.7), // Stop loss limit at 1.7 USDT
		},
	}

	order := quoteOrderWithTPSL.ToOrder(common.HexToHash("0x123"))
	assert.Equal(t, orderbook.BASE_MODE, order.OrderMode)
	// Main order quantity converted: 100 / 2.0 = 50 base tokens
	assert.Equal(t, scaleUpUint256(50.0).String(), order.Quantity.String())

	// Check TPSL orders are created and use base mode
	assert.NotNil(t, order.TPSL)
	assert.NotNil(t, order.TPSL.TPOrder)
	assert.Equal(t, orderbook.BASE_MODE, order.TPSL.TPOrder.Order.OrderMode)
	// TP/SL quantities will be filled later after fee calculation, so they're 0 at creation
	assert.Equal(t, "0", order.TPSL.TPOrder.Order.Quantity.String())

	assert.NotNil(t, order.TPSL.SLOrder)
	assert.Equal(t, orderbook.BASE_MODE, order.TPSL.SLOrder.Order.OrderMode)
	// TP/SL quantities will be filled later after fee calculation, so they're 0 at creation
	assert.Equal(t, "0", order.TPSL.SLOrder.Order.Quantity.String())
}

func TestStopOrderContext_QuoteModeValidation(t *testing.T) {
	// Test validation of stop orders in quote mode
	mockdb := NewMockBalanceGetter()
	user := common.HexToAddress("0xabc")

	// Fund the user with sufficient balances
	mockdb.Fund("1", scaleUpUint256(1000.0)) // Base token
	mockdb.Fund("2", scaleUpUint256(1000.0)) // Quote token

	t.Run("BuyStopOrder_QuoteMode_Validation", func(t *testing.T) {
		// BUY stop order in quote mode - quantity is quote tokens to spend
		stopOrder := &StopOrderContext{
			L1Owner:    user,
			BaseToken:  "1",
			QuoteToken: "2",
			Side:       BUY,
			StopPrice:  scaleUp(25.0),  // Stop at 25
			Price:      scaleUp(24.0),  // Buy at 24
			Quantity:   scaleUp(480.0), // Spend 480 quote tokens
			OrderType:  LIMIT,
			OrderMode:  1, // QUOTE_MODE
		}

		// Should validate successfully - user has 1000 quote tokens, needs 480
		err := stopOrder.validate(user, mockdb, nil, nil)
		assert.NoError(t, err, "should validate quote mode buy stop order")

		// Test with insufficient balance
		mockdb.balances["2"] = scaleUpUint256(400.0) // Only 400 quote tokens
		err = stopOrder.validate(user, mockdb, nil, nil)
		assert.Error(t, err, "should fail with insufficient balance")
	})

	t.Run("SellStopOrder_QuoteMode_Validation", func(t *testing.T) {
		// Reset balance
		mockdb.Fund("1", scaleUpUint256(1000.0))
		mockdb.Fund("2", scaleUpUint256(1000.0))

		// SELL stop order in quote mode - quantity is quote tokens to receive
		stopOrder := &StopOrderContext{
			L1Owner:    user,
			BaseToken:  "1",
			QuoteToken: "2",
			Side:       SELL,
			StopPrice:  scaleUp(20.0),  // Stop at 20
			Price:      scaleUp(19.0),  // Sell at 19
			Quantity:   scaleUp(380.0), // Want to receive 380 quote tokens
			OrderType:  LIMIT,
			OrderMode:  1, // QUOTE_MODE
		}

		// Should validate successfully
		// Need base tokens: 380 / 19 = 20 base tokens
		err := stopOrder.validate(user, mockdb, nil, nil)
		assert.NoError(t, err, "should validate quote mode sell stop order")

		// Test with insufficient base balance
		mockdb.balances["1"] = scaleUpUint256(10.0) // Only 10 base tokens
		err = stopOrder.validate(user, mockdb, nil, nil)
		assert.Error(t, err, "should fail with insufficient base balance")
	})

	t.Run("MarketStopOrder_QuoteMode_Validation", func(t *testing.T) {
		// Reset balance
		mockdb.Fund("1", scaleUpUint256(1000.0))
		mockdb.Fund("2", scaleUpUint256(1000.0))

		// BUY market stop in quote mode
		buyMarketStop := &StopOrderContext{
			L1Owner:    user,
			BaseToken:  "1",
			QuoteToken: "2",
			Side:       BUY,
			StopPrice:  scaleUp(25.0),
			Price:      big.NewInt(0), // Market order has no price
			Quantity:   scaleUp(500.0), // Spend 500 quote tokens
			OrderType:  MARKET,
			OrderMode:  1, // QUOTE_MODE
		}

		// Should validate - needs 500 quote tokens
		err := buyMarketStop.validate(user, mockdb, nil, nil)
		assert.NoError(t, err, "should validate quote mode buy market stop")

		// SELL market stop in quote mode
		sellMarketStop := &StopOrderContext{
			L1Owner:    user,
			BaseToken:  "1",
			QuoteToken: "2",
			Side:       SELL,
			StopPrice:  scaleUp(20.0),
			Price:      big.NewInt(0),
			Quantity:   scaleUp(400.0), // Want to receive 400 quote tokens
			OrderType:  MARKET,
			OrderMode:  1, // QUOTE_MODE
		}

		// Should validate - needs 400/20 = 20 base tokens
		err = sellMarketStop.validate(user, mockdb, nil, nil)
		assert.NoError(t, err, "should validate quote mode sell market stop")
	})
}

func TestStopOrderContext_QuoteModeConversion(t *testing.T) {
	txHash := common.HexToHash("0x123")

	t.Run("LimitStopOrder_QuoteMode", func(t *testing.T) {
		// Limit stop order in quote mode should be converted to base mode
		stopOrder := &StopOrderContext{
			L1Owner:    common.HexToAddress("0xabc"),
			BaseToken:  "1",
			QuoteToken: "2",
			Side:       BUY,
			StopPrice:  scaleUp(25.0),
			Price:      scaleUp(24.0),  // Buy at 24
			Quantity:   scaleUp(480.0), // 480 quote tokens
			OrderType:  LIMIT,
			OrderMode:  1, // QUOTE_MODE
		}

		order := stopOrder.ToStopOrder(txHash)

		// Should be converted to base mode
		assert.Equal(t, orderbook.BASE_MODE, order.Order.OrderMode)
		// Quantity should be: 480 / 24 = 20 base tokens
		expectedQty := scaleUpUint256(20.0)
		assert.Equal(t, expectedQty.String(), order.Order.Quantity.String())
	})

	t.Run("MarketStopOrder_QuoteMode", func(t *testing.T) {
		// Market stop order in quote mode should stay in quote mode
		stopOrder := &StopOrderContext{
			L1Owner:    common.HexToAddress("0xabc"),
			BaseToken:  "1",
			QuoteToken: "2",
			Side:       SELL,
			StopPrice:  scaleUp(20.0),
			Price:      big.NewInt(0), // Market order
			Quantity:   scaleUp(400.0), // 400 quote tokens to receive
			OrderType:  MARKET,
			OrderMode:  1, // QUOTE_MODE
		}

		order := stopOrder.ToStopOrder(txHash)

		// Should remain in quote mode (market orders can't be converted)
		assert.Equal(t, orderbook.QUOTE_MODE, order.Order.OrderMode)
		// Quantity should remain unchanged
		assert.Equal(t, scaleUpUint256(400.0).String(), order.Order.Quantity.String())
	})
}
