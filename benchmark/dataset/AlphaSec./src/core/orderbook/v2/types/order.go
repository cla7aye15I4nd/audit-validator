package types

import (
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/holiman/uint256"
)

// OrderID is a unique identifier for an order
type OrderID string

type OrderIDs []OrderID

// Serialize encodes OrderIds using RLP
func (o *OrderIDs) Serialize() ([]byte, error) {
	return rlp.EncodeToBytes(o)
}

// FailedOrder represents an order that failed with its reason
type FailedOrder struct {
	OrderID OrderID `json:"orderID"`
	Reason  string  `json:"reason"`
}

// FailedOrders is a slice of failed orders
type FailedOrders []FailedOrder

// Serialize encodes FailedOrders using RLP
func (f *FailedOrders) Serialize() ([]byte, error) {
	return rlp.EncodeToBytes(f)
}

// Deserialize decodes FailedOrders from RLP
func (f *FailedOrders) Deserialize(data []byte) error {
	return rlp.DecodeBytes(data, f)
}

// UserID is a unique identifier for a user (address)
type UserID string

// Symbol represents a trading pair (e.g., "BTC/USDT")
type Symbol string

// Constants for conditional order ID generation
const (
	TPIncrement byte = 1 // Take-Profit order increment
	SLIncrement byte = 2 // Stop-Loss order increment
)

// GenerateConditionalOrderID generates unique IDs for conditional orders
// by modifying the last byte of the transaction hash.
// This is the legacy-compatible way to generate TPSL order IDs.
func GenerateConditionalOrderID(txHash common.Hash, increment byte) string {
	modifiedHash := txHash
	modifiedHash[31] = txHash[31] + increment // Natural byte overflow
	return modifiedHash.Hex()
}

// GenerateTPOrderID generates a Take-Profit order ID from a base order ID
func GenerateTPOrderID(baseOrderID OrderID) OrderID {
	hash := common.HexToHash(string(baseOrderID))
	return OrderID(GenerateConditionalOrderID(hash, TPIncrement))
}

// GenerateSLOrderID generates a Stop-Loss order ID from a base order ID
func GenerateSLOrderID(baseOrderID OrderID) OrderID {
	hash := common.HexToHash(string(baseOrderID))
	return OrderID(GenerateConditionalOrderID(hash, SLIncrement))
}

// OrderType represents the type of order
type OrderType uint8

const (
	LIMIT OrderType = iota
	MARKET
	STOP_LIMIT
	STOP_MARKET
	TP_LIMIT
	SL_LIMIT
	SL_MARKET
)

// OrderSide represents buy or sell
type OrderSide uint8

const (
	BUY OrderSide = iota
	SELL
)

// OrderStatus represents the current state of an order
type OrderStatus uint8

const (
	NEW              OrderStatus = iota // Order created, not yet validated
	PENDING                             // Validated, waiting for matching or in orderbook
	PARTIALLY_FILLED                    // Partially executed
	FILLED                              // Fully executed
	CANCELLED                           // Cancelled by user
	REJECTED                            // Failed validation
	EXPIRED                             // Time expired
	TRIGGER_WAIT                        // Conditional order waiting for trigger
	TRIGGERED                           // Conditional order triggered, starting execution
)

// OrderMode represents how the order quantity is specified
type OrderMode uint8

const (
	BASE_MODE  OrderMode = iota // Quantity in base currency
	QUOTE_MODE                  // Quantity in quote currency
)

// Order represents a trading order
type Order struct {
	// Identity
	OrderID OrderID
	UserID  UserID
	Symbol  Symbol

	// Type and Side
	OrderType OrderType
	Side      OrderSide
	OrderMode OrderMode

	// Amounts
	Price    *uint256.Int // Limit price (nil for market orders)
	Quantity *uint256.Int // Remaining quantity
	OrigQty  *uint256.Int // Original quantity

	// Status
	Status    OrderStatus
	Timestamp int64

	// Internal fields
	Index int // Position in heap

	// Lock information (for Market orders)
	LockedAmount *uint256.Int // Amount locked for this order (quote for BUY, base for SELL)

	// TPSL fields (nil if not a TPSL order)
	TPSL *TPSLContext
}

