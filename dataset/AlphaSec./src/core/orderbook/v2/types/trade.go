package types

import (
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/holiman/uint256"
)

// TradeID is a unique identifier for a trade
type TradeID string

// Trade represents an executed trade between two orders
type Trade struct {
	// Identity
	TradeID TradeID `rlp:"-"`
	Symbol  Symbol

	// Order information
	BuyOrderID  OrderID
	SellOrderID OrderID

	// Fill status
	BuyOrderFullyFilled  bool // Buy order completely filled (or only dust remained)
	SellOrderFullyFilled bool // Sell order completely filled (or only dust remained)

	// Maker/Taker designation
	MakerOrderID OrderID
	TakerOrderID OrderID
	IsBuyerMaker bool `rlp:"-"` // true if buyer is maker, false if seller is maker

	// Execution details
	Price    *uint256.Int
	Quantity *uint256.Int // Base currency amount

	// Timestamp
	Timestamp uint64

	// Fee information
	BuyFeeTokenID  string // Token used for buyer fee
	BuyFeeAmount   *uint256.Int
	SellFeeTokenID string // Token used for seller fee
	SellFeeAmount  *uint256.Int

	// TPSL information for lock inheritance
	BuyOrderHasTPSL  bool `rlp:"-"` // Buy order has TPSL and needs lock inheritance
	SellOrderHasTPSL bool `rlp:"-"` // Sell order has TPSL and needs lock inheritance
}

// NewTrade creates a new trade
func NewTrade(tradeID TradeID, symbol Symbol, buyOrderID, sellOrderID OrderID, price, quantity *uint256.Int, isBuyerMaker bool) *Trade {
	makerID := sellOrderID
	takerID := buyOrderID
	if isBuyerMaker {
		makerID = buyOrderID
		takerID = sellOrderID
	}

	return &Trade{
		TradeID:      tradeID,
		Symbol:       symbol,
		Timestamp:    uint64(TimeNow()),
		BuyOrderID:   buyOrderID,
		SellOrderID:  sellOrderID,
		Price:        price,
		Quantity:     quantity,
		MakerOrderID: makerID,
		TakerOrderID: takerID,
		IsBuyerMaker: isBuyerMaker,
	}
}

// GetMakerSide returns the side of the maker order
func (t *Trade) GetMakerSide() OrderSide {
	if t.IsBuyerMaker {
		return BUY
	}
	return SELL
}

// GetTakerSide returns the side of the taker order
func (t *Trade) GetTakerSide() OrderSide {
	if t.IsBuyerMaker {
		return SELL
	}
	return BUY
}

// Copy creates a deep copy of the trade
func (t *Trade) Copy() *Trade {
	if t == nil {
		return nil
	}

	copy := *t

	// Deep copy uint256 fields
	if t.Price != nil {
		copy.Price = t.Price.Clone()
	}
	if t.Quantity != nil {
		copy.Quantity = t.Quantity.Clone()
	}
	if t.BuyFeeAmount != nil {
		copy.BuyFeeAmount = t.BuyFeeAmount.Clone()
	}
	if t.SellFeeAmount != nil {
		copy.SellFeeAmount = t.SellFeeAmount.Clone()
	}

	return &copy
}

// Serialize encodes the Trade using RLP
func (t *Trade) Serialize() ([]byte, error) {
	return rlp.EncodeToBytes(t)
}

// TradeResult represents the result of order matching
type TradeResult struct {
	Trades        []*Trade
	UpdatedOrders []*Order
	RemovedOrders []OrderID
}
