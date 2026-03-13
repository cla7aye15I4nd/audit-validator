package matching

import (
	"fmt"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/log"
)

// PriceTimePriority implements the price-time priority matching algorithm
// Following Hyperliquid's approach with separate handling for market/limit orders
type PriceTimePriority struct {
	symbol    types.Symbol
	validator interfaces.MarketValidator
}

// NewPriceTimePriority creates a new price-time priority matcher
func NewPriceTimePriority(symbol types.Symbol, validator interfaces.MarketValidator) *PriceTimePriority {
	return &PriceTimePriority{
		symbol:    symbol,
		validator: validator,
	}
}

// MatchOrder routes to appropriate matching logic based on order type
func (p *PriceTimePriority) MatchOrder(order *types.Order, orderBook interfaces.OrderBook) (*interfaces.MatchResult, error) {
	if order == nil {
		return nil, fmt.Errorf("order cannot be nil")
	}
	if orderBook == nil {
		return nil, fmt.Errorf("opposite queue cannot be nil")
	}

	// Route based on order type (Hyperliquid style)
	switch order.OrderType {
	case types.MARKET, types.STOP_MARKET, types.SL_MARKET:
		return p.matchMarketOrder(order, orderBook)
	case types.LIMIT, types.STOP_LIMIT, types.TP_LIMIT, types.SL_LIMIT:
		return p.matchLimitOrder(order, orderBook)
	default:
		return nil, fmt.Errorf("unsupported order type: %v", order.OrderType)
	}
}

// matchMarketOrder handles market order matching
// Market orders match immediately without price checks
func (p *PriceTimePriority) matchMarketOrder(order *types.Order, orderBook interfaces.OrderBook) (*interfaces.MatchResult, error) {
	// Market orders with quote mode need special handling
	if order.OrderMode == types.QUOTE_MODE {
		return p.matchMarketQuoteMode(order, orderBook)
	}

	// Base mode market order
	return p.matchMarketBaseMode(order, orderBook)
}

