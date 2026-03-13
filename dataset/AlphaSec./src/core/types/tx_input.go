package types

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"strconv"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
	"github.com/shopspring/decimal"
)

type BalanceGetter interface {
	GetBalance(common.Address) *uint256.Int
	GetTokenBalance(common.Address, string) *uint256.Int
	GetLockedTokenBalance(common.Address, string) *uint256.Int
	GetSessions(addr common.Address) []SessionCommandBytes
}

type MarketChecker interface {
	ContainsMarket(uint64, uint64) (bool, error)
}

const (
	BUY    = uint8(0)
	SELL   = uint8(1)
	LIMIT  = uint8(0)
	MARKET = uint8(1)
)

const (
	ScalingExp             = 18
	MinimumRequiredBalance = 1
	MaxTokenLength         = 20
)

var (
	ScalingDecimal = decimal.NewFromUint64(1_000_000_000_000_000_000)
	uint256Max     = new(big.Int).Sub(new(big.Int).Lsh(big.NewInt(1), 256), big.NewInt(1))

	// price = 10^29 - 1
	priceMax = new(big.Int).Sub(
		new(big.Int).Exp(big.NewInt(10), big.NewInt(29), nil),
		big.NewInt(1),
	)

	// quantity = 10^41 - 1
	quantityMax = new(big.Int).Sub(
		new(big.Int).Exp(big.NewInt(10), big.NewInt(41), nil),
		big.NewInt(1),
	)
)

func GetDexCommandType(input []byte) byte {
	if len(input) < 1 {
		return InvalidDexCommand
	}
	return input[0]
}

type DexCommandData interface {
	command() byte
	validate(sender common.Address, statedb BalanceGetter, orderbook orderbook.Dex, checker MarketChecker) error
	from() common.Address
	copy() DexCommandData

	Serialize() ([]byte, error)
	Deserialize([]byte) error
}

func encode(obj DexCommandData) ([]byte, error) {
	encoded, err := json.Marshal(obj)
	if err != nil {
		return nil, err
	}
	return encoded, nil
}

type TokenTransferContext struct {
	L1Owner common.Address `json:"l1owner"`
	To      common.Address `json:"to"`
	Value   *big.Int       `json:"value"`
	Token   string         `json:"token"`
}

func (t *TokenTransferContext) command() byte        { return DexCommandTokenTransfer }
func (t *TokenTransferContext) from() common.Address { return t.L1Owner }
func (t *TokenTransferContext) copy() DexCommandData {
	var valueCopy *big.Int
	if t == nil || t.Value == nil {
		valueCopy = new(big.Int).Set(t.Value)
	}
	return &TokenTransferContext{t.L1Owner, t.To, valueCopy, t.Token}
}
func (t *TokenTransferContext) Serialize() ([]byte, error)     { return encode(t) }
func (t *TokenTransferContext) Deserialize(input []byte) error { return json.Unmarshal(input, t) }
func (t *TokenTransferContext) validate(sender common.Address, statedb BalanceGetter, orderbook orderbook.Dex, checker MarketChecker) error {
	if t.L1Owner == (common.Address{}) {
		return errors.New("sender address (From) is zero")
	}
	if t.Token == "" {
		return errors.New("token address is zero")
	}
	_, err := strconv.ParseUint(t.Token, 10, 64)
	if err != nil {
		return errors.New("token must be a 64-bit unsigned integer")
	}
	if len(t.Token) > MaxTokenLength {
		return errors.New("token is too long")
	}
	if t.Value == nil {
		return errors.New("amount is nil")
	}
	if t.Value.Sign() < 0 {
		return errors.New("amount must be positive")
	}
	if t.Value != nil && t.Value.Cmp(uint256Max) > 0 {
		return errors.New("price exceeds uint256 max value")
	}
	return t.validateBalance(statedb)
}

func (t *TokenTransferContext) validateBalance(statedb BalanceGetter) error {
	balance := statedb.GetTokenBalance(t.L1Owner, t.Token)
	val := uint256.MustFromBig(t.Value)
	if balance.Cmp(val) < 0 {
		return fmt.Errorf("insufficient %s balance: have %s, need %s",
			t.Token, balance.Dec(), val.Dec())
	}
	return nil
}

type OrderContext struct {
	L1Owner    common.Address `json:"l1owner"`
	BaseToken  string         `json:"baseToken"`
	QuoteToken string         `json:"quoteToken"`
	Side       uint8          `json:"side"` // 0: buy, 1: sell
	Price      *big.Int       `json:"price"`
	Quantity   *big.Int       `json:"quantity"`
	OrderType  uint8          `json:"orderType"`      // 0: limit, 1: market
	OrderMode  uint8          `json:"orderMode"`      // 0: base mode (default), 1: quote mode
	TPSL       *TPSLContext   `json:"tpsl,omitempty"` // optional, only set for TPSL orders
}

type TPSLContext struct {
	TPLimit   *big.Int `json:"tpLimit"`
	SLTrigger *big.Int `json:"slTrigger"`
	SLLimit   *big.Int `json:"slLimit,omitempty"` // optional, if not set, SL is market order
}

func (t *TPSLContext) copy() *TPSLContext {
	if t == nil {
		return nil
	}
	var tpLimit, slTrigger, slLimit *big.Int
	if t.TPLimit != nil {
		tpLimit = new(big.Int).Set(t.TPLimit)
	}
	if t.SLTrigger != nil {
		slTrigger = new(big.Int).Set(t.SLTrigger)
	}
	if t.SLLimit != nil {
		slLimit = new(big.Int).Set(t.SLLimit)
	}
	return &TPSLContext{tpLimit, slTrigger, slLimit}
}

