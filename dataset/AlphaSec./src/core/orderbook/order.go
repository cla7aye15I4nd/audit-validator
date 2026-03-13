package orderbook

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/holiman/uint256"
)

// -- Types and Constants --

// Conditional order ID increments
const (
	TPIncrement byte = 1 // TPSL TP order
	SLIncrement byte = 2 // TPSL SL order
)

// GenerateConditionalOrderID generates unique IDs for conditional orders
// by modifying the last byte of the transaction hash
func GenerateConditionalOrderID(txHash common.Hash, increment byte) string {
	modifiedHash := txHash
	modifiedHash[31] = txHash[31] + increment // Natural byte overflow
	return modifiedHash.Hex()
}

type Side uint8

func Opposite(side Side) Side {
	if side == BUY {
		return SELL
	}
	return BUY
}

func (s Side) String() string {
	switch s {
	case BUY:
		return "BUY"
	case SELL:
		return "SELL"
	default:
		return "UNKNOWN"
	}
}

type OrderType uint8

func (o OrderType) String() string {
	switch o {
	case LIMIT:
		return "LIMIT"
	case MARKET:
		return "MARKET"
	default:
		return "UNKNOWN"
	}
}

type OrderMode uint8

func (m OrderMode) String() string {
	switch m {
	case BASE_MODE:
		return "BASE_MODE"
	case QUOTE_MODE:
		return "QUOTE_MODE"
	default:
		return "UNKNOWN"
	}
}

type TriggerType uint8

func (t TriggerType) String() string {
	switch t {
	case TAKEPROFIT:
		return "TAKEPROFIT"
	case STOPLOSS:
		return "STOPLOSS"
	case STOPLIMIT:
		return "STOPLIMIT"
	default:
		return "UNKNOWN"
	}
}

type RequestType string

const (
	BUY        Side        = 0
	SELL       Side        = 1
	LIMIT      OrderType   = 0
	MARKET     OrderType   = 1
	BASE_MODE  OrderMode   = 0 // Default mode - quantities in base token
	QUOTE_MODE OrderMode   = 1 // Quote mode - quantities in quote token
	TAKEPROFIT TriggerType = 0 // Take Profit
	STOPLOSS   TriggerType = 1 // Stop Loss
	STOPLIMIT  TriggerType = 2 // Stop Limit
)

var (
	TopicTrades       = crypto.Keccak256Hash([]byte("Trades"))            // 0xd37cc1c23d72518afd1e7a67fe42c7d9c5db40d646c2d5dfc324683baede635e
	TopicCancel       = crypto.Keccak256Hash([]byte("Cancel"))            // 0x8c11276ab4208c28a9c53122199d5bcecbc5041a008b5263db3cc3c06411cc5b
	TopicCanceledIds  = crypto.Keccak256Hash([]byte("CanceledIds"))       // 0x46fbbe6e6251d0d9a80a52b6f14e2d466a9aca2578e5103c192e66ccc6786f94
	TopicTriggeredIds = crypto.Keccak256Hash([]byte("TriggeredIds"))      // 0xc9cb97f5d3b4cf5158af621cf9753fcbc4ef2c46efa310cb3083676e6f8f6fee
	TopicTriggerAbove = crypto.Keccak256Hash([]byte("TopicTriggerAbove")) // 0xd5bfcf6006131052eae3f479eb1da700d54890149ccfe08214f53596148bd59a
)

type Aggregated struct {
	BlockNumber uint64     `json:"block"`
	Symbol      string     `json:"symbol"`
	Bids        [][]string `json:"bids"`
	Asks        [][]string `json:"asks"`
}

type DepthUpdate struct {
	Stream string     `json:"stream"` // Stream name (e.g., "bandusdt@depth")
	Data   *DeltaData `json:"data"`
}

type DeltaData struct {
	EventType string     `json:"e"` // Event type
	EventTime int64      `json:"E"` // Event time
	Symbol    string     `json:"s"` // Symbol (e.g., "KAIA/USDT")
	FirstID   string     `json:"U"` // First update ID in event
	FinalID   string     `json:"u"` // Final update ID in event
	Bids      [][]string `json:"b"` // Bids (price and quantity)
	Asks      [][]string `json:"a"` // Asks (price and quantity)
}

func (d *DepthUpdate) Serialize() ([]byte, error) {
	return json.Marshal(d)
}

type TriggeredOrder struct {
	order       *Order
	TriggerType TriggerType
}

