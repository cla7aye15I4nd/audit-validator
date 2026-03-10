package orderbook

import (
	"fmt"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// -- Dispatcher: Manages all symbol engines --
// TODO-Orderbook: remove write methods, consider versioning
type Dex interface {
	GetSymbols() []string
	GetEngines() map[string]*SymbolEngine
	GetOrderRouting() []*OrderRoute
	AggregateL2DepthUpdate(time int64, blockNum string, prefetch bool) []*DepthUpdate
	DispatchReq(req Request)
	DispatchReqV2(interfaces.Request)
	GetOrder(orderId string) (*Order, bool)
	GetStopOrder(orderId string) (*StopOrder, bool)
	MakeSnapshot(blockNumber uint64, prefetch bool)
	GetSnapshot() []*Aggregated
	GetSnapshotFromLvl3() []*Aggregated
	GetMarketRules(symbol string) *MarketRules
	GetBestPrice(symbol string, side Side) *uint256.Int
	
	// Persistence methods
	SetCurrentBlock(blockNum uint64)
	OnBlockEnd(blockNum uint64)
	WriteSnapshot(blockNum uint64)
}

type OrderRoute struct {
	OrderId string
	Symbol  string
}

// OrderRoutingInfo stores routing information for order dispatch
type OrderRoutingInfo struct {
	Symbol string
}

type Dispatcher struct {
	symbols      map[string]struct{}
	engines      map[string]*SymbolEngine
	orderRouting map[string]OrderRoutingInfo
	mu           sync.RWMutex

	// Persistence layer
	persistence *PersistenceManager
}

func (d *Dispatcher) GetSymbols() []string {
	d.mu.RLock()
	defer d.mu.RUnlock()
	symbols := make([]string, 0, len(d.symbols))
	for sym := range d.symbols {
		symbols = append(symbols, sym)
	}
	return symbols
}

func (d *Dispatcher) GetEngines() map[string]*SymbolEngine {
	d.mu.RLock()
	defer d.mu.RUnlock()
	enginesCopy := make(map[string]*SymbolEngine, len(d.engines))
	for k, v := range d.engines {
		enginesCopy[k] = v
	}
	return enginesCopy
}

func (d *Dispatcher) GetOrderRouting() []*OrderRoute {
	routes := make([]*OrderRoute, 0, len(d.orderRouting))
	d.mu.RLock()
	defer d.mu.RUnlock()
	for k, v := range d.orderRouting {
		routes = append(routes, &OrderRoute{
			OrderId: k,
			Symbol:  v.Symbol,
		})
	}
	return routes
}

// AggregateL2DepthUpdate aggregates each engine's depth update and returns the diff.
// If there is no update, it returns an empty slice.
func (d *Dispatcher) AggregateL2DepthUpdate(time int64, blockNum string, prefetch bool) []*DepthUpdate {
	if prefetch {
		return nil
	}

	d.mu.Lock()
	defer d.mu.Unlock()

	var diff []*DepthUpdate
	for sym, en := range d.engines {
		buyDelta, sellDelta := en.UpdateLevel2()
		if len(buyDelta) == 0 && len(sellDelta) == 0 {
			continue
		}

		engineDiff := &DepthUpdate{
			Stream: sym + "@depth",
			Data: &DeltaData{
				EventType: "depthUpdate",
				EventTime: time,
				Symbol:    sym,
				FirstID:   blockNum,
				FinalID:   blockNum,
				Bids:      buyDelta,
				Asks:      sellDelta,
			},
		}

		diff = append(diff, engineDiff)
	}
	return diff
}

func NewDispatcher() *Dispatcher {
	return &Dispatcher{
		symbols:      make(map[string]struct{}),
		engines:      make(map[string]*SymbolEngine),
		orderRouting: make(map[string]OrderRoutingInfo),
		persistence:  nil, // No persistence by default
	}
}

// SetCurrentBlock sets the current block number for persistence
func (d *Dispatcher) SetCurrentBlock(blockNum uint64) {
	// Set block context on all symbol engines for event generation
	d.mu.RLock()
	for _, engine := range d.engines {
		engine.SetBlockContext(blockNum)
	}
	d.mu.RUnlock()

	if d.persistence != nil {
		d.persistence.SetBlock(blockNum)
		// TODO: Update v1 persistence manager to accept stateRoot
		// For now, we just set the block number
	}
}

// OnBlockEnd signals the end of a block for snapshot checks
func (d *Dispatcher) OnBlockEnd(blockNum uint64) {
	if d.persistence != nil {
		d.persistence.OnBlockEnd(blockNum, d)
	}
}

func (d *Dispatcher) WriteSnapshot(blockNum uint64) {
	// nothing to do for legacy disaptcher
}

// Close gracefully shuts down the dispatcher and flushes persistence
func (d *Dispatcher) Close() error {
	log.Info("Closing dispatcher...")

	// First, shutdown all symbol engines
	d.mu.Lock()
	for symbol, engine := range d.engines {
		log.Debug("Shutting down symbol engine", "symbol", symbol)
		engine.Shutdown()
	}
	d.mu.Unlock()

	// Then close persistence (which will flush pending events)
	if d.persistence != nil {
		log.Info("Flushing persistence...")
		if err := d.persistence.Close(); err != nil {
			log.Error("Failed to close persistence", "error", err)
			return err
		}
	}

	log.Info("Dispatcher closed successfully")
	return nil
}

func (d *Dispatcher) DispatchOrder(req *OrderRequest) {
	// Wrap request for persistence if enabled
	if d.persistence != nil && d.persistence.IsEnabled() {
		wrapped := d.wrapRequestForPersistence(req)
		req = wrapped.(*OrderRequest)
	}

	d.mu.Lock()
	engine, exists := d.engines[req.Order.Symbol]
	if !exists {
		d.symbols[req.Order.Symbol] = struct{}{}
		engine = NewSymbolEngine(req.Order.Symbol)
		d.engines[req.Order.Symbol] = engine
	}

	// Register order routing - main order always gets registered
	d.orderRouting[req.Order.OrderID] = OrderRoutingInfo{
		Symbol: req.Order.Symbol,
	}

	// Register additional routing for TPSL orders
	if req.Order.TPSL != nil {
		// Register TP order
		if req.Order.TPSL.TPOrder != nil {
			d.orderRouting[req.Order.TPSL.TPOrder.Order.OrderID] = OrderRoutingInfo{
				Symbol: req.Order.Symbol,
			}
		}
		// Register SL order
		if req.Order.TPSL.SLOrder != nil {
			d.orderRouting[req.Order.TPSL.SLOrder.Order.OrderID] = OrderRoutingInfo{
				Symbol: req.Order.Symbol,
			}
		}
	}
	d.mu.Unlock()

	engine.EnqueueMsg(req)
}

// wrapRequestForPersistence wraps the request's response channel to capture the response for logging
func (d *Dispatcher) wrapRequestForPersistence(req Request) Request {
	originalRespCh := req.ResponseChannel()
	if originalRespCh == nil {
		return req // No response channel to wrap
	}

	wrappedRespCh := make(chan Response, 1)
	wrappedReq := req.Clone(wrappedRespCh)

	// Start goroutine to capture and forward the response
	go func() {
		// Add timeout to prevent hanging
		select {
		case resp := <-wrappedRespCh:
			// Log to persistence
			d.persistence.LogRequestResponse(resp)
			// Forward to original channel
			originalRespCh <- resp
		case <-time.After(5 * time.Second):
			log.Error("Timeout waiting for response from symbol engine")
			// Send generic error response
			originalRespCh <- NewErrorResponse(fmt.Errorf("timeout waiting for response from symbol engine"))
		}
	}()

	return wrappedReq
}

func (d *Dispatcher) DispatchStopOrder(req *StopOrderRequest) {
	// Wrap request for persistence if enabled
	if d.persistence != nil && d.persistence.IsEnabled() {
		wrapped := d.wrapRequestForPersistence(req)
		req = wrapped.(*StopOrderRequest)
	}

	d.mu.Lock()
	engine, exists := d.engines[req.StopOrder.Order.Symbol]
	if !exists {
		d.symbols[req.StopOrder.Order.Symbol] = struct{}{}
		engine = NewSymbolEngine(req.StopOrder.Order.Symbol)
		d.engines[req.StopOrder.Order.Symbol] = engine
	}
	// Register stop order routing
	d.orderRouting[req.StopOrder.Order.OrderID] = OrderRoutingInfo{
		Symbol: req.StopOrder.Order.Symbol,
	}
	d.mu.Unlock()
	engine.EnqueueMsg(req)
}

func (d *Dispatcher) DispatchCancelReq(req *CancelRequest) {
	// Wrap request for persistence if enabled
	if d.persistence != nil && d.persistence.IsEnabled() {
		wrapped := d.wrapRequestForPersistence(req)
		req = wrapped.(*CancelRequest)
	}

	d.mu.RLock()
	routingInfo, exists := d.orderRouting[req.OrderID]
	engine := d.engines[routingInfo.Symbol]
	d.mu.RUnlock()
	if exists && engine != nil {
		engine.EnqueueMsg(req)
	} else {
		log.Warn("Order not found or engine nil", "orderID", req.OrderID, "exists", exists, "engineNil", engine == nil)
		req.ResponseChannel() <- NewErrorResponse(fmt.Errorf("order not found: %s", req.OrderID))
	}
}

func (d *Dispatcher) DispatchCancelAll(req *CancelAllRequest) {

	d.mu.RLock()
	defer d.mu.RUnlock()

	var allCanceled []string
	var allEvents []OrderbookEvent

	for _, engine := range d.engines {
		copyReq := NewCancelAllRequest(req.UserID, req.StateDB(), req.FeeGetter())

		engine.EnqueueMsg(copyReq)

		resp := <-copyReq.ResponseChannel()
		if cancelResp, ok := resp.(*CancelAllResponse); ok {
			allCanceled = append(allCanceled, cancelResp.CancelledOrderIDs...)
			// Collect events from each engine
			if len(resp.Events()) > 0 {
				allEvents = append(allEvents, resp.Events()...)
			}
		}
	}

	// Send aggregated response
	finalResp := NewCancelAllResponse(allCanceled, allEvents)

	// Log to persistence if enabled
	if d.persistence != nil && d.persistence.IsEnabled() {
		d.persistence.LogRequestResponse(finalResp)
	}

	req.ResponseChannel() <- finalResp
}

func (d *Dispatcher) DispatchModify(req *ModifyRequest) {
	// Wrap request for persistence if enabled
	if d.persistence != nil && d.persistence.IsEnabled() {
		wrapped := d.wrapRequestForPersistence(req)
		req = wrapped.(*ModifyRequest)
	}

	d.mu.RLock()
	routingInfo, exists := d.orderRouting[req.Args.OrderId]
	engine := d.engines[routingInfo.Symbol]
	d.mu.RUnlock()

	if exists {
		// Register the new order ID with the same routing info as the original
		d.mu.Lock()
		d.orderRouting[req.Args.NewOrderId] = OrderRoutingInfo{
			Symbol: routingInfo.Symbol,
		}
		d.mu.Unlock()

		engine.EnqueueMsg(req)
	} else {
		req.ResponseChannel() <- NewErrorResponse(fmt.Errorf("order not found: %s", req.Args.OrderId))
	}
}

func (d *Dispatcher) DispatchReq(req Request) {
	switch r := req.(type) {
	case *OrderRequest:
		d.DispatchOrder(r)
	case *CancelRequest:
		d.DispatchCancelReq(r)
	case *CancelAllRequest:
		d.DispatchCancelAll(r)
	case *ModifyRequest:
		d.DispatchModify(r)
	case *StopOrderRequest:
		d.DispatchStopOrder(r)
	}
}

func (d *Dispatcher) DispatchReqV2(interfaces.Request) {
	panic("not implemented")
}

func (d *Dispatcher) GetOrder(orderId string) (*Order, bool) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	routingInfo, exists := d.orderRouting[orderId]
	if !exists {
		return nil, false
	}
	return d.engines[routingInfo.Symbol].userBook.GetOrder(orderId)
}