func (t *OrderContext) command() byte        { return DexCommandNew }
func (t *OrderContext) from() common.Address { return t.L1Owner }
func (t *OrderContext) copy() DexCommandData {
	var priceCopy, quantityCopy *big.Int
	if t.Price != nil {
		priceCopy = new(big.Int).Set(t.Price)
	}
	if t.Quantity != nil {
		quantityCopy = new(big.Int).Set(t.Quantity)
	}
	var tpslCopy *TPSLContext
	if t.TPSL != nil {
		tpslCopy = t.TPSL.copy()
	}
	return &OrderContext{t.L1Owner, t.BaseToken, t.QuoteToken, t.Side, priceCopy, quantityCopy, t.OrderType, t.OrderMode, tpslCopy}
}
func (t *OrderContext) Serialize() ([]byte, error)     { return encode(t) }
func (t *OrderContext) Deserialize(input []byte) error { return json.Unmarshal(input, t) }
func (t *OrderContext) validate(sender common.Address, statedb BalanceGetter, dex orderbook.Dex, checker MarketChecker) error {
	if t.L1Owner == (common.Address{}) {
		return errors.New("from address is zero")
	}
	if t.BaseToken == "" || t.QuoteToken == "" {
		return errors.New("base token or quote token is empty")
	}
	baseTokenId, err := strconv.ParseUint(t.BaseToken, 10, 64)
	if err != nil {
		return errors.New("base token must be a 64-bit unsigned integer")
	}
	quoteTokenId, err := strconv.ParseUint(t.QuoteToken, 10, 64)
	if err != nil {
		return errors.New("quote token must be a 64-bit unsigned integer")
	}
	exist, err := checker.ContainsMarket(baseTokenId, quoteTokenId)
	if err != nil {
		return err
	}
	if !exist {
		return fmt.Errorf("market does not exist. base: %v, quote: %v", baseTokenId, quoteTokenId)
	}
	if len(t.BaseToken) > MaxTokenLength || len(t.QuoteToken) > MaxTokenLength {
		return errors.New("base token or quote token is too long")
	}
	if t.Side != 0 && t.Side != 1 {
		return errors.New("invalid side: must be 0 (buy) or 1 (sell)")
	}
	if t.OrderType != LIMIT && t.OrderType != MARKET {
		return errors.New("invalid order type: must be 0 (limit) or 1 (market)")
	}
	if t.OrderType == LIMIT && (t.Price == nil || t.Price.Sign() <= 0) {
		return errors.New("price must be positive for limit orders")
	}
	if t.OrderType == MARKET && t.Price == nil {
		t.Price = big.NewInt(0) // For market orders, price is not used but must be non-nil
	}
	if t.OrderType == MARKET && t.TPSL != nil {
		return errors.New("TPSL orders cannot be market orders")
	}
	if t.Quantity == nil || t.Quantity.Sign() <= 0 {
		return errors.New("quantity must be positive")
	}
	if t.OrderType != 0 && t.OrderType != 1 {
		return errors.New("invalid order type: must be 0 (limit) or 1 (market)")
	}
	if t.Price != nil && t.Price.Cmp(priceMax) > 0 {
		return errors.New("price exceeds price max value")
	}
	if t.Quantity != nil && t.Quantity.Cmp(quantityMax) > 0 {
		return errors.New("quantity exceeds quantity max value")
	}
	if t.TPSL != nil {
		if t.TPSL.TPLimit == nil || t.TPSL.SLTrigger == nil {
			return errors.New("TPSL TPLimit and SLTrigger must be set")
		}
		if t.TPSL.TPLimit != nil && t.TPSL.TPLimit.Cmp(priceMax) > 0 {
			return errors.New("TPSL TPLimit exceeds price max value")
		}
		if t.TPSL.SLTrigger != nil && t.TPSL.SLTrigger.Cmp(priceMax) > 0 {
			return errors.New("TPSL SLTrigger exceeds price max value")
		}
		if t.TPSL.SLLimit != nil && t.TPSL.SLLimit.Cmp(priceMax) > 0 {
			return errors.New("TPSL SLLimit exceeds price max value")
		}
		if t.TPSL.TPLimit.Sign() <= 0 || t.TPSL.SLTrigger.Sign() <= 0 {
			return errors.New("TPSL TPLimit and SLTrigger must be positive")
		}
		if t.Side == BUY && t.TPSL.TPLimit.Cmp(t.Price) <= 0 {
			return fmt.Errorf("TPSL TPLimit %s must be greater than order price %s", t.TPSL.TPLimit, t.Price)
		}
		if t.Side == SELL && t.TPSL.TPLimit.Cmp(t.Price) >= 0 {
			return fmt.Errorf("TPSL TPLimit %s must be less than order price %s", t.TPSL.TPLimit, t.Price)
		}
		if t.Side == BUY && t.TPSL.SLTrigger.Cmp(t.Price) >= 0 {
			return fmt.Errorf("TPSL SLTrigger %s must be less than order price %s", t.TPSL.SLTrigger, t.Price)
		}
		if t.Side == SELL && t.TPSL.SLTrigger.Cmp(t.Price) <= 0 {
			return fmt.Errorf("TPSL SLTrigger %s must be greater than order price %s", t.TPSL.SLTrigger, t.Price)
		}
	}

	// Market rules validation
	symbol := t.BaseToken + "/" + t.QuoteToken
	marketRules := dex.GetMarketRules(symbol)

	if t.OrderType == MARKET {
		// Market order validation using best price
		// Note: we cannot use orderbook.BUY/SELL here due to parameter name conflict
		// So we define the side based on t.Side
		bestPrice := dex.GetBestPrice(symbol, orderbook.Side(t.Side))

		if err := marketRules.ValidateMarketOrder(
			uint256.MustFromBig(t.Quantity),
			bestPrice,
			orderbook.Side(t.Side),
			orderbook.OrderMode(t.OrderMode),
		); err != nil {
			return fmt.Errorf("market order validation failed: %v", err)
		}
	} else if t.OrderType == LIMIT {
		// Price tick size validation
		priceUint := uint256.MustFromBig(t.Price)
		if err := marketRules.ValidateOrderPrice(priceUint); err != nil {
			return fmt.Errorf("price validation failed: %v", err)
		}

		// Quantity lot size validation (convert quote mode to base for validation)
		qty := t.Quantity
		if t.OrderMode == 1 { // QUOTE_MODE
			qty = common.BigIntDivScaledDecimal(t.Quantity, t.Price)
		}
		qtyUint := uint256.MustFromBig(qty)

		if err := marketRules.ValidateOrderQuantity(priceUint, qtyUint); err != nil {
			return fmt.Errorf("quantity validation failed: %v", err)
		}

		// Minimum order value validation ($1)
		if err := marketRules.ValidateMinimumOrderValue(priceUint, qtyUint); err != nil {
			return err
		}

		// TPSL price validation
		if t.TPSL != nil {
			// TP limit price validation
			if t.TPSL.TPLimit != nil {
				tpPriceUint := uint256.MustFromBig(t.TPSL.TPLimit)
				if err := marketRules.ValidateOrderPrice(tpPriceUint); err != nil {
					return fmt.Errorf("TPSL TP limit price validation failed: %v", err)
				}
			}

			// SL trigger price validation
			if t.TPSL.SLTrigger != nil {
				slTriggerUint := uint256.MustFromBig(t.TPSL.SLTrigger)
				if err := marketRules.ValidateOrderPrice(slTriggerUint); err != nil {
					return fmt.Errorf("TPSL SL trigger price validation failed: %v", err)
				}
			}

			// SL limit price validation (if exists)
			if t.TPSL.SLLimit != nil {
				slLimitUint := uint256.MustFromBig(t.TPSL.SLLimit)
				if err := marketRules.ValidateOrderPrice(slLimitUint); err != nil {
					return fmt.Errorf("TPSL SL limit price validation failed: %v", err)
				}
			}
		}
	}

	return t.validateBalance(statedb)
}

