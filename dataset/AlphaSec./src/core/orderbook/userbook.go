package orderbook

import (
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/holiman/uint256"
	"io"
	"sync"
)

// -- UserBook for positions, orders, trades --

type Position struct {
	Quantity *uint256.Int
	AvgPrice *uint256.Int
	PnL      *uint256.Int
}

type UserBook struct {
	mu        sync.RWMutex
	Positions map[string]*Position
	Orders    map[string]*Order
	Trades    []*Trade
}

func NewUserBook() *UserBook {
	return &UserBook{
		Positions: make(map[string]*Position),
		Orders:    make(map[string]*Order),
		Trades:    []*Trade{},
	}
}

func (ub *UserBook) UpdatePosition(userID string, side Side, price, quantity *uint256.Int) {
	ub.mu.Lock()
	defer ub.mu.Unlock()
	pos, ok := ub.Positions[userID]
	if !ok {
		pos = &Position{
			Quantity: new(uint256.Int),
			AvgPrice: new(uint256.Int),
			PnL:      new(uint256.Int),
		}
		ub.Positions[userID] = pos
	}

	if side == BUY {
		// totalCost = pos.AvgPrice * pos.Quantity + price * quantity
		totalCost := common.Uint256MulScaledDecimal(pos.AvgPrice, pos.Quantity)
		additionalCost := common.Uint256MulScaledDecimal(price, quantity)
		totalCost.Add(totalCost, additionalCost)

		pos.Quantity = new(uint256.Int).Add(pos.Quantity, quantity)

		// pos.AvgPrice = totalCost / pos.Quantity (avoid divide by zero)
		if !pos.Quantity.IsZero() {
			pos.AvgPrice = common.Uint256DivScaledDecimal(totalCost, pos.Quantity)
		}
	} else {
		// if quantity > pos.Quantity: quantity = pos.Quantity
		if quantity.Cmp(pos.Quantity) > 0 {
			quantity = new(uint256.Int).Set(pos.Quantity)
		}

		// pnl = (price - pos.AvgPrice) * quantity
		priceDiff := new(uint256.Int).Sub(price, pos.AvgPrice)
		pnl := new(uint256.Int).Mul(priceDiff, quantity)

		pos.Quantity = new(uint256.Int).Sub(pos.Quantity, quantity)
		pos.PnL = new(uint256.Int).Add(pos.PnL, pnl)
	}
}

func (ub *UserBook) AddOrder(order *Order) {
	ub.mu.Lock()
	defer ub.mu.Unlock()
	ub.Orders[order.OrderID] = order
}

func (ub *UserBook) AddTrade(t *Trade) {
	ub.mu.Lock()
	defer ub.mu.Unlock()
	ub.Trades = append(ub.Trades, t)
}

func (ub *UserBook) GetOrder(orderID string) (*Order, bool) {
	ub.mu.RLock()
	defer ub.mu.RUnlock()
	order, ok := ub.Orders[orderID]
	return order, ok
}

func (ub *UserBook) RemoveOrder(orderID string) {
	ub.mu.Lock()
	defer ub.mu.Unlock()
	delete(ub.Orders, orderID)
}

// GetUserOrders returns all orders for a specific user
func (ub *UserBook) GetUserOrders(userID string) []*Order {
	ub.mu.RLock()
	defer ub.mu.RUnlock()
	
	var userOrders []*Order
	for _, order := range ub.Orders {
		if order != nil && order.UserID == userID {
			userOrders = append(userOrders, order)
		}
	}
	return userOrders
}

func (ub *UserBook) EncodeRLP(w io.Writer) error {
	type kvPosition struct {
		Key string
		Val *Position
	}
	type kvOrder struct {
		Key string
		Val *Order
	}
	type encodable struct {
		Positions []*kvPosition
		Orders    []*kvOrder
		Trades    []*Trade
	}

	var positions []*kvPosition
	for k, v := range ub.Positions {
		positions = append(positions, &kvPosition{Key: k, Val: v})
	}

	var orders []*kvOrder
	for k, v := range ub.Orders {
		orders = append(orders, &kvOrder{Key: k, Val: v})
	}

	data := &encodable{
		Positions: positions,
		Orders:    orders,
		Trades:    ub.Trades,
	}

	return rlp.Encode(w, data)
}

func (ub *UserBook) DecodeRLP(s *rlp.Stream) error {
	type kvPosition struct {
		Key string
		Val *Position
	}
	type kvOrder struct {
		Key string
		Val *Order
	}
	type encodable struct {
		Positions []*kvPosition
		Orders    []*kvOrder
		Trades    []*Trade
	}

	var data encodable
	if err := s.Decode(&data); err != nil {
		return err
	}

	ub.Positions = make(map[string]*Position)
	for _, kv := range data.Positions {
		ub.Positions[kv.Key] = kv.Val
	}

	ub.Orders = make(map[string]*Order)
	for _, kv := range data.Orders {
		ub.Orders[kv.Key] = kv.Val
	}

	ub.Trades = data.Trades
	return nil
}
