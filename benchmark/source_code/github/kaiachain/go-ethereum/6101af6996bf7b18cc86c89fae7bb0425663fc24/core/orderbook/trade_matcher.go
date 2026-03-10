package orderbook

import (
	"container/heap"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// TradeMatcher handles order matching and trade execution logic
type TradeMatcher struct {
	symbol string
}

// NewTradeMatcher creates a new TradeMatcher instance
func NewTradeMatcher(symbol string) *TradeMatcher {
	return &TradeMatcher{
		symbol: symbol,
	}
}

// matchBuyOrder matches a buy order against the sell queue
// Returns the generated trades and the total executed cost
func (m *TradeMatcher) matchBuyOrder(order *Order, e *SymbolEngine, locker *DefaultLocker) ([]*Trade, *uint256.Int) {
	var trades []*Trade
	_, quoteToken, _ := SymbolToTokens(order.Symbol)
	locked := locker.GetLockedTokenBalance(common.HexToAddress(order.UserID), quoteToken)
	executedCost := new(uint256.Int).SetUint64(0)

	// Handle market orders in quote mode specially
	isQuoteMarket := order.OrderType == MARKET && order.OrderMode == QUOTE_MODE
	var remainingQuote *uint256.Int
	if isQuoteMarket {
		// For market buy in quote mode, order.Quantity is the quote amount to spend
		remainingQuote = new(uint256.Int).Set(order.Quantity)
	}

	for (isQuoteMarket && remainingQuote.Sign() > 0) || (!isQuoteMarket && order.Quantity.Sign() > 0) {
		if len(e.sellQueue) == 0 {
			break
		}
		top := e.sellQueue[0]
		if top.IsCanceled || top.Quantity.Sign() == 0 {
			heap.Pop(&e.sellQueue)
			e.sellDirty[top.Price.String()] = struct{}{}
			continue
		}
		if top.Price.Cmp(order.Price) > 0 {
			break
		}
		
		// Get lot size for current price level
		lotSize := e.marketRules.GetLotSize(top.Price)
		
		var qty *uint256.Int  // Base quantity to trade
		var cost *uint256.Int // Quote amount for this trade
		
		if isQuoteMarket {
			// Market buy in quote mode: calculate how much base we can buy with remaining quote
			maxBaseFromQuote := common.Uint256DivScaledDecimal(remainingQuote, top.Price)
			// Round down to lot size for market orders
			if order.OrderType == MARKET {
				maxBaseFromQuote, _ = RoundDownToLotSize(maxBaseFromQuote, lotSize)
			}
			// If can't buy even one lot, stop matching
			if maxBaseFromQuote.IsZero() {
				break
			}
			qty = minUint256(maxBaseFromQuote, top.Quantity)
			cost = common.Uint256MulScaledDecimal(top.Price, qty)
		} else {
			// Normal base mode (limit or market in base mode)
			qty = minUint256(order.Quantity, top.Quantity)
			// Round down to lot size for market orders
			if order.OrderType == MARKET {
				qty, _ = RoundDownToLotSize(qty, lotSize)
				// If remaining quantity is less than lot size, stop matching
				if qty.IsZero() {
					break
				}
			}
			cost = common.Uint256MulScaledDecimal(top.Price, qty)
		}
		
		// Check if buyer has enough locked quote tokens
		remaining := new(uint256.Int).Sub(locked, executedCost)

		if remaining.Cmp(cost) < 0 {
			adjustedQty := common.Uint256DivScaledDecimal(remaining, top.Price)
			// Round down to lot size for market orders
			if order.OrderType == MARKET {
				adjustedQty, _ = RoundDownToLotSize(adjustedQty, lotSize)
			}
			cost = common.Uint256MulScaledDecimal(top.Price, adjustedQty)
			// Defensive check to prevent infinite loop
			if adjustedQty.IsZero() || cost.IsZero() {
				break
			}
			qty = adjustedQty
		}
		executedCost = new(uint256.Int).Add(executedCost, cost)

		// Update quantities
		var orderQty *uint256.Int
		if isQuoteMarket {
			// Deduct cost from remaining quote amount
			remainingQuote = new(uint256.Int).Sub(remainingQuote, cost)
			orderQty = remainingQuote
		} else {
			// Deduct qty from order quantity (base mode)
			orderQty = new(uint256.Int).Sub(order.Quantity, qty)
		}
		topQty := new(uint256.Int).Sub(top.Quantity, qty)
		t := &Trade{
			Symbol:          order.Symbol,
			BuyOrderID:      order.OrderID,
			SellOrderID:     top.OrderID,
			BuyOrderFilled:  orderQty.IsZero(),
			SellOrderFilled: topQty.IsZero(),
			MakerID:         top.OrderID,
			TakerID:         order.OrderID,
			Price:           top.Price,
			Quantity:        qty,
			Timestamp:       uint64(time.Now().UnixNano()),
			IsBuyerMaker:    false,
		}
		trades = append(trades, t)
		// TODO-Orderbook: comment out unnessary userbook data
		//e.userBook.AddTrade(t)
		//e.userBook.UpdatePosition(order.UserID, BUY, top.Price, qty)
		//e.userBook.UpdatePosition(top.UserID, SELL, top.Price, qty)
		order.Quantity = orderQty
		top.Quantity = topQty

		if top.Quantity.IsZero() {
			heap.Pop(&e.sellQueue)
			e.sellDirty[top.Price.String()] = struct{}{}
		}
	}

	return trades, executedCost
}

// matchSellOrder matches a sell order against the buy queue
// Returns the generated trades and the total executed quantity
func (m *TradeMatcher) matchSellOrder(order *Order, e *SymbolEngine, locker *DefaultLocker) ([]*Trade, *uint256.Int) {
	var trades []*Trade
	baseToken, _, _ := SymbolToTokens(order.Symbol)
	locked := locker.GetLockedTokenBalance(common.HexToAddress(order.UserID), baseToken)
	executedQty := uint256.NewInt(0)

	// Handle market orders in quote mode specially
	isQuoteMarket := order.OrderType == MARKET && order.OrderMode == QUOTE_MODE
	var remainingQuote *uint256.Int
	if isQuoteMarket {
		// For market sell in quote mode, order.Quantity is the quote amount to receive
		remainingQuote = new(uint256.Int).Set(order.Quantity)
	}

	for (isQuoteMarket && remainingQuote.Sign() > 0) || (!isQuoteMarket && order.Quantity.Sign() > 0) {
		if len(e.buyQueue) == 0 {
			break
		}
		top := e.buyQueue[0]
		if top.IsCanceled || top.Quantity.Sign() == 0 {
			heap.Pop(&e.buyQueue)
			e.buyDirty[top.Price.String()] = struct{}{}
			continue
		}
		if top.Price.Cmp(order.Price) < 0 {
			break
		}
		
		// Get lot size for current price level
		lotSize := e.marketRules.GetLotSize(top.Price)
		
		var qty *uint256.Int  // Base quantity to trade
		var cost *uint256.Int // Quote amount for this trade
		
		if isQuoteMarket {
			// Market sell in quote mode: calculate how much base to sell to get remaining quote
			baseNeeded := common.Uint256DivScaledDecimal(remainingQuote, top.Price)
			// Round down to lot size for market orders
			if order.OrderType == MARKET {
				baseNeeded, _ = RoundDownToLotSize(baseNeeded, lotSize)
			}
			// If can't sell even one lot, stop matching
			if baseNeeded.IsZero() {
				break
			}
			qty = minUint256(baseNeeded, top.Quantity)
			cost = common.Uint256MulScaledDecimal(top.Price, qty)
		} else {
			// Normal base mode (limit or market in base mode)
			qty = minUint256(order.Quantity, top.Quantity)
			// Round down to lot size for market orders
			if order.OrderType == MARKET {
				qty, _ = RoundDownToLotSize(qty, lotSize)
				// If remaining quantity is less than lot size, stop matching
				if qty.IsZero() {
					break
				}
			}
			cost = common.Uint256MulScaledDecimal(top.Price, qty)
		}
		
		// Check if seller has enough locked base tokens
		remaining := new(uint256.Int).Sub(locked, executedQty)

		if remaining.Cmp(qty) < 0 {
			// Round down to lot size for market orders
			if order.OrderType == MARKET {
				remaining, _ = RoundDownToLotSize(remaining, lotSize)
			}
			// Defensive check to prevent infinite loop
			if remaining.IsZero() {
				break
			}
			qty = remaining
			cost = common.Uint256MulScaledDecimal(top.Price, qty)
		}
		executedQty = new(uint256.Int).Add(executedQty, qty)
		
		// Update quantities
		var orderQty *uint256.Int
		if isQuoteMarket {
			// Deduct cost from remaining quote amount
			remainingQuote = new(uint256.Int).Sub(remainingQuote, cost)
			orderQty = remainingQuote
		} else {
			// Deduct qty from order quantity (base mode)
			orderQty = new(uint256.Int).Sub(order.Quantity, qty)
		}
		topQty := new(uint256.Int).Sub(top.Quantity, qty)

		t := &Trade{
			Symbol:          order.Symbol,
			BuyOrderID:      top.OrderID,
			SellOrderID:     order.OrderID,
			BuyOrderFilled:  topQty.IsZero(),
			SellOrderFilled: orderQty.IsZero(),
			MakerID:         top.OrderID,
			TakerID:         order.OrderID,
			Price:           top.Price,
			Quantity:        qty,
			Timestamp:       uint64(time.Now().UnixNano()),
			IsBuyerMaker:    true,
		}
		trades = append(trades, t)
		// TODO-Orderbook: comment out unnessary userbook data
		//e.userBook.AddTrade(t)
		//e.userBook.UpdatePosition(top.UserID, BUY, top.Price, qty)
		//e.userBook.UpdatePosition(order.UserID, SELL, top.Price, qty)
		order.Quantity = orderQty
		top.Quantity = topQty

		if top.Quantity.IsZero() {
			heap.Pop(&e.buyQueue)
			e.buyDirty[top.Price.String()] = struct{}{}
		}
	}

	return trades, executedQty
}

// processCompletedTradesWithEvents processes trades and generates events for state changes
// Event order reflects actual execution: maker updates → price updates → taker addition
func (m *TradeMatcher) processCompletedTradesWithEvents(trades []*Trade, e *SymbolEngine, locker *DefaultLocker) []OrderbookEvent {
	var events []OrderbookEvent

	for _, trade := range trades {
		// Generate price update event if price changed
		if e.currentPrice == nil || !e.currentPrice.Eq(trade.Price) {
			events = append(events, &PriceUpdatedEvent{
				BaseEvent: e.createEvent(),
				Symbol:    e.symbol,
				Price:     trade.Price.Clone(),
			})
		}

		// Process the trade (updates balances, TPSL, etc.)
		m.processSingleTrade(trade, e, locker)

		// Generate events for maker order updates
		// These happen BEFORE the taker order is added to queue
		buyOrder, _ := e.userBook.GetOrder(trade.BuyOrderID)
		sellOrder, _ := e.userBook.GetOrder(trade.SellOrderID)

		// Buy order (could be maker or taker depending on trade.IsBuyerMaker)
		if buyOrder != nil {
			if buyOrder.Quantity.Sign() == 0 {
				events = append(events, &OrderRemovedEvent{
					BaseEvent: e.createEvent(),
					OrderID:   trade.BuyOrderID,
					Symbol:    e.symbol,
					Side:      BUY,
				})
			} else {
				events = append(events, &OrderQuantityUpdatedEvent{
					BaseEvent:   e.createEvent(),
					OrderID:     trade.BuyOrderID,
					Symbol:      e.symbol,
					NewQuantity: buyOrder.Quantity.Clone(),
				})
			}
		}

		// Sell order (could be maker or taker depending on trade.IsBuyerMaker)
		if sellOrder != nil {
			if sellOrder.Quantity.Sign() == 0 {
				events = append(events, &OrderRemovedEvent{
					BaseEvent: e.createEvent(),
					OrderID:   trade.SellOrderID,
					Symbol:    e.symbol,
					Side:      SELL,
				})
			} else {
				events = append(events, &OrderQuantityUpdatedEvent{
					BaseEvent:   e.createEvent(),
					OrderID:     trade.SellOrderID,
					Symbol:      e.symbol,
					NewQuantity: sellOrder.Quantity.Clone(),
				})
			}
		}
	}

	return events
}

// adjustTPSLQuantityAfterFee adjusts TPSL order quantities after fees and handles dust
// Returns the amount of dust to unlock (if any)
func (m *TradeMatcher) adjustTPSLQuantityAfterFee(tpslOrder *TPSLOrder, earnedAmount *uint256.Int, 
	tpPrice, slPrice *uint256.Int, side Side, e *SymbolEngine) (*uint256.Int, string) {
	
	if tpslOrder == nil || earnedAmount == nil || earnedAmount.IsZero() {
		return nil, ""
	}
	
	tpOrder := tpslOrder.TPOrder
	slOrder := tpslOrder.SLOrder
	
	// Get lot sizes for TP and SL prices
	tpLotSize := e.marketRules.GetLotSize(tpPrice)
	slLotSize := e.marketRules.GetLotSize(slPrice)
	
	var tpAddQty, slAddQty *uint256.Int
	var dustToken string
	
	if side == BUY {
		// BUY side: earned base tokens directly
		tpAddQty = earnedAmount
		slAddQty = earnedAmount
		baseToken, _, _ := SymbolToTokens(e.symbol)
		dustToken = baseToken
	} else {
		// SELL side: earned quote tokens, need to convert to base
		tpAddQty = common.Uint256DivScaledDecimal(earnedAmount, tpPrice)
		slAddQty = common.Uint256DivScaledDecimal(earnedAmount, slPrice)
		_, quoteToken, _ := SymbolToTokens(e.symbol)
		dustToken = quoteToken
	}
	
	// Calculate new quantities
	newTPOrigQty := new(uint256.Int).Add(tpOrder.Order.OrigQty, tpAddQty)
	newSLOrigQty := new(uint256.Int).Add(slOrder.Order.OrigQty, slAddQty)
	
	// Round down to lot sizes
	tpRounded, tpHasDust := RoundDownToLotSize(newTPOrigQty, tpLotSize)
	slRounded, slHasDust := RoundDownToLotSize(newSLOrigQty, slLotSize)
	
	// Update TP order quantities
	executedTPQty := new(uint256.Int).Sub(tpOrder.Order.OrigQty, tpOrder.Order.Quantity)
	tpOrder.Order.OrigQty = tpRounded
	tpOrder.Order.Quantity = new(uint256.Int).Sub(tpRounded, executedTPQty)
	if tpOrder.Order.Quantity.Sign() < 0 {
		tpOrder.Order.Quantity = uint256.NewInt(0)
	}
	
	// Update SL order quantities
	executedSLQty := new(uint256.Int).Sub(slOrder.Order.OrigQty, slOrder.Order.Quantity)
	slOrder.Order.OrigQty = slRounded
	slOrder.Order.Quantity = new(uint256.Int).Sub(slRounded, executedSLQty)
	if slOrder.Order.Quantity.Sign() < 0 {
		slOrder.Order.Quantity = uint256.NewInt(0)
	}
	
	// Calculate dust to unlock
	var dustToUnlock *uint256.Int
	if tpHasDust || slHasDust {
		if side == BUY {
			// For BUY side, dust is in base tokens
			tpDust := new(uint256.Int).Sub(newTPOrigQty, tpRounded)
			slDust := new(uint256.Int).Sub(newSLOrigQty, slRounded)
			// Use the larger dust amount
			if tpDust.Cmp(slDust) > 0 {
				dustToUnlock = tpDust
			} else {
				dustToUnlock = slDust
			}
		} else {
			// For SELL side, convert dust back to quote tokens
			var maxDustQuote *uint256.Int
			if tpHasDust {
				tpDustBase := new(uint256.Int).Sub(newTPOrigQty, tpRounded)
				maxDustQuote = common.Uint256MulScaledDecimal(tpDustBase, tpPrice)
			}
			if slHasDust {
				slDustBase := new(uint256.Int).Sub(newSLOrigQty, slRounded)
				slDustQuote := common.Uint256MulScaledDecimal(slDustBase, slPrice)
				if maxDustQuote == nil || slDustQuote.Cmp(maxDustQuote) > 0 {
					maxDustQuote = slDustQuote
				}
			}
			dustToUnlock = maxDustQuote
		}
	}
	
	return dustToUnlock, dustToken
}

// processSingleTrade handles a single trade's state updates
func (m *TradeMatcher) processSingleTrade(trade *Trade, e *SymbolEngine, locker *DefaultLocker) {
	e.currentPrice = trade.Price
	buyOrder, buyExist := e.userBook.GetOrder(trade.BuyOrderID)
	sellOrder, sellExist := e.userBook.GetOrder(trade.SellOrderID)
	if !buyExist || !sellExist {
		panic(ErrOrderNotFound.Error())
	}
	e.buyDirty[buyOrder.Price.String()] = struct{}{}
	e.sellDirty[sellOrder.Price.String()] = struct{}{}

	baseToken, quoteToken, err := SymbolToTokens(trade.Symbol)
	if err != nil {
		panic(ErrFailedToParseSymbol.Error())
	}

	log.Debug(LogProcessingTrade, "buyUser", buyOrder.UserID, "sellUser", sellOrder.UserID, "baseToken", baseToken, "quoteToken", quoteToken, "quantity", trade.Quantity.String(), "price", trade.Price.String())

	buyer := common.HexToAddress(buyOrder.UserID)
	seller := common.HexToAddress(sellOrder.UserID)
	totalCost := common.Uint256MulScaledDecimal(trade.Price, trade.Quantity)
	buyerEarn, buyerFee, sellerEarn, sellerFee, err := locker.ConsumeTradeBalance(buyer, seller, baseToken, quoteToken, trade.Quantity, totalCost, trade.IsBuyerMaker)
	if err != nil {
		return
	}

	// Fill in fee info in trade
	trade.BuyFeeTokenID, trade.BuyFeeAmount, trade.SellFeeTokenID, trade.SellFeeAmount =
		baseToken, buyerFee, quoteToken, sellerFee

	if buyOrder.TPSL != nil {
		// Adjust TPSL quantities with lot size rounding
		dust, dustToken := m.adjustTPSLQuantityAfterFee(
			buyOrder.TPSL, 
			buyerEarn,
			buyOrder.TPSL.TPOrder.StopPrice,
			buyOrder.TPSL.SLOrder.StopPrice,
			BUY,
			e,
		)
		
		// Unlock dust if any
		if dust != nil && dust.Sign() > 0 {
			locker.UnlockTokenBalance(buyer, dustToken, dust)
			log.Debug("TPSL dust unlocked for buyer", "amount", toDecimal(dust), "token", dustToken)
		}
	}
	if sellOrder.TPSL != nil {
		// Determine SL price based on order type
		slPrice := sellOrder.TPSL.SLOrder.StopPrice
		if sellOrder.TPSL.SLOrder.Order.OrderType == LIMIT && sellOrder.TPSL.SLOrder.Order.Price != nil {
			slPrice = sellOrder.TPSL.SLOrder.Order.Price
		}
		
		// Adjust TPSL quantities with lot size rounding
		dust, dustToken := m.adjustTPSLQuantityAfterFee(
			sellOrder.TPSL,
			sellerEarn,
			sellOrder.TPSL.TPOrder.StopPrice,
			slPrice,
			SELL,
			e,
		)
		
		// Unlock dust if any
		if dust != nil && dust.Sign() > 0 {
			locker.UnlockTokenBalance(seller, dustToken, dust)
			log.Debug("TPSL dust unlocked for seller", "amount", toDecimal(dust), "token", dustToken)
		}
	}
	if buyOrder.Quantity.IsZero() && buyOrder.TPSL != nil {
		e.addTPSLOrder(buyOrder.TPSL, locker)
		log.Info(LogTPSLOrderAdded+" for BUY", "TPStopPrice", toDecimal(buyOrder.TPSL.TPOrder.StopPrice), "SLStopPrice", toDecimal(buyOrder.TPSL.SLOrder.StopPrice))
	}
	if sellOrder.Quantity.IsZero() && sellOrder.TPSL != nil {
		e.addTPSLOrder(sellOrder.TPSL, locker)
		log.Info(LogTPSLOrderAdded+" for SELL", "TPStopPrice", toDecimal(sellOrder.TPSL.TPOrder.StopPrice), "SLStopPrice", toDecimal(sellOrder.TPSL.SLOrder.StopPrice))
	}
	e.checkTPSLOrders(trade.Price, locker)
}

// prepareOrder prepares an order for matching by setting up locks and adjusting prices
func (m *TradeMatcher) prepareOrder(order *Order, e *SymbolEngine, locker *DefaultLocker) (baseToken, quoteToken string, marketLocked *uint256.Int) {
	e.userBook.AddOrder(order)
	baseToken, quoteToken, _ = SymbolToTokens(order.Symbol)
	userAddr := common.HexToAddress(order.UserID)

	// Note: Limit orders in quote mode have already been converted to base mode in ToOrder
	// Only market orders can still be in QUOTE_MODE at this point
	
	if order.OrderType == MARKET {
		if order.Side == BUY {
			order.Price = MaxUint256
			marketLocked = locker.LockMarketOrder(userAddr, quoteToken)
			// For market buy in quote mode, order.Quantity represents quote amount to spend
		} else {
			order.Price = new(uint256.Int).SetUint64(OrderMinPrice)
			marketLocked = locker.LockMarketOrder(userAddr, baseToken)
			// For market sell in quote mode, order.Quantity represents quote amount to receive
		}
	} else {
		// Limit orders - already converted to base mode if originally in quote mode
		// So always treat as base mode here
		if order.Side == BUY {
			// Buy: calculate and lock quote amount (quantity is in base)
			cost := common.Uint256MulScaledDecimal(order.Price, order.Quantity)
			locker.LockTokenBalance(userAddr, quoteToken, cost)
			log.Info(LogLockedQuoteTokenBuy, "user", userAddr.Hex(), "quote", quoteToken, "amount", toDecimal(cost))
		} else {
			// Sell: lock base amount (quantity is in base)
			locker.LockTokenBalance(userAddr, baseToken, order.Quantity)
			log.Info(LogLockedBaseTokenSell, "user", userAddr.Hex(), "base", baseToken, "amount", toDecimal(order.Quantity))
		}
	}

	return baseToken, quoteToken, marketLocked
}