func (t *OrderContext) validateBalance(statedb BalanceGetter) error {
	var token string
	var required *big.Int

	isQuoteMode := orderbook.OrderMode(t.OrderMode) == orderbook.QUOTE_MODE

	switch t.Side {
	case BUY:
		token = t.QuoteToken
		if t.OrderType == LIMIT {
			if isQuoteMode {
				// Buy limit in quote mode: required quote is the quantity itself
				required = new(big.Int).Set(t.Quantity)
			} else {
				// Buy limit in base mode: required quote = base_quantity * price
				required = common.BigIntMulScaledDecimal(t.Price, t.Quantity)
			}
		} else if t.OrderType == MARKET {
			// For market buys, we check for a minimum balance and lock the full available balance later.
			required = big.NewInt(MinimumRequiredBalance)
		} else {
			return fmt.Errorf("invalid order type: %v", t.OrderType)
		}
	case SELL:
		token = t.BaseToken
		if t.OrderType == LIMIT {
			if isQuoteMode {
				// Sell limit in quote mode: required base = quote_quantity / price
				required = common.BigIntDivScaledDecimal(t.Quantity, t.Price)
			} else {
				// Sell limit in base mode: required base is the quantity itself
				required = new(big.Int).Set(t.Quantity)
			}
		} else if t.OrderType == MARKET {
			// For market sells, we check for a minimum balance and lock the full available balance later.
			required = big.NewInt(MinimumRequiredBalance)
		} else {
			return fmt.Errorf("invalid order type: %v", t.OrderType)
		}
	default:
		return fmt.Errorf("invalid order side: %v", t.Side)
	}

	balance := statedb.GetTokenBalance(t.L1Owner, token)
	requiredFromBig := uint256.MustFromBig(required)
	if balance.Cmp(requiredFromBig) < 0 {
		return fmt.Errorf("insufficient %s balance: have %s, need %s",
			token, balance.Dec(), requiredFromBig.Dec())
	}

	return nil
}

func (t *OrderContext) ToOrderV2(txHash common.Hash) *types.Order {
	// Convert quote mode to base mode for limit orders
	quantity := uint256.MustFromBig(t.Quantity)
	orderMode := types.OrderMode(t.OrderMode)
	orderType := types.OrderType(t.OrderType)

	// For limit orders in quote mode, convert quantities to base
	if orderMode == types.QUOTE_MODE && orderType == types.LIMIT {
		if t.Price != nil && t.Price.Sign() > 0 {
			// Convert quote quantity to base quantity: base_qty = quote_qty / price
			priceUint := uint256.MustFromBig(t.Price)
			quantity = common.Uint256DivScaledDecimal(quantity, priceUint)
			// After conversion, treat as base mode internally
			orderMode = types.BASE_MODE
		}
	}

	var tpsl *types.TPSLContext
	if t.TPSL != nil {
		tpsl = types.NewTPSL(
			uint256.MustFromBig(t.TPSL.TPLimit),
			uint256.MustFromBig(t.TPSL.SLTrigger),
			uint256.MustFromBig(t.TPSL.SLLimit),
		)
	}

	return types.NewOrder(
		types.OrderID(txHash.Hex()),
		types.UserID(t.L1Owner.Hex()),
		types.Symbol(t.BaseToken+"/"+t.QuoteToken),
		types.OrderSide(t.Side),
		orderMode,
		orderType,
		uint256.MustFromBig(t.Price),
		quantity,
		tpsl,
	)
}