// matchMarketBaseMode matches market order in base currency mode
func (p *PriceTimePriority) matchMarketBaseMode(order *types.Order, orderBook interfaces.OrderBook) (*interfaces.MatchResult, error) {
	var err error
	trades := make([]*types.Trade, 0)
	originalQuantity := order.Quantity.Clone()
	filledOrdersWithTPSL := make([]*types.Order, 0)
	rejectedOrders := make([]types.FailedOrder, 0)

	// Lock enforcement for BUY market orders in base mode
	// For SELL orders, quantity is already limited by balance manager
	var totalQuoteSpent *types.Quantity
	if order.Side == types.BUY && order.LockedAmount != nil {
		// BUY in base mode: need to track quote spending against lock
		totalQuoteSpent = types.NewQuantity(0)
	}

	// Match without price checks
	for order.Quantity.Sign() > 0 {
		// Get best opposite order (original, not copy)
		var passive *types.Order
		if order.Side == types.BUY {
			passive = orderBook.GetBestAsk()
		} else {
			passive = orderBook.GetBestBid()
		}

		if passive == nil {
			// No more liquidity
			break
		}

		// Execute at passive order's price (no price check needed)
		execQuantity := p.minQuantity(order.Quantity, passive.Quantity)
		execPrice := passive.Price.Clone()

		// Apply lot size validation for base mode market orders
		if p.validator != nil {
			// Check if the execution quantity meets lot size requirements
			rounded, wasRounded := p.validator.RoundDownToLotSize(execPrice, execQuantity)
			if wasRounded {
				execQuantity = rounded
			}
			// Check if it's dust
			if p.validator.IsQuantityDust(execQuantity, execPrice) {
				// TODO-Orderbook: maker limit order must not remain dust
				// If passive order itself is dust, remove it
				if p.validator.IsQuantityDust(passive.Quantity, execPrice) {
					passive.Status = types.REJECTED
					orderBook.RemoveOrder(passive.OrderID)
					rejectedOrders = append(rejectedOrders,
						types.FailedOrder{OrderID: passive.OrderID, Reason: "maker order with dust"})
					log.Error("Removed dust passive order for market base",
						"orderID", passive.OrderID,
						"quantity", passive.Quantity,
						"price", passive.Price)
					continue
				}
				// Skip this level if quantity is dust
				break
			}
		}

		// Check lock limits for BUY orders (quote spending)
		if order.Side == types.BUY && totalQuoteSpent != nil {
			quoteCost := p.multiplyWithPrecision(execQuantity, execPrice)
			if new(types.Quantity).Add(totalQuoteSpent, quoteCost).Cmp(order.LockedAmount) > 0 {
				// Calculate how much we can afford with remaining lock
				remainingQuote := new(types.Quantity).Sub(order.LockedAmount, totalQuoteSpent)
				execQuantity = p.divideWithPrecision(remainingQuote, execPrice)

				// Round down to lot size for partial fills
				if p.validator != nil {
					rounded, wasRounded := p.validator.RoundDownToLotSize(execPrice, execQuantity)
					if wasRounded {
						execQuantity = rounded
					}
				}

				if execQuantity.IsZero() {
					// Can't afford even minimum quantity at this price
					break
				}
				// Take the smaller of what we can afford vs what's available
				execQuantity = p.minQuantity(execQuantity, passive.Quantity)
				// Recalculate actual quote cost
				quoteCost = p.multiplyWithPrecision(execQuantity, execPrice)
			}
			totalQuoteSpent = new(types.Quantity).Add(totalQuoteSpent, quoteCost)
		}

		// Create trade
		trade := p.createTrade(order, passive, execPrice, execQuantity)
		trades = append(trades, trade)

		log.Debug("Trade executed",
			"tradeID", trade.TradeID,
			"takerOrder", order.OrderID,
			"makerOrder", passive.OrderID,
			"price", execPrice,
			"quantity", execQuantity)

		// Update quantities directly on original objects
		order.Quantity = new(types.Quantity).Sub(order.Quantity, execQuantity)
		passive.Quantity = new(types.Quantity).Sub(passive.Quantity, execQuantity)

		// Remove or update passive order
		if passive.Quantity.IsZero() {
			passive.Status = types.FILLED
			// Save filled order with TPSL before removing
			if passive.HasTPSL() {
				filledOrdersWithTPSL = append(filledOrdersWithTPSL, passive.Copy())
			}
			if err = orderBook.RemoveOrder(passive.OrderID); err != nil {
				break
			}
		} else {
			passive.Status = types.PARTIALLY_FILLED
			if err = orderBook.UpdateOrder(passive); err != nil {
				break
			}
		}
	}

	// Calculate filled quantity
	filledQuantity := new(types.Quantity).Sub(originalQuantity, order.Quantity)

	// Market order is always filled
	order.Status = types.FILLED

	// Market orders never rest in the book
	// Any remaining quantity is cancelled
	return &interfaces.MatchResult{
		Trades:               trades,
		RemainingOrder:       nil, // Market orders never have remaining
		FilledQuantity:       filledQuantity,
		FilledOrdersWithTPSL: filledOrdersWithTPSL,
		FailedOrders:         rejectedOrders,
	}, err
}