// TPSLContext contains Take-Profit and Stop-Loss parameters
type TPSLContext struct {
	// Take Profit - limit price for TP order
	TPLimitPrice *uint256.Int

	// Stop Loss - trigger and limit prices
	SLTriggerPrice *uint256.Int
	SLLimitPrice   *uint256.Int // Optional: if nil, market order when triggered
}

// HasTPSL returns true if this order has TPSL attached
func (o *Order) HasTPSL() bool {
	return o.TPSL != nil
}

func (o *Order) IsPendingTP() bool {
	return o.OrderType.IsTP() && o.Status.IsPending()
}

// IsValidTPSL validates TPSL parameters
func (t *TPSLContext) IsValid(side OrderSide, currentPrice *uint256.Int) bool {
	if t == nil {
		return false
	}

	// Must have both TP and SL
	if t.TPLimitPrice == nil || t.SLTriggerPrice == nil {
		return false
	}

	// For BUY orders: TP > current > SL
	// For SELL orders: TP < current < SL
	if side == BUY {
		// TP should be higher than current price
		if currentPrice != nil && t.TPLimitPrice.Cmp(currentPrice) <= 0 {
			return false
		}
		// SL trigger should be lower than current price
		if currentPrice != nil && t.SLTriggerPrice.Cmp(currentPrice) >= 0 {
			return false
		}
	} else { // SELL
		// TP should be lower than current price
		if currentPrice != nil && t.TPLimitPrice.Cmp(currentPrice) >= 0 {
			return false
		}
		// SL trigger should be higher than current price
		if currentPrice != nil && t.SLTriggerPrice.Cmp(currentPrice) <= 0 {
			return false
		}
	}

	return true
}

// NewOrder creates a new order with basic validation
func NewOrder(orderID OrderID, userID UserID, symbol Symbol, side OrderSide, orderMode OrderMode, orderType OrderType, price, quantity *uint256.Int, tpsl *TPSLContext) *Order {
	now := time.Now().UnixNano()

	return &Order{
		OrderID:   orderID,
		UserID:    userID,
		Symbol:    symbol,
		OrderType: orderType,
		Side:      side,
		OrderMode: orderMode,
		Price:     price,
		Quantity:  quantity,
		OrigQty:   quantity.Clone(),
		Status:    NEW,
		Timestamp: now,
		Index:     -1,
		TPSL:      tpsl,
	}
}

func NewTPSL(tpLimit, slTrigger, slLimit *uint256.Int) *TPSLContext {
	return &TPSLContext{
		TPLimitPrice:   tpLimit,
		SLTriggerPrice: slTrigger,
		SLLimitPrice:   slLimit,
	}
}

// Copy creates a deep copy of the order
func (o *Order) Copy() *Order {
	if o == nil {
		return nil
	}

	copy := *o

	// Deep copy uint256 fields
	if o.Price != nil {
		copy.Price = o.Price.Clone()
	}
	if o.Quantity != nil {
		copy.Quantity = o.Quantity.Clone()
	}
	if o.OrigQty != nil {
		copy.OrigQty = o.OrigQty.Clone()
	}

	// Deep copy TPSL context
	if o.TPSL != nil {
		copy.TPSL = &TPSLContext{}
		if o.TPSL.TPLimitPrice != nil {
			copy.TPSL.TPLimitPrice = o.TPSL.TPLimitPrice.Clone()
		}
		if o.TPSL.SLTriggerPrice != nil {
			copy.TPSL.SLTriggerPrice = o.TPSL.SLTriggerPrice.Clone()
		}
		if o.TPSL.SLLimitPrice != nil {
			copy.TPSL.SLLimitPrice = o.TPSL.SLLimitPrice.Clone()
		}
	}

	return &copy
}

// IsActive returns true if the order can still be matched
func (o *Order) IsActive() bool {
	return o.Status == PENDING || o.Status == PARTIALLY_FILLED
}

// IsFilled returns true if the order is completely filled
func (o *Order) IsFilled() bool {
	return o.Status == FILLED || (o.Quantity != nil && o.Quantity.IsZero())
}