func (t *OrderContext) ToOrder(txHash common.Hash) *orderbook.Order {
	originalID := txHash.Hex()

	// Convert quote mode to base mode for limit orders
	quantity := uint256.MustFromBig(t.Quantity)
	origQty := uint256.MustFromBig(t.Quantity)
	orderMode := orderbook.OrderMode(t.OrderMode)

	// For limit orders in quote mode, convert quantities to base
	if orderbook.OrderMode(t.OrderMode) == orderbook.QUOTE_MODE && orderbook.OrderType(t.OrderType) == orderbook.LIMIT {
		if t.Price != nil && t.Price.Sign() > 0 {
			// Convert quote quantity to base quantity: base_qty = quote_qty / price
			priceUint := uint256.MustFromBig(t.Price)
			quantity = common.Uint256DivScaledDecimal(quantity, priceUint)
			origQty = quantity
			// After conversion, treat as base mode internally
			orderMode = orderbook.BASE_MODE
		}
	}
	// Note: Market orders in quote mode keep their original mode and quantity
	// They will be handled specially during matching

	var tpsl *orderbook.TPSLOrder
	if t.TPSL != nil {
		// Generate unique IDs for TP and SL orders
		tpOrderID := orderbook.GenerateConditionalOrderID(txHash, orderbook.TPIncrement)
		slOrderID := orderbook.GenerateConditionalOrderID(txHash, orderbook.SLIncrement)

		slOrderType := orderbook.OrderType(MARKET)
		slLimit := uint256.NewInt(0)
		if t.TPSL.SLLimit != nil {
			slOrderType = orderbook.OrderType(LIMIT)
			slLimit = uint256.MustFromBig(t.TPSL.SLLimit)
		}

		var tpQty, slQty *uint256.Int
		tpQty, slQty = uint256.NewInt(0), uint256.NewInt(0)
		//if t.Side == BUY {
		//	qty := new(big.Int).Set(t.Quantity)
		//	if orderbook.FeeRate != 0 {
		//		fee := new(big.Int).Div(t.Quantity, new(big.Int).SetUint64(orderbook.FeeRate))
		//		qty = new(big.Int).Sub(t.Quantity, fee)
		//	}
		//	tpQty = uint256.MustFromBig(qty)
		//	slQty = uint256.MustFromBig(qty)
		//} else {
		//	cost := common.BigIntMulScaledDecimal(t.Price, t.Quantity)
		//	if orderbook.FeeRate != 0 {
		//		fee := new(big.Int).Div(cost, new(big.Int).SetUint64(orderbook.FeeRate))
		//		cost = new(big.Int).Sub(cost, fee)
		//	}
		//
		//	// TODO-Orderbook: This may cause the decimal precision issue.
		//	tpQty = uint256.MustFromBig(common.BigIntDivScaledDecimal(cost, t.TPSL.TPLimit))
		//	if slOrderType == orderbook.OrderType(LIMIT) {
		//		slQty = uint256.MustFromBig(common.BigIntDivScaledDecimal(cost, t.TPSL.SLLimit))
		//	} else {
		//		slQty = uint256.MustFromBig(common.BigIntDivScaledDecimal(cost, t.TPSL.SLTrigger))
		//	}
		//}

		// For TPSL orders in quote mode, convert quantities
		// Since TPSL orders are triggered later, they should use the converted mode
		tpsl = &orderbook.TPSLOrder{
			TPOrder: &orderbook.StopOrder{
				Order: &orderbook.Order{
					OrderID:    tpOrderID, // Use unique TP order ID
					UserID:     t.L1Owner.Hex(),
					Symbol:     t.BaseToken + "/" + t.QuoteToken,
					Side:       orderbook.Opposite(orderbook.Side(t.Side)), // TP is always opposite side of the main order
					Price:      uint256.MustFromBig(t.TPSL.TPLimit),
					OrigQty:    tpQty,
					Quantity:   tpQty,
					Timestamp:  time.Now().UnixNano(),
					OrderType:  orderbook.OrderType(LIMIT), // TP is always a limit order
					OrderMode:  orderbook.BASE_MODE,        // Always use base mode after conversion
					IsCanceled: false,
				},
				StopPrice:    uint256.MustFromBig(t.TPSL.TPLimit),
				TriggerAbove: t.Side == BUY,
			},
			SLOrder: &orderbook.StopOrder{
				Order: &orderbook.Order{
					OrderID:    slOrderID, // Use unique SL order ID
					UserID:     t.L1Owner.Hex(),
					Symbol:     t.BaseToken + "/" + t.QuoteToken,
					Side:       orderbook.Opposite(orderbook.Side(t.Side)), // SL is always opposite side of the main order
					Price:      slLimit,
					OrigQty:    slQty,
					Quantity:   slQty,
					Timestamp:  time.Now().UnixNano(),
					OrderType:  slOrderType,
					OrderMode:  orderbook.BASE_MODE, // Always use base mode after conversion
					IsCanceled: false,
				},
				StopPrice:    uint256.MustFromBig(t.TPSL.SLTrigger),
				TriggerAbove: t.Side == SELL,
			},
		}
	}

	return &orderbook.Order{
		OrderID:    originalID, // Main order keeps original ID
		UserID:     t.L1Owner.Hex(),
		Symbol:     t.BaseToken + "/" + t.QuoteToken,
		Side:       orderbook.Side(t.Side),
		Price:      uint256.MustFromBig(t.Price),
		OrigQty:    origQty,  // Use converted quantity
		Quantity:   quantity, // Use converted quantity
		Timestamp:  time.Now().UnixNano(),
		OrderType:  orderbook.OrderType(t.OrderType),
		OrderMode:  orderMode, // Use converted mode (BASE_MODE for converted limit orders)
		IsCanceled: false,
		TPSL:       tpsl,
	}
}

type CancelContext struct {
	L1Owner common.Address `json:"l1owner"`
	OrderId common.Hash    `json:"orderId"` // typically tx hash or unique order hash
}

func (t *CancelContext) command() byte                  { return DexCommandCancel }
func (t *CancelContext) from() common.Address           { return t.L1Owner }
func (t *CancelContext) copy() DexCommandData           { return &CancelContext{t.L1Owner, t.OrderId} }
func (t *CancelContext) Serialize() ([]byte, error)     { return encode(t) }
func (t *CancelContext) Deserialize(input []byte) error { return json.Unmarshal(input, t) }
func (t *CancelContext) validate(sender common.Address, statedb BalanceGetter, orderbook orderbook.Dex, checker MarketChecker) error {
	if t.L1Owner == (common.Address{}) {
		return errors.New("from address is zero")
	}
	return t.validateBalance(statedb, orderbook)
}

func (t *CancelContext) validateBalance(statedb BalanceGetter, orderbook orderbook.Dex) error {
	orderId := t.OrderId

	// TODO-Orderbook: This is a temporary fix for TPSL order cancellation
	// TPSL orders (TP/SL) have predictable IDs (original order ID + 1 or 2 in last byte)
	// Check if this might be a conditional order by looking for the original order
	// This should be properly refactored to have a unified order validation system
	originalOrderId := orderId
	originalOrderId[31] = orderId[31] - 1  // Check if this is a TP order (original + 1)
	if _, hasOrder := orderbook.GetOrder(originalOrderId.Hex()); hasOrder {
		log.Info("CancelContext: Skipping validation for potential TP order", "orderId", orderId.Hex(), "originalOrderId", originalOrderId.Hex())
		return nil  // Original order exists, this might be a TP order - skip validation
	}
	
	originalOrderId[31] = orderId[31] - 2  // Check if this is a SL order (original + 2)
	if _, hasOrder := orderbook.GetOrder(originalOrderId.Hex()); hasOrder {
		log.Info("CancelContext: Skipping validation for potential SL order", "orderId", orderId.Hex(), "originalOrderId", originalOrderId.Hex())
		return nil  // Original order exists, this might be a SL order - skip validation
	}
	
	_, hasStopOrder := orderbook.GetStopOrder(orderId.Hex())
	if hasStopOrder {
		log.Info("CancelContext found stop order", "orderId", orderId)
		// TODO-Orderbook: validate stop order lock/unlock balance
		return nil
	}

	order, hasOrder := orderbook.GetOrder(orderId.Hex())
	if !hasOrder {
		log.Error("Order not found", "orderId", orderId)
		return fmt.Errorf("order not found: %v", orderId)
	}

	args, err := order.ToCancelArgs()
	if err != nil {
		log.Error("Failed to generate CancelArgs", "orderId", orderId, "error", err)
		return err
	}

	if statedb.GetLockedTokenBalance(args.From, args.Token).Cmp(args.Amount) < 0 {
		log.Warn("CancelContext failed: insufficient locked balance", "from", args.From.Hex(), "token", args.Token)
		return fmt.Errorf("insufficient locked balance for token %s", args.Token)
	}
	log.Info("CancelContext validation succeeded", "orderId", args.OrderId, "from", args.From, "token", args.Token, "amount", args.Amount)
	return nil
}