// matchMarketQuoteMode matches market order in quote currency mode
func (p *PriceTimePriority) matchMarketQuoteMode(order *types.Order, orderBook interfaces.OrderBook) (*interfaces.MatchResult, error) {
	var err error
	trades := make([]*types.Trade, 0)
	remainingQuote := order.Quantity.Clone() // In quote mode, quantity is quote amount
	totalFilledBase := types.NewQuantity(0)
	filledOrdersWithTPSL := make([]*types.Order, 0)
	rejectedOrders := make([]types.FailedOrder, 0)

	// Lock enforcement for SELL orders in quote mode
	var totalBaseSold *types.Quantity
	if order.Side == types.SELL && order.LockedAmount != nil {
		// SELL in quote mode: track base sold against lock
		totalBaseSold = types.NewQuantity(0)
	}
	// For BUY orders in quote mode, remainingQuote already enforces the limit

	for remainingQuote.Sign() > 0 {
		// Get best opposite order (original, not copy)
		var passive *types.Order
		if order.Side == types.BUY {
			passive = orderBook.GetBestAsk()
		} else {
			passive = orderBook.GetBestBid()
		}

		if passive == nil {
			// No more liquidity
			break
		}

		// Calculate how much base we can trade with remaining quote
		maxBaseFromQuote := p.divideWithPrecision(remainingQuote, passive.Price)
		if maxBaseFromQuote.IsZero() {
			// Can't afford even 1 unit at this price
			break
		}

		// Execute the smaller of what we can afford vs what's available
		execQuantity := p.minQuantity(maxBaseFromQuote, passive.Quantity)

		// Round down to lot size for the passive order's price
		if p.validator != nil {
			rounded, wasRounded := p.validator.RoundDownToLotSize(passive.Price, execQuantity)
			if wasRounded {
				execQuantity = rounded
			}
			// Check if it's dust
			if p.validator.IsQuantityDust(execQuantity, passive.Price) {
				// TODO-Orderbook: maker limit order must not remain dust
				// If passive order itself is dust, remove it
				if p.validator.IsQuantityDust(passive.Quantity, passive.Price) {
					passive.Status = types.REJECTED
					orderBook.RemoveOrder(passive.OrderID)
					rejectedOrders = append(rejectedOrders,
						types.FailedOrder{OrderID: passive.OrderID, Reason: "maker order with dust"})
					log.Error("Removed dust passive order for market quote",
						"orderID", passive.OrderID,
						"quantity", passive.Quantity,
						"price", passive.Price)
					continue
				}
				// Can't trade dust amounts
				break
			}
		}

		// Check lock limits for SELL orders (base selling)
		if totalBaseSold != nil {
			if new(types.Quantity).Add(totalBaseSold, execQuantity).Cmp(order.LockedAmount) > 0 {
				// Limit to remaining base lock
				remainingBase := new(types.Quantity).Sub(order.LockedAmount, totalBaseSold)
				if remainingBase.IsZero() {
					// No more base to sell
					break
				}
				execQuantity = p.minQuantity(remainingBase, execQuantity)
			}
		}

		execPrice := passive.Price.Clone()
		quoteCost := p.multiplyWithPrecision(execQuantity, execPrice)

		// Create trade
		trade := p.createTrade(order, passive, execPrice, execQuantity)
		trades = append(trades, trade)

		// Update quantities
		remainingQuote = new(types.Quantity).Sub(remainingQuote, quoteCost)
		passive.Quantity = new(types.Quantity).Sub(passive.Quantity, execQuantity)
		totalFilledBase = new(types.Quantity).Add(totalFilledBase, execQuantity)

		// Update base tracking for SELL orders
		if totalBaseSold != nil {
			totalBaseSold = new(types.Quantity).Add(totalBaseSold, execQuantity)
		}

		// Remove or update passive order
		if passive.Quantity.IsZero() {
			passive.Status = types.FILLED
			// Save filled order with TPSL before removing
			if passive.HasTPSL() {
				filledOrdersWithTPSL = append(filledOrdersWithTPSL, passive.Copy())
			}
			if err = orderBook.RemoveOrder(passive.OrderID); err != nil {
				break
			}
		} else {
			passive.Status = types.PARTIALLY_FILLED
			if err = orderBook.UpdateOrder(passive); err != nil {
				break
			}
		}
	}

	// Market order is always filled
	order.Status = types.FILLED

	// Market orders never rest in the book
	return &interfaces.MatchResult{
		Trades:               trades,
		RemainingOrder:       nil,
		FilledQuantity:       totalFilledBase, // Return base amount filled
		FilledOrdersWithTPSL: filledOrdersWithTPSL,
		FailedOrders:         rejectedOrders,
	}, err
}