type Order struct {
	OrderID    string
	UserID     string
	Symbol     string
	Side       Side
	Price      *uint256.Int
	OrigQty    *uint256.Int
	Quantity   *uint256.Int
	Timestamp  int64
	Index      int
	OrderType  OrderType
	OrderMode  OrderMode  // BASE_MODE or QUOTE_MODE
	IsCanceled bool
	TPSL       *TPSLOrder
}

func (o *Order) Copy() *Order {
	copied := &Order{
		OrderID:    o.OrderID,
		UserID:     o.UserID,
		Symbol:     o.Symbol,
		Side:       o.Side,
		Timestamp:  o.Timestamp,
		Index:      o.Index,
		OrderType:  o.OrderType,
		OrderMode:  o.OrderMode,
		IsCanceled: o.IsCanceled,
	}
	
	// Deep copy uint256.Int fields if not nil
	if o.Price != nil {
		copied.Price = new(uint256.Int).Set(o.Price)
	}
	if o.OrigQty != nil {
		copied.OrigQty = new(uint256.Int).Set(o.OrigQty)
	}
	if o.Quantity != nil {
		copied.Quantity = new(uint256.Int).Set(o.Quantity)
	}
	
	// Deep copy TPSL if present
	if o.TPSL != nil {
		copied.TPSL = o.TPSL.Copy()
	}
	
	return copied
}

type TPSLOrder struct {
	TPOrder  *StopOrder
	SLOrder  *StopOrder
	submitted bool // True after TP order has been submitted to orderbook
}

func (t *TPSLOrder) Copy() *TPSLOrder {
	if t == nil {
		return nil
	}
	
	copied := &TPSLOrder{
		submitted: t.submitted,
	}
	
	if t.TPOrder != nil {
		copied.TPOrder = t.TPOrder.Copy()
	}
	
	if t.SLOrder != nil {
		copied.SLOrder = t.SLOrder.Copy()
	}
	
	return copied
}

type StopOrder struct {
	Order        *Order
	StopPrice    *uint256.Int
	TriggerAbove bool
}

func (s *StopOrder) Copy() *StopOrder {
	if s == nil {
		return nil
	}
	
	copied := &StopOrder{
		TriggerAbove: s.TriggerAbove,
	}
	
	if s.Order != nil {
		// Use the Order's Copy method but avoid infinite recursion
		// by not copying the TPSL field in the nested order
		orderCopy := &Order{
			OrderID:    s.Order.OrderID,
			UserID:     s.Order.UserID,
			Symbol:     s.Order.Symbol,
			Side:       s.Order.Side,
			Timestamp:  s.Order.Timestamp,
			Index:      s.Order.Index,
			OrderType:  s.Order.OrderType,
			OrderMode:  s.Order.OrderMode,
			IsCanceled: s.Order.IsCanceled,
			// Intentionally not copying TPSL to avoid circular reference
		}
		
		// Deep copy uint256.Int fields if not nil
		if s.Order.Price != nil {
			orderCopy.Price = new(uint256.Int).Set(s.Order.Price)
		}
		if s.Order.OrigQty != nil {
			orderCopy.OrigQty = new(uint256.Int).Set(s.Order.OrigQty)
		}
		if s.Order.Quantity != nil {
			orderCopy.Quantity = new(uint256.Int).Set(s.Order.Quantity)
		}
		copied.Order = orderCopy
	}
	
	if s.StopPrice != nil {
		copied.StopPrice = new(uint256.Int).Set(s.StopPrice)
	}
	
	return copied
}

type Trade struct {
	Symbol          string
	BuyOrderID      string
	SellOrderID     string
	BuyOrderFilled  bool
	SellOrderFilled bool
	MakerID         string
	TakerID         string
	Price           *uint256.Int
	Quantity        *uint256.Int
	Timestamp       uint64
	BuyFeeTokenID   string
	BuyFeeAmount    *uint256.Int
    SellFeeTokenID  string
    SellFeeAmount   *uint256.Int
	IsBuyerMaker    bool `rlp:"-"`
}