type CancelAllContext struct {
	L1Owner common.Address `json:"l1owner"`
}

func (t *CancelAllContext) command() byte                  { return DexCommandCancelAll }
func (t *CancelAllContext) from() common.Address           { return t.L1Owner }
func (t *CancelAllContext) copy() DexCommandData           { return &CancelAllContext{t.L1Owner} }
func (t *CancelAllContext) Serialize() ([]byte, error)     { return encode(t) }
func (t *CancelAllContext) Deserialize(input []byte) error { return json.Unmarshal(input, t) }
func (t *CancelAllContext) validate(sender common.Address, statedb BalanceGetter, orderbook orderbook.Dex, checker MarketChecker) error {
	if t.L1Owner == (common.Address{}) {
		return errors.New("from address is zero")
	}
	return t.validateBalance(statedb)
}

func (t *CancelAllContext) validateBalance(statedb BalanceGetter) error {
	return nil
}

type ModifyContext struct {
	L1Owner   common.Address `json:"l1owner"`
	OrderID   common.Hash    `json:"orderId"`   // 수정 대상 주문 ID
	NewPrice  *big.Int       `json:"newPrice"`  // 변경할 가격 (nil이면 변경 없음)
	NewQty    *big.Int       `json:"newQty"`    // 변경할 수량 (nil이면 변경 없음)
	OrderMode uint8          `json:"orderMode"` // 0: base mode (default), 1: quote mode

	// Internal field for quote mode conversion (not serialized)
	originalPrice *big.Int `json:"-"`
}

func (t *ModifyContext) command() byte        { return DexCommandModify }
func (t *ModifyContext) from() common.Address { return t.L1Owner }
func (t *ModifyContext) copy() DexCommandData {
	var newPriceCopy, newQtyCopy, originalPriceCopy *big.Int
	if t.NewPrice != nil {
		newPriceCopy = new(big.Int).Set(t.NewPrice)
	}
	if t.NewQty != nil {
		newQtyCopy = new(big.Int).Set(t.NewQty)
	}
	if t.originalPrice != nil {
		originalPriceCopy = new(big.Int).Set(t.originalPrice)
	}
	return &ModifyContext{t.L1Owner, t.OrderID, newPriceCopy, newQtyCopy, t.OrderMode, originalPriceCopy}
}
func (t *ModifyContext) Serialize() ([]byte, error)     { return encode(t) }
func (t *ModifyContext) Deserialize(input []byte) error { return json.Unmarshal(input, t) }
func (t *ModifyContext) validate(sender common.Address, statedb BalanceGetter, dex orderbook.Dex, checker MarketChecker) error {
	if t.L1Owner == (common.Address{}) {
		return errors.New("from address is zero")
	}
	if t.NewPrice == nil && t.NewQty == nil {
		return errors.New("new price and new quantity are nil")
	}
	if t.NewPrice != nil && t.NewPrice.Cmp(priceMax) > 0 {
		return errors.New("new price exceeds uint256 max value")
	}
	if t.NewQty != nil && t.NewQty.Cmp(quantityMax) > 0 {
		return errors.New("new quantity exceeds uint256 max value")
	}

	// Get order to determine symbol for market rules
	orderId := t.OrderID.Hex()
	order, hasOrder := dex.GetOrder(orderId)

	if !hasOrder {
		log.Error("Order not found for modify", "orderId", orderId)
		return fmt.Errorf("order not found: %v", orderId)
	}

	// Market rules validation for modify
	marketRules := dex.GetMarketRules(order.Symbol)

	// Calculate already executed quantity
	executedQty := new(big.Int).Sub(order.OrigQty.ToBig(), order.Quantity.ToBig())

	// Determine final price for validation
	var finalPrice *uint256.Int
	if t.NewPrice != nil {
		finalPrice = uint256.MustFromBig(t.NewPrice)
		// Validate new price tick size
		if err := marketRules.ValidateOrderPrice(finalPrice); err != nil {
			return fmt.Errorf("new price validation failed: %v", err)
		}
	} else {
		finalPrice = order.Price
	}

	// Case 1: Only price change
	if t.NewPrice != nil && t.NewQty == nil {
		// Check if remaining quantity is valid for new price's lot size
		remainingQty := order.Quantity

		// Get lot size for new price
		newLotSize := marketRules.GetLotSize(finalPrice)
		remainder := new(uint256.Int)
		remainder.Mod(remainingQty, newLotSize)

		if !remainder.IsZero() {
			return fmt.Errorf("remaining quantity %s is not divisible by lot size %s at new price %s",
				remainingQty,
				newLotSize,
				finalPrice)
		}

		// Validate minimum order value with new price
		if err := marketRules.ValidateMinimumOrderValue(finalPrice, remainingQty); err != nil {
			return err
		}
	}

	// Case 2: Quantity change (with or without price change)
	if t.NewQty != nil {
		// Check new quantity is greater than executed
		if t.NewQty.Cmp(executedQty) <= 0 {
			return fmt.Errorf("new quantity %s must be greater than executed quantity %s",
				t.NewQty.String(), executedQty.String())
		}

		// Calculate remaining quantity after modify
		remainingAfterModify := new(big.Int).Sub(t.NewQty, executedQty)

		// Convert quote mode to base for validation
		if t.OrderMode == 1 { // QUOTE_MODE
			remainingAfterModify = common.BigIntDivScaledDecimal(remainingAfterModify, finalPrice.ToBig())
		}
		remainingUint := uint256.MustFromBig(remainingAfterModify)

		// Validate remaining quantity against lot size
		if err := marketRules.ValidateOrderQuantity(finalPrice, remainingUint); err != nil {
			return fmt.Errorf("remaining quantity after modify validation failed: %v", err)
		}

		// Validate minimum order value
		if err := marketRules.ValidateMinimumOrderValue(finalPrice, remainingUint); err != nil {
			return err
		}
	}
	return t.validateBalance(statedb, dex)
}