// matchLimitOrder handles limit order matching
func (p *PriceTimePriority) matchLimitOrder(order *types.Order, orderBook interfaces.OrderBook) (*interfaces.MatchResult, error) {
	var err error
	var cannotMatch bool
	trades := make([]*types.Trade, 0)
	originalQuantity := order.Quantity.Clone()
	filledOrdersWithTPSL := make([]*types.Order, 0)
	rejectedOrders := make([]types.FailedOrder, 0)

	// Continue matching while order has remaining quantity
	for order.Quantity.Sign() > 0 {
		// Get best opposite order (original, not copy)
		var passive *types.Order
		if order.Side == types.BUY {
			passive = orderBook.GetBestAsk()
		} else {
			passive = orderBook.GetBestBid()
		}

		if passive == nil {
			// No more orders to match against
			break
		}

		// Check if prices cross
		if !p.canMatchLimit(order, passive) {
			// Price levels don't cross
			break
		}

		// Execute trade at passive order's price
		execQuantity := p.minQuantity(order.Quantity, passive.Quantity)
		execPrice := passive.Price.Clone()

		if p.validator != nil {
			// Round down to maker's lot size to prevent dust
			rounded, wasRounded := p.validator.RoundDownToLotSize(passive.Price, execQuantity)
			if wasRounded {
				execQuantity = rounded
			}

			if p.validator.IsQuantityDust(execQuantity, passive.Price) {
				// TODO-Orderbook: maker limit order must not remain dust
				// If passive order itself is dust, remove it
				if p.validator.IsQuantityDust(passive.Quantity, passive.Price) {
					passive.Status = types.REJECTED
					orderBook.RemoveOrder(passive.OrderID)
					rejectedOrders = append(rejectedOrders,
						types.FailedOrder{OrderID: passive.OrderID, Reason: "maker order with dust"})
					log.Error("Removed dust passive order",
						"orderID", passive.OrderID,
						"quantity", passive.Quantity,
						"price", passive.Price)
					continue // Continue to next order instead of breaking
				}
				// Can't trade dust amounts
				log.Warn("Dust trade for limit orders",
					"takerOrder", order.OrderID,
					"makerOrder", passive.OrderID,
					"price", execPrice,
					"quantity", execQuantity)
				cannotMatch = true
				break
			}
		}

		// Create trade
		trade := p.createTrade(order, passive, execPrice, execQuantity)
		trades = append(trades, trade)

		log.Debug("Trade executed",
			"tradeID", trade.TradeID,
			"takerOrder", order.OrderID,
			"makerOrder", passive.OrderID,
			"price", execPrice,
			"quantity", execQuantity)

		// Update quantities directly on original objects
		order.Quantity = new(types.Quantity).Sub(order.Quantity, execQuantity)
		passive.Quantity = new(types.Quantity).Sub(passive.Quantity, execQuantity)

		// Update or remove passive order
		if passive.Quantity.IsZero() {
			passive.Status = types.FILLED
			// Save filled order with TPSL before removing
			if passive.HasTPSL() {
				filledOrdersWithTPSL = append(filledOrdersWithTPSL, passive.Copy())
			}
			if err = orderBook.RemoveOrder(passive.OrderID); err != nil {
				break
			}
		} else {
			passive.Status = types.PARTIALLY_FILLED
			if err = orderBook.UpdateOrder(passive); err != nil {
				break
			}
		}
		// Update taker order status
		if order.Quantity.IsZero() {
			order.Status = types.FILLED
		} else {
			order.Status = types.PARTIALLY_FILLED
		}
	}

	// Calculate filled quantity
	filledQuantity := new(types.Quantity).Sub(originalQuantity, order.Quantity)
	if p.validator != nil {
		order.Quantity, _ = p.validator.RoundDownToLotSize(order.Price, order.Quantity)
	}

	// Check if the aggressive order has TPSL and was fully filled (including dust case)
	if order.Quantity.IsZero() || cannotMatch {
		if filledQuantity.IsZero() {
			order.Status = types.REJECTED
			rejectedOrders = append(rejectedOrders,
				types.FailedOrder{OrderID: order.OrderID, Reason: "dust taker order with current orderbook"})
		} else {
			order.Status = types.FILLED
			// Check if it has TPSL and was fully filled
			if order.HasTPSL() {
				filledOrdersWithTPSL = append(filledOrdersWithTPSL, order.Copy())
			}
		}
	}

	// Determine if there's a remaining order
	var remainingOrder *types.Order
	// Don't add to orderbook if dust or zero
	if err == nil && order.Quantity.Sign() > 0 && !cannotMatch {
		remainingOrder = order
		remainingOrder.Status = types.PENDING
		// Add to orderbook
		err = orderBook.AddOrder(remainingOrder)
	}

	return &interfaces.MatchResult{
		Trades:               trades,
		RemainingOrder:       remainingOrder,
		FilledQuantity:       filledQuantity,
		FilledOrdersWithTPSL: filledOrdersWithTPSL,
		FailedOrders:         rejectedOrders,
	}, err
}

