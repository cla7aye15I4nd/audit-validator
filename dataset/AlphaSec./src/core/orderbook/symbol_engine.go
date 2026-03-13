package orderbook

import (
	"container/heap"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// SymbolEngine manages the orderbook for a specific trading symbol.
// Each symbol runs in its own goroutine to process orders concurrently.
// It maintains buy/sell queues, user orders, TPSL orders, and Level2 book data.

// Level2Entry and Level2Book types are now in level2_book.go

type SymbolEngine struct {
	symbol                 string
	buyQueue               BuyQueue
	sellQueue              SellQueue
	userBook               *UserBook
	conditionalOrderManager *ConditionalOrderManager
	snapshotManager        *SnapshotManager
	tradeMatcher           *TradeMatcher
	triggered              []*TriggeredOrder

	level2Book *Level2Book
	buyDirty   map[string]struct{}
	sellDirty  map[string]struct{}

	currentPrice *uint256.Int
	marketRules  *MarketRules // Market rules for tick/lot size validation

	queue chan Request
	quit  chan struct{} // Channel for graceful shutdown

	stateMu sync.RWMutex

	// Event tracking
	currentBlock uint64
}

func (e *SymbolEngine) GetSymbol() string {
	return e.symbol
}

func (e *SymbolEngine) GetBuyQueue() BuyQueue {
	return e.buyQueue
}

func (e *SymbolEngine) GetSellQueue() SellQueue {
	return e.sellQueue
}

func (e *SymbolEngine) GetUserBook() *UserBook {
	return e.userBook
}

func (e *SymbolEngine) GetTPSLOrders() []*TPSLOrder {
	return e.conditionalOrderManager.GetOrders()
}

func (e *SymbolEngine) GetTriggered() []*TriggeredOrder {
	return e.triggered
}

func (e *SymbolEngine) GetLevel2Book() *Level2Book {
	return e.level2Book
}

func (e *SymbolEngine) GetCurrentPrice() *uint256.Int {
	return e.currentPrice
}

func (e *SymbolEngine) GetBestBid() *uint256.Int {
	e.stateMu.RLock()
	defer e.stateMu.RUnlock()
	
	// Best bid is the highest buy price
	if len(e.buyQueue) > 0 {
		return e.buyQueue[0].Price.Clone()
	}
	return nil
}

func (e *SymbolEngine) GetBestAsk() *uint256.Int {
	e.stateMu.RLock()
	defer e.stateMu.RUnlock()
	
	// Best ask is the lowest sell price
	if len(e.sellQueue) > 0 {
		return e.sellQueue[0].Price.Clone()
	}
	return nil
}

// Shutdown gracefully stops the symbol engine by closing the quit channel.
// This signals the run goroutine to terminate cleanly.
// TODO-Orderbook: use shutdown to terminate symbol engine gracefully
func (e *SymbolEngine) Shutdown() {
	select {
	case <-e.quit:
		// Already closed
		return
	default:
		close(e.quit)
	}
}

func NewSymbolEngine(symbol string) *SymbolEngine {
	e := &SymbolEngine{
		symbol:                  symbol,
		buyQueue:                make(BuyQueue, 0),
		sellQueue:               make(SellQueue, 0),
		userBook:                NewUserBook(),
		conditionalOrderManager: NewConditionalOrderManager(),
		snapshotManager:         NewSnapshotManager(symbol),
		marketRules:             NewMarketRules(),
		tradeMatcher:            NewTradeMatcher(symbol),
		triggered:               make([]*TriggeredOrder, 0),
		level2Book:              NewLevel2Book(),
		buyDirty:                make(map[string]struct{}),
		sellDirty:               make(map[string]struct{}),
		queue:                   make(chan Request, OrderQueueSize),
		quit:                    make(chan struct{}),
	}

	// TODO-Orderbook: terminate this goroutine properly
	go e.run()
	return e
}

// SetBlockContext sets the current block for event generation
func (e *SymbolEngine) SetBlockContext(blockNum uint64) {
	e.stateMu.Lock()
	defer e.stateMu.Unlock()

	e.currentBlock = blockNum
}

// createEvent creates a new event with current block context
func (e *SymbolEngine) createEvent() BaseEvent {
	return BaseEvent{
		BlockNumber: e.currentBlock,
		TxIndex:     0, // Not tracking tx index for now
		Timestamp:   time.Now().Unix(),
	}
}

func (e *SymbolEngine) run() {
	for {
		select {
		case msg := <-e.queue:
			base, quote, _ := SymbolToTokenIds(e.symbol)
			// TODO-Orderbook: error handling for GetMarketFees
			makerFee, takerFee, _ := msg.FeeGetter().GetMarketFees(base, quote)
			var response Response
			
			switch req := msg.(type) {
			case *OrderRequest:
				trades, triggered, events := e.processOrder(req.Order, wrapLocker(msg.StateDB(), makerFee, takerFee))
				response = NewOrderResponse(trades, triggered, events)
			case *CancelRequest:
				isCanceled, cancelledIDs, events := e.cancelOrder(req.OrderID, wrapLocker(msg.StateDB(), makerFee, takerFee))
				response = NewCancelResponse(isCanceled, cancelledIDs, events)
			case *CancelAllRequest:
				canceled, events := e.cancelAllOrdersByUser(req.UserID, wrapLocker(msg.StateDB(), makerFee, takerFee))
				response = NewCancelAllResponse(canceled, events)
			case *ModifyRequest:
				trades, triggered, cancelledIDs, modified, events := e.modifyRequest(req.Args, wrapLocker(msg.StateDB(), makerFee, takerFee))
				response = NewModifyResponse(trades, triggered, cancelledIDs, modified, events)
			case *StopOrderRequest:
				trades, triggered, triggerAbove, events := e.addStopOrder(req.StopOrder, wrapLocker(msg.StateDB(), makerFee, takerFee))
				response = NewStopOrderResponse(trades, triggered, triggerAbove, events)
			default:
				panic(ErrUnknownRequestType.Error())
			}

			msg.ResponseChannel() <- response
		case <-e.quit:
			log.Info(LogEngineShuttingDown, "symbol", e.symbol)
			return
		}
	}
}

func (e *SymbolEngine) getStopOrder(orderID string) *StopOrder {
	return e.conditionalOrderManager.GetOrderByID(orderID)
}

func (e *SymbolEngine) MakeSnapshot(block uint64) {
	e.stateMu.RLock()
	bids, asks := e.level2Book.ToSortedStringLists()
	e.stateMu.RUnlock()
	e.snapshotManager.MakeSnapshot(block, bids, asks)
}

func (e *SymbolEngine) GetSnapshot() *Aggregated {
	return e.snapshotManager.GetSnapshot()
}

// BuildLevel2BookFromQueues delegates to the extracted function
func (e *SymbolEngine) BuildLevel2BookFromQueues() *Level2Book {
	return buildLevel2BookFromQueues(e.buyQueue, e.sellQueue)
}

func (e *SymbolEngine) GetSnapshotFromLevel3() *Aggregated {
	e.stateMu.RLock()
	defer e.stateMu.RUnlock()

	return e.snapshotManager.CreateLevel3Snapshot(e.buyQueue, e.sellQueue)
}

// UpdateLevel2 updates the Level2 book and returns the changes
func (e *SymbolEngine) UpdateLevel2() ([][]string, [][]string) {
	e.stateMu.Lock()
	defer e.stateMu.Unlock()

	buyDelta := updateLevel2ByQueue(e.level2Book, e.buyQueue, BUY, e.buyDirty)
	sellDelta := updateLevel2ByQueue(e.level2Book, e.sellQueue, SELL, e.sellDirty)
	e.buyDirty = make(map[string]struct{})
	e.sellDirty = make(map[string]struct{})
	return buyDelta, sellDelta
}

func (e *SymbolEngine) addTPSLOrder(tpslOrder *TPSLOrder, locker *DefaultLocker) {
	e.conditionalOrderManager.AddTPSLOrder(tpslOrder, locker)
}

func (e *SymbolEngine) addStopOrder(stopOrder *StopOrder, locker *DefaultLocker) (trades []*Trade, triggered []string, triggerAbove *bool, events []OrderbookEvent) {
	shouldTriggerImmediately, triggerAboveValue := e.conditionalOrderManager.AddStopOrder(stopOrder, e.currentPrice, locker)

	if shouldTriggerImmediately {
		trades, triggered, events = e.processOrder(stopOrder.Order, locker)
		triggered = append([]string{stopOrder.Order.OrderID}, triggered...)
		return trades, triggered, nil, events
	}

	// Build TPSL order for persistence and event generation
	var tpslOrder *TPSLOrder
	if (triggerAboveValue && stopOrder.Order.Side == BUY) ||
		(!triggerAboveValue && stopOrder.Order.Side == SELL) {
		// TP
		tpslOrder = &TPSLOrder{
			TPOrder: stopOrder,
			SLOrder: nil,
		}
	} else {
		// SL
		tpslOrder = &TPSLOrder{
			TPOrder: nil,
			SLOrder: stopOrder,
		}
	}

	// Generate TPSLOrderAddedEvent
	events = []OrderbookEvent{
		&TPSLOrderAddedEvent{
			BaseEvent: e.createEvent(),
			TPSLOrder: tpslOrder.Copy(),
		},
	}

	return nil, nil, &triggerAboveValue, events
}

func (e *SymbolEngine) checkTPSLOrders(lastTradePrice *uint256.Int, locker *DefaultLocker) {
	triggered := e.conditionalOrderManager.CheckOrders(lastTradePrice, e.userBook, locker, e.cancelOrderWithoutTPSL)
	e.triggered = append(e.triggered, triggered...)
}

func minUint256(a, b *uint256.Int) *uint256.Int {
	if a.Cmp(b) < 0 {
		return new(uint256.Int).Set(a)
	}
	return new(uint256.Int).Set(b)
}

func (e *SymbolEngine) processOrder(order *Order, locker *DefaultLocker) ([]*Trade, []string, []OrderbookEvent) {
	// TODO-Orderbook: Separate asset locking logics from this method
	var allEvents []OrderbookEvent

	trades, events := e.processOrderWithoutStopOrder(order, locker)
	allEvents = append(allEvents, events...)

	var triggeredOrderIDs []string
	for len(e.triggered) > 0 {
		triggeredOrder := e.triggered[0]
		if triggeredOrder.TriggerType != TAKEPROFIT {
			triggeredOrderIDs = append(triggeredOrderIDs, triggeredOrder.order.OrderID)
		}
		e.triggered = e.triggered[1:]
		stopTrades, stopEvents := e.processOrderWithoutStopOrder(triggeredOrder.order, locker)
		trades = append(trades, stopTrades...)
		allEvents = append(allEvents, stopEvents...)
	}
	return trades, triggeredOrderIDs, allEvents
}

func (e *SymbolEngine) processOrderWithoutStopOrder(order *Order, locker *DefaultLocker) ([]*Trade, []OrderbookEvent) {
	if locker == nil {
		log.Error(ErrNilLocker.Error(), "symbol", e.symbol, "orderID", order.OrderID)
		return []*Trade{}, nil // Return empty trades to prevent panic
	}

	e.stateMu.Lock()
	defer e.stateMu.Unlock()

	log.Info(LogProcessingOrder,
		"orderId", order.OrderID,
		"userId", order.UserID,
		"symbol", order.Symbol,
		"side", order.Side.String(),
		"price", toDecimal(order.Price),
		"origQty", toDecimal(order.OrigQty),
		"quantity", toDecimal(order.Quantity),
		"timestamp", order.Timestamp,
		"orderType", order.OrderType,
		"TPSL", order.TPSL != nil)
	if order.TPSL != nil {
		log.Info("with TPSLOrder",
			"TPStopPrice", toDecimal(order.TPSL.TPOrder.StopPrice),
			"TPTriggerAbove", order.TPSL.TPOrder.TriggerAbove,
			"TPOrderPrice", toDecimal(order.TPSL.TPOrder.Order.Price),
			"TPOrderQty", toDecimal(order.TPSL.TPOrder.Order.Quantity),
			"SLStopPrice", toDecimal(order.TPSL.SLOrder.StopPrice),
			"SLTriggerAbove", order.TPSL.SLOrder.TriggerAbove,
			"SLOrderPrice", toDecimal(order.TPSL.SLOrder.Order.Price),
			"SLOrderQty", toDecimal(order.TPSL.SLOrder.Order.Quantity),
		)
	}

	var trades []*Trade
	var events []OrderbookEvent

	// Prepare order (handle locking and price adjustment)
	baseToken, quoteToken, marketLocked := e.tradeMatcher.prepareOrder(order, e, locker)
	userAddr := common.HexToAddress(order.UserID)

	// Match order based on side
	if order.Side == BUY {
		var executedCost *uint256.Int
		trades, executedCost = e.tradeMatcher.matchBuyOrder(order, e, locker)

		if order.OrderType == MARKET {
			locker.UnlockMarketRefund(userAddr, quoteToken, marketLocked, executedCost)
		}

		if order.Quantity.Sign() > 0 && order.OrderType == LIMIT {
			heap.Push(&e.buyQueue, order)
			e.buyDirty[order.Price.String()] = struct{}{}

			// Generate OrderAddedEvent
			events = append(events, &OrderAddedEvent{
				BaseEvent: e.createEvent(),
				Order:     order.Copy(),
			})
		}
	} else {
		var executedQty *uint256.Int
		trades, executedQty = e.tradeMatcher.matchSellOrder(order, e, locker)

		if order.OrderType == MARKET {
			locker.UnlockMarketRefund(userAddr, baseToken, marketLocked, executedQty)
		}

		if order.Quantity.Sign() > 0 && order.OrderType == LIMIT {
			heap.Push(&e.sellQueue, order)
			e.sellDirty[order.Price.String()] = struct{}{}

			// Generate OrderAddedEvent
			events = append(events, &OrderAddedEvent{
				BaseEvent: e.createEvent(),
				Order:     order.Copy(),
			})
		}
	}

	// Process completed trades and generate events
	tradeEvents := e.tradeMatcher.processCompletedTradesWithEvents(trades, e, locker)
	events = append(events, tradeEvents...)

	return trades, events
}

func (e *SymbolEngine) cancelOrderWithoutTPSL(orderID string, locker *DefaultLocker) bool {
	order, exist := e.userBook.GetOrder(orderID)
	if !exist || order == nil || order.IsCanceled {
		log.Warn(LogOrderNotFoundOrCanceled, "orderID", orderID)
		return false
	}
	order.IsCanceled = true

	if order.OrderType != LIMIT || order.Quantity.IsZero() {
		log.Warn(ErrMarketOrderCannotCancel.Error(), "orderID", orderID)
		return false
	}

	args, _ := order.ToCancelArgs()
	locker.UnlockTokenBalance(args.From, args.Token, args.Amount)

	// Remove from heap
	if order.Side == BUY {
		log.Info(LogUnlockedQuoteTokenCancel, "user", args.From, "amount", args.Amount, "quoteToken", args.Token)
		heap.Remove(&e.buyQueue, order.Index)
		e.buyDirty[order.Price.String()] = struct{}{}
	} else {
		log.Info(LogUnlockedBaseTokenCancel, "user", args.From, "amount", args.Amount, "baseToken", args.Token)
		heap.Remove(&e.sellQueue, order.Index)
		e.sellDirty[order.Price.String()] = struct{}{}
	}

	return true
}

func (e *SymbolEngine) cancelOrder(orderID string, locker *DefaultLocker) (bool, []string, []OrderbookEvent) {
	e.stateMu.Lock()
	defer e.stateMu.Unlock()

	var events []OrderbookEvent
	var cancelledOrderIDs []string
	log.Info(LogProcessingCancelOrder, "orderId", orderID)

	// Check if it's a conditional order
	cancelledIDs, found := e.conditionalOrderManager.CancelOrder(orderID, locker, e.cancelOrderWithoutTPSL)
	if found {
		// Generate events for all cancelled orders
		for _, cancelledID := range cancelledIDs {
			events = append(events, &TPSLOrderRemovedEvent{
				BaseEvent: e.createEvent(),
				OrderID:   cancelledID,
				Symbol:    e.symbol,
			})
		}
		return true, cancelledIDs, events
	}

	// Get order details before canceling (for event generation)
	order, exists := e.userBook.GetOrder(orderID)

	canceled := e.cancelOrderWithoutTPSL(orderID, locker)
	if canceled && exists && order != nil {
		cancelledOrderIDs = append(cancelledOrderIDs, orderID)
		
		// If the order has TPSL attached, generate IDs for the TP and SL orders
		// even though they may not have been created yet (if order wasn't fully filled)
		if order.TPSL != nil {
			// Generate the TP and SL order IDs based on the transaction hash
			txHash := common.HexToHash(orderID)
			tpID := GenerateConditionalOrderID(txHash, TPIncrement)
			slID := GenerateConditionalOrderID(txHash, SLIncrement)
			cancelledOrderIDs = append(cancelledOrderIDs, tpID, slID)
		}
		
		// Generate OrderRemovedEvent with the order details we captured before canceling
		events = append(events, &OrderRemovedEvent{
			BaseEvent: e.createEvent(),
			OrderID:   orderID,
			Symbol:    e.symbol,
			Side:      order.Side,
		})
	}
	return canceled, cancelledOrderIDs, events
}

func (e *SymbolEngine) cancelAllOrdersByUser(userId string, locker *DefaultLocker) ([]string, []OrderbookEvent) {
	e.stateMu.Lock()
	defer e.stateMu.Unlock()

	addr := common.HexToAddress(userId)
	baseToken, quoteToken, _ := SymbolToTokens(e.symbol)
	cancelOrderIds := make([]string, 0)
	var events []OrderbookEvent

	// Iterate through BUY queue
	for i := 0; i < len(e.buyQueue); {
		order := e.buyQueue[i]
		if order.UserID != userId || order.IsCanceled || order.OrderType != LIMIT || order.Quantity.IsZero() {
			i++
			continue
		}
		order.IsCanceled = true
		heap.Remove(&e.buyQueue, order.Index)
		e.buyDirty[order.Price.String()] = struct{}{}
		unlockAmount := common.Uint256MulScaledDecimal(order.Price, order.Quantity)
		locker.UnlockTokenBalance(addr, quoteToken, unlockAmount)
		log.Info(LogCancelAllUnlockedBuy, "userId", userId, "amount", unlockAmount, "token", quoteToken)
		cancelOrderIds = append(cancelOrderIds, order.OrderID)

		// If the order has TPSL attached, generate IDs for the TP and SL orders
		// even though they may not have been created yet (if order wasn't fully filled)
		if order.TPSL != nil {
			// Generate the TP and SL order IDs based on the transaction hash
			txHash := common.HexToHash(order.OrderID)
			tpID := GenerateConditionalOrderID(txHash, TPIncrement)
			slID := GenerateConditionalOrderID(txHash, SLIncrement)
			cancelOrderIds = append(cancelOrderIds, tpID, slID)
		}

		// Generate OrderRemovedEvent
		events = append(events, &OrderRemovedEvent{
			BaseEvent: e.createEvent(),
			OrderID:   order.OrderID,
			Symbol:    e.symbol,
			Side:      BUY,
		})

		// heap.Remove replaces order.Index position with another element, so don't increment i
	}

	// Iterate through SELL queue
	for i := 0; i < len(e.sellQueue); {
		order := e.sellQueue[i]
		if order.UserID != userId || order.IsCanceled || order.OrderType != LIMIT || order.Quantity.IsZero() {
			i++
			continue
		}
		order.IsCanceled = true
		heap.Remove(&e.sellQueue, order.Index)
		e.sellDirty[order.Price.String()] = struct{}{}
		locker.UnlockTokenBalance(addr, baseToken, order.Quantity)
		log.Info(LogCancelAllUnlockedSell, "userId", userId, "amount", order.Quantity, "token", baseToken)
		cancelOrderIds = append(cancelOrderIds, order.OrderID)

		// If the order has TPSL attached, generate IDs for the TP and SL orders
		// even though they may not have been created yet (if order wasn't fully filled)
		if order.TPSL != nil {
			// Generate the TP and SL order IDs based on the transaction hash
			txHash := common.HexToHash(order.OrderID)
			tpID := GenerateConditionalOrderID(txHash, TPIncrement)
			slID := GenerateConditionalOrderID(txHash, SLIncrement)
			cancelOrderIds = append(cancelOrderIds, tpID, slID)
		}

		// Generate OrderRemovedEvent
		events = append(events, &OrderRemovedEvent{
			BaseEvent: e.createEvent(),
			OrderID:   order.OrderID,
			Symbol:    e.symbol,
			Side:      SELL,
		})
	}

	// Iterate through and remove conditional orders
	conditionalCancelledIds := e.conditionalOrderManager.CancelAllByUser(userId, locker, baseToken, quoteToken)
	for _, conditionalId := range conditionalCancelledIds {
		// Generate TPSLOrderRemovedEvent
		events = append(events, &TPSLOrderRemovedEvent{
			BaseEvent: e.createEvent(),
			OrderID:   conditionalId,
			Symbol:    e.symbol,
		})
	}
	cancelOrderIds = append(cancelOrderIds, conditionalCancelledIds...)

	log.Info("CancelAll generated events", "userId", userId, "events", len(events), "canceledOrders", len(cancelOrderIds))
	return cancelOrderIds, events
}

func (e *SymbolEngine) modifyRequest(args *ModifyArgs, locker *DefaultLocker) ([]*Trade, []string, []string, bool, []OrderbookEvent) {
	orig, exist := e.userBook.GetOrder(args.OrderId)
	if !exist || orig == nil || orig.IsCanceled {
		log.Warn(LogModifyFailed+": original order not found or canceled", "orderId", args.OrderId)
		return nil, nil, nil, false, nil
	}

	if orig.UserID != args.From.Hex() {
		log.Warn(LogModifyFailed+": user mismatch", "expected", orig.UserID, "got", args.From.Hex())
		return nil, nil, nil, false, nil
	}

	// Skip if no new fields provided
	if args.NewPrice == nil && args.NewQty == nil {
		log.Warn(LogModifySkipped)
		return nil, nil, nil, false, nil
	}

	// Cancel existing order (generates cancel events and returns cancelled IDs)
	success, cancelledIDs, cancelEvents := e.cancelOrder(args.OrderId, locker)
	if !success {
		log.Warn(LogModifyFailed+": unable to cancel original order", "orderId", args.OrderId)
		return nil, nil, nil, false, nil
	}

	// Create new order with new order ID (modify tx hash)
	newOrder := orig.Copy() // deep copy
	newOrder.OrderID = args.NewOrderId // Use modify tx hash as new order ID
	newOrder.IsCanceled = false
	newOrder.Timestamp = time.Now().UnixNano()
	if args.NewPrice != nil {
		newOrder.Price = args.NewPrice
	}
	if args.NewQty != nil {
		filled := new(uint256.Int).Sub(orig.OrigQty, orig.Quantity)
		if args.NewQty.Cmp(filled) < 0 {
			log.Warn(LogModifyFailed+": "+ErrNewQuantityLessThanFilled.Error(), "orderId", args.OrderId)
			return nil, nil, cancelledIDs, false, cancelEvents
		}
		newOrder.OrigQty = args.NewQty
		newOrder.Quantity = new(uint256.Int).Sub(args.NewQty, filled)
	}

	// Attempt to execute order (generates order events)
	trades, triggered, orderEvents := e.processOrder(newOrder, locker)

	// Combine all events (cancel + new order)
	allEvents := append(cancelEvents, orderEvents...)

	log.Info(LogModifyCompleted, "orderId", newOrder.OrderID)
	return trades, triggered, cancelledIDs, true, allEvents
}

func (e *SymbolEngine) EnqueueMsg(msg Request) {
	e.queue <- msg
}