func (t *ModifyContext) validateBalance(statedb BalanceGetter, dispatcher orderbook.Dex) error {
	orderId := t.OrderID.Hex()
	_, exist := dispatcher.GetStopOrder(orderId)
	if exist {
		log.Error("StopOrder cannot be modified", "orderId", orderId)
		return fmt.Errorf("stop order cannot be modified: %v", orderId)
	}

	order, hasOrder := dispatcher.GetOrder(orderId)
	if !hasOrder {
		log.Error("Order not found for modify", "orderId", orderId)
		return fmt.Errorf("order not found: %v", orderId)
	}

	if order.UserID != t.L1Owner.Hex() {
		log.Error("ModifyContext user mismatch", "expected", order.UserID, "got", t.L1Owner.Hex())
		return fmt.Errorf("user mismatch: expected %s, got %s", order.UserID, t.L1Owner.Hex())
	}

	// Store original price for quote mode conversion later
	t.originalPrice = order.Price.ToBig()

	baseToken, quoteToken, _ := orderbook.SymbolToTokens(order.Symbol)
	isQuoteMode := orderbook.OrderMode(t.OrderMode) == orderbook.QUOTE_MODE

	// Calculate the executed amount (in base tokens)
	executedBase := new(big.Int).Sub(order.OrigQty.ToBig(), order.Quantity.ToBig())

	// Three cases to handle:
	// Case 1: Only NewQty provided (NewPrice is nil)
	// Case 2: Only NewPrice provided (NewQty is nil)
	// Case 3: Both NewQty and NewPrice provided

	var finalPriceToUse *big.Int
	var finalQtyInBase *big.Int

	// Determine the final price to use
	if t.NewPrice != nil && t.NewPrice.Sign() > 0 {
		finalPriceToUse = t.NewPrice
	} else {
		finalPriceToUse = order.Price.ToBig()
	}

	// Determine the final quantity in base tokens
	if t.NewQty != nil {
		if isQuoteMode {
			if finalPriceToUse.Sign() <= 0 {
				return fmt.Errorf("price must be positive to modify a quote mode order")
			}
			// Convert quote quantity to base using the final price
			finalQtyInBase = common.BigIntDivScaledDecimal(t.NewQty, finalPriceToUse)
		} else {
			// Already in base mode
			finalQtyInBase = t.NewQty
		}

		// Check if new quantity is less than executed amount
		if finalQtyInBase.Cmp(executedBase) < 0 {
			log.Error("ModifyContext new quantity is less than executed", "newQtyInBase", finalQtyInBase, "executed", executedBase)
			return fmt.Errorf("new quantity %s is less than executed %s", finalQtyInBase, executedBase)
		}
	} else {
		// No new quantity provided, use original quantity
		finalQtyInBase = order.OrigQty.ToBig()
	}

	// Calculate balance requirements based on order side
	if order.Side == orderbook.BUY {
		// For BUY orders: need to check quote token requirements
		// New cost = finalQtyInBase * finalPriceToUse
		// Old cost = order.OrigQty * order.Price (what's currently locked)

		newCost := common.BigIntMulScaledDecimal(finalPriceToUse, finalQtyInBase)
		oldCost := common.BigIntMulScaledDecimal(order.Price.ToBig(), order.OrigQty.ToBig())

		diff := new(big.Int).Sub(newCost, oldCost)
		if diff.Sign() > 0 {
			// Need more quote tokens
			availableBalance := statedb.GetTokenBalance(t.L1Owner, quoteToken)
			if availableBalance.Cmp(uint256.MustFromBig(diff)) < 0 {
				log.Error("ModifyContext insufficient quote balance",
					"from", t.L1Owner.Hex(),
					"token", quoteToken,
					"needed", diff,
					"available", availableBalance.Dec())
				return fmt.Errorf("insufficient %s balance: have %s, need %s",
					quoteToken, availableBalance.Dec(), uint256.MustFromBig(diff).Dec())
			}
		}
		// If diff <= 0, we're reducing the order or keeping same cost, so no additional balance needed

	} else { // SELL order
		// For SELL orders: need to check base token requirements
		// New requirement = finalQtyInBase
		// Old requirement = order.OrigQty (what's currently locked)

		diff := new(big.Int).Sub(finalQtyInBase, order.OrigQty.ToBig())
		if diff.Sign() > 0 {
			// Need more base tokens
			availableBalance := statedb.GetTokenBalance(t.L1Owner, baseToken)
			if availableBalance.Cmp(uint256.MustFromBig(diff)) < 0 {
				log.Error("ModifyContext insufficient base balance",
					"from", t.L1Owner.Hex(),
					"token", baseToken,
					"needed", diff,
					"available", availableBalance.Dec())
				return fmt.Errorf("insufficient %s balance: have %s, need %s",
					baseToken, availableBalance.Dec(), uint256.MustFromBig(diff).Dec())
			}
		}
		// If diff <= 0, we're reducing the order, so no additional balance needed
	}

	return nil
}

func (t *ModifyContext) ToModifyArgsV2(newOrderId string) *types.ModifyArgs {
	var price *uint256.Int
	var qty *uint256.Int

	if t.NewPrice != nil {
		price = uint256.MustFromBig(t.NewPrice)
	}
	if t.NewQty != nil {
		qty = uint256.MustFromBig(t.NewQty)

		// For quote mode, convert quantity to base
		// Note: We can only modify limit orders, so we always have a price
		if types.OrderMode(t.OrderMode) == types.QUOTE_MODE { // QUOTE_MODE
			// Determine which price to use for conversion
			var priceForConversion *uint256.Int
			if t.NewPrice != nil && t.NewPrice.Sign() > 0 {
				// Use new price if provided
				priceForConversion = price
			} else {
				// Use original price if new price not provided
				priceForConversion = uint256.MustFromBig(t.originalPrice)
			}
			// Convert quote quantity to base quantity: base_qty = quote_qty / price
			qty = common.Uint256DivScaledDecimal(qty, priceForConversion)
		}
	}

	return types.NewModifyArgs(
		types.OrderID(t.OrderID.Hex()),
		types.OrderID(newOrderId),
		types.UserID(t.L1Owner.Hex()),
		price,
		qty,
	)
}

