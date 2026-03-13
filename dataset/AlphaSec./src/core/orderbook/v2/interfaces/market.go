package interfaces

import (
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
)

// MarketValidator defines the interface for market rules validation and adjustments
type MarketValidator interface {
	// Order validation methods
	ValidateOrder(order *types.Order) error
	ValidateOrderPrice(price *types.Price) error
	ValidateOrderQuantity(price, quantity *types.Quantity) error
	ValidateMinimumOrderValue(price, quantity *types.Quantity) error
	ValidateMarketOrder(quantity, bestPrice *types.Quantity, side types.OrderSide, mode types.OrderMode) error
	
	// Market rules query methods
	GetTickSize(price *types.Price) *types.Quantity
	GetLotSize(price *types.Price) *types.Quantity
	GetMinimumLotSize() *types.Quantity
	
	// Quantity adjustment methods
	RoundDownToLotSize(price, quantity *types.Quantity) (*types.Quantity, bool)
	RoundPriceToTickSize(price *types.Price, roundUp bool) *types.Price
	RoundQuantityToLotSize(price, quantity *types.Quantity, roundUp bool) *types.Quantity
	
	// Validation helpers
	IsQuantityDust(quantity, price *types.Quantity) bool
}