func (d *Dispatcher) GetStopOrder(orderId string) (*StopOrder, bool) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	routingInfo, exists := d.orderRouting[orderId]
	if !exists {
		return nil, false
	}
	stopOrder := d.engines[routingInfo.Symbol].getStopOrder(orderId)
	if stopOrder == nil {
		return nil, false
	}

	return stopOrder, true
}

func (d *Dispatcher) MakeSnapshot(blockNumber uint64, prefetch bool) {
	if prefetch {
		return
	}

	d.mu.RLock()
	defer d.mu.RUnlock()

	var wg sync.WaitGroup
	for _, engine := range d.engines {
		wg.Add(1)
		go func(e *SymbolEngine) {
			defer wg.Done()
			e.MakeSnapshot(blockNumber)
		}(engine)
	}
	wg.Wait()
}

func (d *Dispatcher) GetSnapshot() []*Aggregated {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var lvl2 []*Aggregated
	for _, engine := range d.engines {
		lvl2 = append(lvl2, engine.GetSnapshot())
	}
	return lvl2
}

func (d *Dispatcher) GetSnapshotFromLvl3() []*Aggregated {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var lvl2 []*Aggregated
	for _, engine := range d.engines {
		lvl2 = append(lvl2, engine.GetSnapshotFromLevel3())
	}
	return lvl2
}

func (d *Dispatcher) GetMarketRules(symbol string) *MarketRules {
	d.mu.RLock()
	engine, exists := d.engines[symbol]
	d.mu.RUnlock()

	if exists && engine != nil && engine.marketRules != nil {
		return engine.marketRules
	}

	// Return default market rules if symbol not found or marketRules is nil
	return NewMarketRules()
}

func (d *Dispatcher) GetBestPrice(symbol string, side Side) *uint256.Int {
	d.mu.RLock()
	engine, exists := d.engines[symbol]
	d.mu.RUnlock()

	if !exists || engine == nil {
		return nil
	}

	// For BUY orders, need best ask (lowest sell price)
	// For SELL orders, need best bid (highest buy price)
	if side == BUY {
		return engine.GetBestAsk()
	} else {
		return engine.GetBestBid()
	}
}