func (t *ModifyContext) ToModifyArgs(newOrderId string) *orderbook.ModifyArgs {
	var price *uint256.Int
	var qty *uint256.Int

	if t.NewPrice != nil {
		price = uint256.MustFromBig(t.NewPrice)
	}
	if t.NewQty != nil {
		qty = uint256.MustFromBig(t.NewQty)

		// For quote mode, convert quantity to base
		// Note: We can only modify limit orders, so we always have a price
		if orderbook.OrderMode(t.OrderMode) == orderbook.QUOTE_MODE { // QUOTE_MODE
			// Determine which price to use for conversion
			var priceForConversion *uint256.Int
			if t.NewPrice != nil && t.NewPrice.Sign() > 0 {
				// Use new price if provided
				priceForConversion = price
			} else {
				// Use original price if new price not provided
				priceForConversion = uint256.MustFromBig(t.originalPrice)
			}
			// Convert quote quantity to base quantity: base_qty = quote_qty / price
			qty = common.Uint256DivScaledDecimal(qty, priceForConversion)
		}
	}

	return &orderbook.ModifyArgs{
		OrderId:    t.OrderID.Hex(),
		From:       t.L1Owner,
		NewPrice:   price,
		NewQty:     qty,
		NewOrderId: newOrderId,
	}
}

type StopOrderContext struct {
	L1Owner    common.Address `json:"l1owner"`
	BaseToken  string         `json:"baseToken"`
	QuoteToken string         `json:"quoteToken"`
	StopPrice  *big.Int       `json:"stopPrice"`
	Price      *big.Int       `json:"price"`
	Quantity   *big.Int       `json:"quantity"`
	Side       uint8          `json:"side"`
	OrderType  uint8          `json:"orderType"`
	OrderMode  uint8          `json:"orderMode"` // 0: base mode (default), 1: quote mode
}

func (t *StopOrderContext) command() byte        { return DexCommandStopOrder }
func (t *StopOrderContext) from() common.Address { return t.L1Owner }
func (t *StopOrderContext) copy() DexCommandData {
	var stopPriceCopy, priceCopy, quantityCopy *big.Int
	if t.StopPrice != nil {
		stopPriceCopy = new(big.Int).Set(t.StopPrice)
	}
	if t.Price != nil {
		priceCopy = new(big.Int).Set(t.Price)
	}
	if t.Quantity != nil {
		quantityCopy = new(big.Int).Set(t.Quantity)
	}
	return &StopOrderContext{t.L1Owner, t.BaseToken, t.QuoteToken, stopPriceCopy, priceCopy, quantityCopy, t.Side, t.OrderType, t.OrderMode}
}
func (t *StopOrderContext) Serialize() ([]byte, error)     { return encode(t) }
func (t *StopOrderContext) Deserialize(input []byte) error { return json.Unmarshal(input, t) }
func (t *StopOrderContext) validate(sender common.Address, statedb BalanceGetter, dex orderbook.Dex, checker MarketChecker) error {
	if t.L1Owner == (common.Address{}) {
		return errors.New("from address is zero")
	}
	if t.BaseToken == "" || t.QuoteToken == "" {
		return errors.New("base token or quote token is empty")
	}
	baseTokenId, err := strconv.ParseUint(t.BaseToken, 10, 64)
	if err != nil {
		return errors.New("base token must be a 64-bit unsigned integer")
	}
	quoteTokenId, err := strconv.ParseUint(t.QuoteToken, 10, 64)
	if err != nil {
		return errors.New("quote token must be a 64-bit unsigned integer")
	}
	exist, err := checker.ContainsMarket(baseTokenId, quoteTokenId)
	if err != nil {
		return err
	}
	if !exist {
		return fmt.Errorf("market does not exist. base: %v, quote: %v", baseTokenId, quoteTokenId)
	}
	if len(t.BaseToken) > MaxTokenLength || len(t.QuoteToken) > MaxTokenLength {
		return errors.New("base token or quote token is too long")
	}
	if t.Side != 0 && t.Side != 1 {
		return errors.New("invalid side: must be 0 (buy) or 1 (sell)")
	}
	if t.StopPrice == nil || t.StopPrice.Sign() <= 0 {
		return errors.New("stop price must be set for stop-limit order")
	}
	if t.OrderType != LIMIT && t.OrderType != MARKET {
		return errors.New("invalid order type: must be 0 (limit) or 1 (market)")
	}
	if t.OrderType == LIMIT && (t.Price == nil || t.Price.Sign() <= 0) {
		return errors.New("limit price must be set for stop-limit order")
	}
	if t.Quantity == nil || t.Quantity.Sign() <= 0 {
		return errors.New("quantity must be positive")
	}
	if t.OrderType != 0 && t.OrderType != 1 {
		return errors.New("invalid order type: must be 0 (limit) or 1 (market)")
	}
	if t.StopPrice != nil && t.StopPrice.Cmp(priceMax) > 0 {
		return errors.New("stop price exceeds uint256 max value")
	}
	if t.Price != nil && t.Price.Cmp(priceMax) > 0 {
		return errors.New("price exceeds uint256 max value")
	}
	if t.Quantity != nil && t.Quantity.Cmp(quantityMax) > 0 {
		return errors.New("quantity exceeds uint256 max value")
	}

	// Market rules validation for stop orders
	symbol := t.BaseToken + "/" + t.QuoteToken
	marketRules := dex.GetMarketRules(symbol)

	if t.OrderType == MARKET {
		// For market stop orders, validate using stop price as reference
		bestPrice := uint256.MustFromBig(t.StopPrice)
		if err := marketRules.ValidateMarketOrder(
			uint256.MustFromBig(t.Quantity),
			bestPrice,
			orderbook.Side(t.Side),
			orderbook.OrderMode(t.OrderMode),
		); err != nil {
			return fmt.Errorf("stop market order validation failed: %v", err)
		}
	} else if t.OrderType == LIMIT {
		// Validate stop trigger price
		stopPriceUint := uint256.MustFromBig(t.StopPrice)
		if err := marketRules.ValidateOrderPrice(stopPriceUint); err != nil {
			return fmt.Errorf("stop price validation failed: %v", err)
		}

		// Validate limit price
		priceUint := uint256.MustFromBig(t.Price)
		if err := marketRules.ValidateOrderPrice(priceUint); err != nil {
			return fmt.Errorf("limit price validation failed: %v", err)
		}

		// Quantity lot size validation (convert quote mode to base for validation)
		qty := t.Quantity
		if t.OrderMode == 1 { // QUOTE_MODE
			qty = common.BigIntDivScaledDecimal(t.Quantity, t.Price)
		}
		qtyUint := uint256.MustFromBig(qty)

		if err := marketRules.ValidateOrderQuantity(priceUint, qtyUint); err != nil {
			return fmt.Errorf("quantity validation failed: %v", err)
		}

		// Minimum order value validation
		if err := marketRules.ValidateMinimumOrderValue(priceUint, qtyUint); err != nil {
			return err
		}
	}

	return t.validateBalance(statedb)
}