// Copy creates a deep copy of Trade
func (t *Trade) Copy() *Trade {
	if t == nil {
		return nil
	}
	
	copied := &Trade{
		Symbol:          t.Symbol,
		BuyOrderID:      t.BuyOrderID,
		SellOrderID:     t.SellOrderID,
		BuyOrderFilled:  t.BuyOrderFilled,
		SellOrderFilled: t.SellOrderFilled,
		MakerID:         t.MakerID,
		TakerID:         t.TakerID,
		Timestamp:       t.Timestamp,
		IsBuyerMaker:    t.IsBuyerMaker,
	}
	
	if t.Price != nil {
		copied.Price = new(uint256.Int).Set(t.Price)
	}
	
	if t.Quantity != nil {
		copied.Quantity = new(uint256.Int).Set(t.Quantity)
	}
	
	return copied
}

func (t *Trade) Serialize() ([]byte, error) {
	return rlp.EncodeToBytes(t)
}

type OrderIds []string

func (c *OrderIds) Serialize() ([]byte, error) {
	return rlp.EncodeToBytes(c)
}

type CancelArgs struct {
	OrderId string
	From    common.Address
	Token   string
	Amount  *uint256.Int
}

func (o *Order) ToCancelArgs() (*CancelArgs, error) {
	// Market orders should never be canceled
	if o.OrderType == MARKET {
		return nil, ErrMarketOrderCannotCancel
	}

	baseToken, quoteToken, err := SymbolToTokens(o.Symbol)
	if err != nil {
		return nil, err
	}

	var token string
	var amount *uint256.Int

	// Handle based on order side first
	switch o.Side {
	case BUY:
		token = quoteToken
		if o.OrderMode == QUOTE_MODE {
			// Buy in quote mode: locked quote amount is the quantity itself
			amount = o.Quantity
		} else { // BASE_MODE
			// Buy in base mode: locked quote amount = base_quantity * price
			// Check for valid price (should always be valid for limit orders)
			if o.Price == nil || o.Price.Sign() == 0 {
				return nil, fmt.Errorf("invalid price for BASE_MODE BUY order")
			}
			amount = common.Uint256MulScaledDecimal(o.Quantity, o.Price)
		}
	case SELL:
		token = baseToken
		if o.OrderMode == QUOTE_MODE {
			// Sell in quote mode: locked base amount needs to be calculated
			// base_amount = quote_quantity / price
			// Check for valid price to avoid division by zero
			if o.Price == nil || o.Price.Sign() == 0 {
				return nil, fmt.Errorf("invalid price for QUOTE_MODE SELL order")
			}
			amount = common.Uint256DivScaledDecimal(o.Quantity, o.Price)
		} else { // BASE_MODE
			// Sell in base mode: locked base amount is the quantity itself
			amount = o.Quantity
		}
	default:
		return nil, fmt.Errorf("invalid order side: %d", o.Side)
	}

	return &CancelArgs{
		OrderId: o.OrderID,
		From:    common.HexToAddress(o.UserID),
		Token:   token,
		Amount:  amount,
	}, nil
}

type ModifyArgs struct {
	OrderId    string
	From       common.Address
	NewPrice   *uint256.Int
	NewQty     *uint256.Int
	NewOrderId string // New order ID for the modified order (modify tx hash)
}

// Copy creates a deep copy of ModifyArgs
func (m *ModifyArgs) Copy() *ModifyArgs {
	if m == nil {
		return nil
	}
	
	copied := &ModifyArgs{
		OrderId:    m.OrderId,
		From:       m.From,
		NewOrderId: m.NewOrderId,
	}
	
	if m.NewPrice != nil {
		copied.NewPrice = new(uint256.Int).Set(m.NewPrice)
	}
	
	if m.NewQty != nil {
		copied.NewQty = new(uint256.Int).Set(m.NewQty)
	}
	
	return copied
}

// SymbolToTokens converts a symbol string to its token addresses.
// It assumes the symbol is in the format "BaseToken/QuoteToken".
func SymbolToTokens(symbol string) (string, string, error) {
	tokens := strings.Split(symbol, "/")
	if len(tokens) != 2 || tokens[0] == "" || tokens[1] == "" {
		return "", "", fmt.Errorf("invalid symbol format: %s", symbol)
	}
	return tokens[0], tokens[1], nil
}

func SymbolToTokenIds(symbol string) (uint64, uint64, error) {
	base, quote, err := SymbolToTokens(symbol)
	if err != nil {
		return 0, 0, err
	}

	baseId, err := strconv.ParseUint(base, 10, 64)
	if err != nil {
		return 0, 0, err
	}

	quoteId, err := strconv.ParseUint(quote, 10, 64)
	if err != nil {
		return 0, 0, err
	}
	return baseId, quoteId, nil
}