// FilledQuantity returns the amount that has been filled
func (o *Order) FilledQuantity() *uint256.Int {
	if o.OrigQty == nil || o.Quantity == nil {
		return uint256.NewInt(0)
	}
	return new(uint256.Int).Sub(o.OrigQty, o.Quantity)
}

// CanCancel returns true if the order can be cancelled
func (o *Order) CanCancel() bool {
	return o.Status == PENDING || o.Status == PARTIALLY_FILLED || o.Status == TRIGGER_WAIT
}

// UpdateStatus updates the order status based on quantity
func (o *Order) UpdateStatus() {
	if o.Status == REJECTED || o.Status == CANCELLED || o.Status == EXPIRED {
		return // Terminal states
	}

	if o.Quantity != nil && o.Quantity.IsZero() {
		o.Status = FILLED
	} else if o.FilledQuantity().Sign() > 0 {
		o.Status = PARTIALLY_FILLED
	}
}

// String returns string representation of the order
func (o *Order) String() string {
	return string(o.OrderID)
}

// OrderType methods
func (t OrderType) String() string {
	switch t {
	case LIMIT:
		return "LIMIT"
	case MARKET:
		return "MARKET"
	case STOP_LIMIT:
		return "STOP_LIMIT"
	case STOP_MARKET:
		return "STOP_MARKET"
	case TP_LIMIT:
		return "TP_LIMIT"
	case SL_LIMIT:
		return "SL_LIMIT"
	case SL_MARKET:
		return "SL_MARKET"
	default:
		return "UNKNOWN"
	}
}

func (t OrderType) IsLimit() bool {
	return t == LIMIT || t == STOP_LIMIT || t == TP_LIMIT || t == SL_LIMIT
}

func (t OrderType) IsMarket() bool {
	return t == MARKET || t == STOP_MARKET || t == SL_MARKET
}

func (t OrderType) IsStop() bool {
	return t == STOP_LIMIT || t == STOP_MARKET
}

func (t OrderType) IsTP() bool {
	return t == TP_LIMIT
}

func (t OrderType) IsSL() bool {
	return t == SL_MARKET || t == SL_LIMIT
}

func (t OrderType) IsTPSL() bool {
	return t == TP_LIMIT || t == SL_LIMIT || t == SL_MARKET
}

// OrderSide methods
func (s OrderSide) String() string {
	switch s {
	case BUY:
		return "BUY"
	case SELL:
		return "SELL"
	default:
		return "UNKNOWN"
	}
}

func (s OrderSide) Opposite() OrderSide {
	if s == BUY {
		return SELL
	}
	return BUY
}

// OrderStatus methods
func (s OrderStatus) String() string {
	switch s {
	case NEW:
		return "NEW"
	case PENDING:
		return "PENDING"
	case PARTIALLY_FILLED:
		return "PARTIALLY_FILLED"
	case FILLED:
		return "FILLED"
	case CANCELLED:
		return "CANCELLED"
	case REJECTED:
		return "REJECTED"
	case EXPIRED:
		return "EXPIRED"
	case TRIGGER_WAIT:
		return "TRIGGER_WAIT"
	case TRIGGERED:
		return "TRIGGERED"
	default:
		return "UNKNOWN"
	}
}

func (s OrderStatus) IsTerminal() bool {
	return s == FILLED || s == CANCELLED || s == REJECTED || s == EXPIRED
}

func (s OrderStatus) IsPending() bool {
	return s == PENDING
}

type ModifyArgs struct {
	OrderID     OrderID
	NewOrderID  OrderID
	UserID      UserID
	NewPrice    *uint256.Int
	NewQuantity *uint256.Int
}

func NewModifyArgs(orderID, newOrderID OrderID, userID UserID, newPrice *uint256.Int, newQuantity *uint256.Int) *ModifyArgs {
	return &ModifyArgs{
		OrderID:     orderID,
		NewOrderID:  newOrderID,
		UserID:      userID,
		NewPrice:    newPrice,
		NewQuantity: newQuantity,
	}
}