func (t *StopOrderContext) validateBalance(statedb BalanceGetter) error {
	isQuoteMode := orderbook.OrderMode(t.OrderMode) == orderbook.QUOTE_MODE

	switch t.Side {
	case BUY:
		var lockAmount *big.Int
		if isQuoteMode {
			// In quote mode: quantity represents quote tokens to spend
			lockAmount = new(big.Int).Set(t.Quantity)
		} else {
			// In base mode: calculate quote needed based on price
			if t.OrderType == LIMIT {
				lockAmount = common.BigIntMulScaledDecimal(t.Price, t.Quantity)
			} else if t.OrderType == MARKET {
				lockAmount = common.BigIntMulScaledDecimal(t.StopPrice, t.Quantity)
			} else {
				log.Error("Unsupported stop BUY order type", "orderType", t.OrderType)
				return fmt.Errorf("unsupported stop BUY order type: %v", t.OrderType)
			}
		}
		bal := statedb.GetTokenBalance(t.L1Owner, t.QuoteToken)
		if bal.ToBig().Cmp(lockAmount) < 0 {
			return fmt.Errorf("insufficient %s balance: have %s, need %s", t.QuoteToken, bal.Dec(), lockAmount)
		}
	case SELL:
		var lockAmount *big.Int
		if isQuoteMode {
			// In quote mode: need to calculate base tokens required
			// base_amount = quote_amount / price
			if t.OrderType == LIMIT && t.Price != nil && t.Price.Sign() > 0 {
				lockAmount = common.BigIntDivScaledDecimal(t.Quantity, t.Price)
			} else if t.OrderType == MARKET && t.StopPrice != nil && t.StopPrice.Sign() > 0 {
				lockAmount = common.BigIntDivScaledDecimal(t.Quantity, t.StopPrice)
			} else {
				return fmt.Errorf("invalid price for quote mode SELL stop order")
			}
		} else {
			// In base mode: quantity is already in base tokens
			lockAmount = new(big.Int).Set(t.Quantity)
		}
		bal := statedb.GetTokenBalance(t.L1Owner, t.BaseToken)
		if bal.ToBig().Cmp(lockAmount) < 0 {
			return fmt.Errorf("insufficient %s balance: have %s, need %s", t.BaseToken, bal.Dec(), lockAmount)
		}
	default:
		return fmt.Errorf("unsupported order side: %v", t.Side)
	}
	return nil
}

func (t *StopOrderContext) ToStopOrder2(txHash common.Hash) *types.StopOrder {
	// Convert quote mode to base mode for limit orders
	quantity := uint256.MustFromBig(t.Quantity)
	origQty := uint256.MustFromBig(t.Quantity)
	orderMode := types.OrderMode(t.OrderMode)
	orderType := types.OrderType(t.OrderType)

	// For limit stop orders in quote mode, convert quantities to base
	if orderMode == types.QUOTE_MODE && t.OrderType == LIMIT { // QUOTE_MODE && LIMIT
		if t.Price != nil && t.Price.Sign() > 0 {
			// Convert quote quantity to base quantity: base_qty = quote_qty / price
			priceUint := uint256.MustFromBig(t.Price)
			quantity = common.Uint256DivScaledDecimal(quantity, priceUint)
			origQty = quantity
			// After conversion, treat as base mode internally
			orderMode = types.BASE_MODE
		}
	}
	// Convert order type to stop order
	if t.OrderType == LIMIT {
		orderType = types.STOP_LIMIT
	} else if t.OrderType == MARKET {
		orderType = types.STOP_MARKET
	}

	order := types.NewOrder(
		types.OrderID(txHash.Hex()),
		types.UserID(t.L1Owner.Hex()),
		types.Symbol(t.BaseToken+"/"+t.QuoteToken),
		types.OrderSide(t.Side),
		orderMode,
		orderType,
		uint256.MustFromBig(t.Price),
		origQty, // Use converted quantity
		nil,
	)

	return types.NewStopOrder(order, uint256.MustFromBig(t.StopPrice))
}

func (t *StopOrderContext) ToStopOrder(txHash common.Hash) *orderbook.StopOrder {
	// Convert quote mode to base mode for limit orders
	quantity := uint256.MustFromBig(t.Quantity)
	origQty := uint256.MustFromBig(t.Quantity)
	orderMode := orderbook.OrderMode(t.OrderMode)

	// For limit stop orders in quote mode, convert quantities to base
	if t.OrderMode == 1 && t.OrderType == LIMIT { // QUOTE_MODE && LIMIT
		if t.Price != nil && t.Price.Sign() > 0 {
			// Convert quote quantity to base quantity: base_qty = quote_qty / price
			priceUint := uint256.MustFromBig(t.Price)
			quantity = common.Uint256DivScaledDecimal(quantity, priceUint)
			origQty = quantity
			// After conversion, treat as base mode internally
			orderMode = orderbook.BASE_MODE
		}
	}
	// Note: Market stop orders in quote mode keep their original mode and quantity

	return &orderbook.StopOrder{
		Order: &orderbook.Order{
			OrderID:    txHash.Hex(),
			UserID:     t.L1Owner.Hex(),
			Symbol:     t.BaseToken + "/" + t.QuoteToken,
			Side:       orderbook.Side(t.Side),
			Price:      uint256.MustFromBig(t.Price),
			Quantity:   quantity, // Use converted quantity
			OrigQty:    origQty,  // Use converted quantity
			OrderType:  orderbook.OrderType(t.OrderType),
			OrderMode:  orderMode, // Use converted mode
			Timestamp:  time.Now().UnixNano(),
			IsCanceled: false,
		},
		StopPrice: uint256.MustFromBig(t.StopPrice),
	}
}