// canMatchLimit checks if two limit orders can match
func (p *PriceTimePriority) canMatchLimit(taker, maker *types.Order) bool {
	if taker.Side == types.BUY {
		// Buy order: taker price >= maker price
		return taker.Price.Cmp(maker.Price) >= 0
	} else {
		// Sell order: taker price <= maker price
		return taker.Price.Cmp(maker.Price) <= 0
	}
}

// createTrade creates a trade record
func (p *PriceTimePriority) createTrade(taker, maker *types.Order, price, quantity *types.Quantity) *types.Trade {
	// Determine order IDs based on side
	var buyOrderID, sellOrderID types.OrderID
	if taker.Side == types.BUY {
		buyOrderID = taker.OrderID
		sellOrderID = maker.OrderID
	} else {
		buyOrderID = maker.OrderID
		sellOrderID = taker.OrderID
	}

	// Determine if orders are fully filled
	var buyOrder, sellOrder *types.Order
	if taker.Side == types.BUY {
		buyOrder = taker
		sellOrder = maker
	} else {
		buyOrder = maker
		sellOrder = taker
	}

	buyOrderFilled := new(types.Quantity).Sub(buyOrder.Quantity, quantity).IsZero()
	sellOrderFilled := new(types.Quantity).Sub(sellOrder.Quantity, quantity).IsZero()

	// Check if orders have TPSL and are fully filled
	buyOrderHasTPSL := buyOrderFilled && buyOrder.HasTPSL()
	sellOrderHasTPSL := sellOrderFilled && sellOrder.HasTPSL()

	return &types.Trade{
		TradeID:              types.GenerateTradeID(),
		Symbol:               p.symbol,
		Price:                price,
		Quantity:             quantity,
		BuyOrderID:           buyOrderID,
		SellOrderID:          sellOrderID,
		MakerOrderID:         maker.OrderID,
		TakerOrderID:         taker.OrderID,
		IsBuyerMaker:         maker.Side == types.BUY,
		BuyOrderFullyFilled:  buyOrderFilled,
		SellOrderFullyFilled: sellOrderFilled,
		BuyOrderHasTPSL:      buyOrderHasTPSL,
		SellOrderHasTPSL:     sellOrderHasTPSL,
		Timestamp:            uint64(types.TimeNow()),
	}
}

// Helper functions

// minQuantity returns the minimum of two quantities
func (p *PriceTimePriority) minQuantity(a, b *types.Quantity) *types.Quantity {
	if a.Cmp(b) < 0 {
		return a.Clone()
	}
	return b.Clone()
}

// multiplyWithPrecision multiplies quantity by price with decimal precision
func (p *PriceTimePriority) multiplyWithPrecision(quantity, price *types.Price) *types.Quantity {
	// Use Uint256MulScaledDecimal for proper decimal scaling: (quantity * price) / 10^18
	// Decimal version is safer as it avoids overflow
	result := common.Uint256MulScaledDecimal(quantity, price)
	return result
}

// divideWithPrecision divides quote amount by price to get base quantity
func (p *PriceTimePriority) divideWithPrecision(quote *types.Quantity, price *types.Price) *types.Quantity {
	if price.IsZero() {
		return types.NewQuantity(0)
	}
	// Use Uint256DivScaledDecimal for proper decimal scaling: (quote * 10^18) / price
	// Decimal version provides better precision
	result := common.Uint256DivScaledDecimal(quote, price)
	return result
}

// GetAlgorithm returns the name of the matching algorithm
func (p *PriceTimePriority) GetAlgorithm() string {
	return "PriceTimePriority"
}

// Validate validates the matcher configuration
func (p *PriceTimePriority) Validate() error {
	if p.symbol == "" {
		return fmt.Errorf("symbol cannot be empty")
	}
	return nil
}
