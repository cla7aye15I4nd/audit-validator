package orderbook

import (
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	v2dispatcher "github.com/ethereum/go-ethereum/core/orderbook/v2/dispatcher"
	v2engine "github.com/ethereum/go-ethereum/core/orderbook/v2/engine"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	v2types "github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// DexAdapter adapts the v2 Dispatcher to implement the v1 Dex interface
type DexAdapter struct {
	dispatcher *v2dispatcher.Dispatcher
}

// NewDexAdapter creates a new adapter
func NewDexAdapter(dispatcher *v2dispatcher.Dispatcher) *DexAdapter {
	return &DexAdapter{
		dispatcher: dispatcher,
	}
}

// GetSymbols returns all active trading symbols
func (d *DexAdapter) GetSymbols() []string {
	// Get all symbols from dispatcher engines
	if d.dispatcher == nil {
		return []string{}
	}

	// Get stats from dispatcher which includes engine info
	stats := d.dispatcher.GetStats()
	engines, ok := stats["engines"].(map[string]interface{})
	if !ok {
		return []string{}
	}

	symbols := make([]string, 0, len(engines))
	for symbol := range engines {
		symbols = append(symbols, symbol)
	}

	return symbols
}

// GetEngines returns all active symbol engines
func (d *DexAdapter) GetEngines() map[string]*SymbolEngine {
	// V2 engines are incompatible with V1 engine type
	// Return empty map as this is mostly for debugging/inspection
	// V2 stats can be retrieved via GetStats() method
	log.Debug("GetEngines called on v2 adapter - returning empty (incompatible types)")
	return make(map[string]*SymbolEngine)
}

// GetOrderRouting returns order routing information
func (d *DexAdapter) GetOrderRouting() []*OrderRoute {
	// V2 handles routing internally through dispatcher
	// Return empty as v1 OrderRoute structure is not applicable
	return []*OrderRoute{}
}

// AggregateL2DepthUpdate aggregates depth updates from all engines
// Returns only the changes (diff) since last call for each symbol
func (d *DexAdapter) AggregateL2DepthUpdate(time int64, blockNum string, prefetch bool) []*DepthUpdate {
	if prefetch {
		return nil
	}

	if d.dispatcher == nil {
		return []*DepthUpdate{}
	}

	// Get symbols from dispatcher
	symbols := d.GetSymbols()
	depthUpdates := make([]*DepthUpdate, 0)

	for _, symbol := range symbols {
		// Get the Level2 diff from each engine
		engineInterface := d.dispatcher.GetEngine(v2types.Symbol(symbol))
		if engineInterface == nil {
			continue
		}

		// Type assert to v2engine.SymbolEngine
		engine, ok := engineInterface.(*v2engine.SymbolEngine)
		if !ok {
			log.Warn("Failed to cast engine to v2engine.SymbolEngine", "symbol", symbol)
			continue
		}

		// Get the diff (changes since last call)
		bidDiff, askDiff := engine.UpdateLevel2()
		if len(bidDiff) == 0 && len(askDiff) == 0 {
			continue
		}

		// Create depth update with only the changes
		depthUpdate := &DepthUpdate{
			Stream: symbol + "@depth",
			Data: &DeltaData{
				EventType: "depthUpdate",
				EventTime: time,
				Symbol:    symbol,
				FirstID:   blockNum,
				FinalID:   blockNum,
				Bids:      bidDiff,
				Asks:      askDiff,
			},
		}

		depthUpdates = append(depthUpdates, depthUpdate)
	}

	return depthUpdates
}

// DispatchReq dispatches a request to the appropriate engine
func (d *DexAdapter) DispatchReq(req Request) {
}

func (d *DexAdapter) DispatchReqV2(req interfaces.Request) {
	d.dispatcher.DispatchReq(req)
}

// GetOrder retrieves an order by ID
func (d *DexAdapter) GetOrder(orderId string) (*Order, bool) {
	// Check for nil dispatcher
	if d.dispatcher == nil {
		log.Error("DexAdapter dispatcher is nil")
		return nil, false
	}

	// Get the v2 order from dispatcher's cache
	v2Order := d.dispatcher.GetCachedOrder(orderId)
	if v2Order == nil {
		log.Debug("Order not found in cache", "orderId", orderId)
		return nil, false
	}

	// Ensure price and quantity are not nil
	if v2Order.Price == nil || v2Order.Quantity == nil {
		log.Error("Order has nil price or quantity", "orderId", orderId)
		return nil, false
	}

	// Convert v2 order to v1 Order format for compatibility
	// v2 properly tracks both OrigQty and current Quantity
	// Use OrigQty if available, otherwise use current Quantity
	origQty := v2Order.Quantity
	if v2Order.OrigQty != nil {
		origQty = v2Order.OrigQty
	}

	v1Order := &Order{
		OrderID:   string(v2Order.OrderID),
		UserID:    string(v2Order.UserID),
		Symbol:    string(v2Order.Symbol),
		Side:      Side(v2Order.Side),
		Price:     uint256.MustFromBig(v2Order.Price.ToBig()),
		Quantity:  uint256.MustFromBig(v2Order.Quantity.ToBig()),
		OrigQty:   uint256.MustFromBig(origQty.ToBig()),
		OrderType: OrderType(v2Order.OrderType),
		Timestamp: v2Order.Timestamp,
	}

	log.Debug("Order found and converted", "orderId", orderId, "symbol", v1Order.Symbol)
	return v1Order, true
}

// GetStopOrder retrieves a stop order by ID
func (d *DexAdapter) GetStopOrder(orderId string) (*StopOrder, bool) {
	// Check for nil dispatcher
	if d.dispatcher == nil {
		log.Error("DexAdapter dispatcher is nil")
		return nil, false
	}

	// Get the order from cache (stop orders are now cached in dispatcher)
	v2Order := d.dispatcher.GetCachedOrder(orderId)
	if v2Order == nil {
		log.Debug("Stop order not found in cache", "orderId", orderId)
		return nil, false
	}

	// Check if this is a stop order type
	if v2Order.OrderType != v2types.STOP_LIMIT && v2Order.OrderType != v2types.STOP_MARKET {
		log.Debug("Order found but not a stop order", "orderId", orderId, "type", v2Order.OrderType)
		return nil, false
	}

	// Convert to v1 StopOrder format for compatibility
	// Note: StopPrice and TriggerAbove are not stored in the regular order struct
	// They would need to be retrieved from the conditional manager if needed
	// For existence check (cancel validation), this simplified version is sufficient
	v1StopOrder := &StopOrder{
		Order: &Order{
			OrderID:   string(v2Order.OrderID),
			UserID:    string(v2Order.UserID),
			Symbol:    string(v2Order.Symbol),
			Side:      Side(v2Order.Side),
			Price:     v2Order.Price,
			Quantity:  v2Order.Quantity,
			OrigQty:   v2Order.Quantity,
			OrderType: OrderType(v2Order.OrderType),
			Timestamp: v2Order.Timestamp,
		},
		// These fields are not available in the cached order
		// Would need to be stored separately or retrieved from conditional manager
		StopPrice:    nil,
		TriggerAbove: false,
	}

	log.Debug("Stop order found", "orderId", orderId, "symbol", v1StopOrder.Order.Symbol)
	return v1StopOrder, true
}

// MakeSnapshot creates a snapshot at the given block number
func (d *DexAdapter) MakeSnapshot(blockNumber uint64, prefetch bool) {
	if prefetch {
		return
	}

	// Note: Persistence is now handled at the system level via OnBlockEnd
	// This method is kept for v1 compatibility but persistence happens
	// through OrderbookSystem.OnBlockEnd() which should be called
	// at block boundaries by the blockchain

	// Persistence disabled - to be redesigned later
}

// GetSnapshot returns the current orderbook snapshot (Level2)
func (d *DexAdapter) GetSnapshot() []*Aggregated {
	if d.dispatcher == nil {
		return []*Aggregated{}
	}

	symbols := d.GetSymbols()
	aggregated := make([]*Aggregated, 0, len(symbols))

	for _, symbol := range symbols {
		// Get the engine for this symbol
		engineInterface := d.dispatcher.GetEngine(v2types.Symbol(symbol))
		if engineInterface == nil {
			continue
		}

		// Type assert to v2engine.SymbolEngine
		engine, ok := engineInterface.(*v2engine.SymbolEngine)
		if !ok {
			log.Warn("Failed to cast engine to v2engine.SymbolEngine", "symbol", symbol)
			continue
		}

		// Get Level2 snapshot from the engine
		v2Snapshot := engine.GetLevel2Snapshot()
		if v2Snapshot == nil {
			continue
		}

		// v2 snapshot already has the data in the correct format
		agg := &Aggregated{
			BlockNumber: v2Snapshot.BlockNumber,
			Symbol:      symbol,
			Bids:        v2Snapshot.Bids,
			Asks:        v2Snapshot.Asks,
		}

		aggregated = append(aggregated, agg)
	}

	return aggregated
}

// GetSnapshotFromLvl3 returns level 2 aggregated snapshot from level 3 orderbook
// This aggregates individual orders (Level3) to price levels (Level2)
func (d *DexAdapter) GetSnapshotFromLvl3() []*Aggregated {

	return nil
}

// GetMarketRules returns market rules for a symbol
func (d *DexAdapter) GetMarketRules(symbol string) *MarketRules {
	// V2 uses types.MarketRules internally
	// Return default v1 market rules
	return NewMarketRules()
}

// GetBestPrice returns the best price for a given side
func (d *DexAdapter) GetBestPrice(symbol string, side Side) *uint256.Int {
	if d.dispatcher == nil {
		return nil
	}

	// Get orderbook snapshot with depth 1 (top of book)
	v2Snapshot := d.dispatcher.GetOrderbookSnapshot(v2types.Symbol(symbol), 1)
	if v2Snapshot == nil {
		return nil
	}

	switch side {
	case BUY:
		// Best buy price is the highest bid
		if len(v2Snapshot.Bids) > 0 {
			return v2Snapshot.Bids[0].Price
		}
	case SELL:
		// Best sell price is the lowest ask
		if len(v2Snapshot.Asks) > 0 {
			return v2Snapshot.Asks[0].Price
		}
	}

	return nil
}

// convertRequest converts a v1 request to v2 format
func (d *DexAdapter) convertRequest(v1Req Request) *v2types.Request {
	// Extract StateDB and FeeGetter from v1 request (available in all request types via baseRequest)
	v1StateDB := v1Req.StateDB()
	v1FeeGetter := v1Req.FeeGetter()

	// Create StateDB adapter (v1 Locker implements v2 StateDB interface)
	var stateDBAdapter v2types.StateDB
	if v1StateDB != nil {
		stateDBAdapter = &StateDBAdapter{locker: v1StateDB}
	}

	// Create FeeRetriever adapter (v1 and v2 have same interface)
	var feeRetrieverAdapter v2types.FeeRetriever
	if v1FeeGetter != nil {
		feeRetrieverAdapter = &FeeRetrieverAdapter{v1FeeGetter: v1FeeGetter}
	}

	// Base v2 request with StateDB and FeeRetriever
	v2Req := &v2types.Request{
		StateDB:      stateDBAdapter,
		FeeRetriever: feeRetrieverAdapter,
	}

	switch req := v1Req.(type) {
	case *OrderRequest:
		if req.Order == nil {
			return nil
		}

		// Convert v1 Order to v2 Order
		v2Order := &v2types.Order{
			OrderID:   v2types.OrderID(req.Order.OrderID),
			UserID:    v2types.UserID(req.Order.UserID),
			Symbol:    v2types.Symbol(req.Order.Symbol),
			Side:      convertSide(req.Order.Side),
			OrderType: convertOrderType(req.Order.OrderType),
			Price:     req.Order.Price,
			Quantity:  req.Order.Quantity,
			Status:    v2types.NEW,
		}

		v2Req.Type = v2types.PlaceOrder
		v2Req.Order = v2Order
		return v2Req

	case *CancelRequest:
		v2Req.Type = v2types.CancelOrder
		v2Req.OrderID = req.OrderID
		return v2Req

	case *CancelAllRequest:
		v2Req.Type = v2types.CancelAllOrders
		v2Req.UserID = req.UserID
		return v2Req

	case *StopOrderRequest:
		if req.StopOrder == nil || req.StopOrder.Order == nil {
			return nil
		}

		// Convert v1 StopOrder to v2 StopOrder
		// V1 stop order type is determined by whether the order has a price (limit) or not (market)
		var orderType v2types.OrderType
		if req.StopOrder.Order.Price != nil && !req.StopOrder.Order.Price.IsZero() {
			orderType = v2types.STOP_LIMIT
		} else {
			orderType = v2types.STOP_MARKET
		}

		v2StopOrder := &v2types.StopOrder{
			Order: &v2types.Order{
				OrderID:   v2types.OrderID(req.StopOrder.Order.OrderID),
				UserID:    v2types.UserID(req.StopOrder.Order.UserID),
				Symbol:    v2types.Symbol(req.StopOrder.Order.Symbol),
				Side:      convertSide(req.StopOrder.Order.Side),
				OrderType: orderType,
				Price:     req.StopOrder.Order.Price,
				Quantity:  req.StopOrder.Order.Quantity,
				Status:    v2types.TRIGGER_WAIT,
			},
			StopPrice:    req.StopOrder.StopPrice,
			TriggerAbove: req.StopOrder.TriggerAbove,
		}

		v2Req.Type = v2types.PlaceStopOrder
		v2Req.StopOrder = v2StopOrder
		return v2Req

	case *ModifyRequest:
		if req.Args == nil {
			return nil
		}
		v2Req.Type = v2types.ModifyOrder
		v2Req.OldOrderID = req.Args.OrderId
		v2Req.Order = &v2types.Order{
			Price:    req.Args.NewPrice,
			Quantity: req.Args.NewQty,
		}
		return v2Req

	default:
		log.Warn("Unsupported request type for v2 conversion", "type", fmt.Sprintf("%T", req))
		return nil
	}
}

// convertResponse converts a v2 response to v1 format
func (d *DexAdapter) convertResponse(v2Resp *v2types.OrderbookResponse, err error) Response {
	if err != nil {
		return NewErrorResponse(err)
	}

	if v2Resp == nil {
		return NewErrorResponse(fmt.Errorf("nil response from v2"))
	}

	if !v2Resp.Success {
		return NewErrorResponse(fmt.Errorf(v2Resp.Error))
	}

	// Convert trades
	var v1Trades []*Trade
	if v2Resp.Trades != nil {
		for _, v2Trade := range v2Resp.Trades {
			// Determine maker and taker IDs
			var makerID, takerID string
			if v2Trade.IsBuyerMaker {
				makerID = string(v2Trade.BuyOrderID)
				takerID = string(v2Trade.SellOrderID)
			} else {
				makerID = string(v2Trade.SellOrderID)
				takerID = string(v2Trade.BuyOrderID)
			}

			v1Trade := &Trade{
				Symbol:          string(v2Trade.Symbol),
				BuyOrderID:      string(v2Trade.BuyOrderID),
				SellOrderID:     string(v2Trade.SellOrderID),
				BuyOrderFilled:  v2Trade.BuyOrderFullyFilled,
				SellOrderFilled: v2Trade.SellOrderFullyFilled,
				MakerID:         makerID,
				TakerID:         takerID,
				Price:           v2Trade.Price,
				Quantity:        v2Trade.Quantity,
				Timestamp:       uint64(v2Trade.Timestamp),
				IsBuyerMaker:    v2Trade.IsBuyerMaker,
			}
			v1Trades = append(v1Trades, v1Trade)
		}
	}

	// Return response with converted data
	// V1 OrderResponse uses baseResponse which has events and err fields
	resp := &OrderResponse{
		Trades:            v1Trades,
		TriggeredOrderIDs: OrderIds{}, // V2 doesn't have triggered orders in response yet
	}

	// Set error if the response wasn't successful
	if !v2Resp.Success {
		resp.err = fmt.Errorf(v2Resp.Error)
	}

	return resp
}

// Helper functions for type conversion

func convertSide(v1Side Side) v2types.OrderSide {
	switch v1Side {
	case BUY:
		return v2types.BUY
	case SELL:
		return v2types.SELL
	default:
		return v2types.BUY
	}
}

func convertOrderType(v1Type OrderType) v2types.OrderType {
	switch v1Type {
	case MARKET:
		return v2types.MARKET
	case LIMIT:
		return v2types.LIMIT
	default:
		return v2types.LIMIT
	}
}

// convertV2SideToV1 converts v2 side to v1 side
func convertV2SideToV1(v2Side v2types.OrderSide) Side {
	switch v2Side {
	case v2types.BUY:
		return BUY
	case v2types.SELL:
		return SELL
	default:
		return BUY
	}
}

// convertV2OrderToV1 converts a v2 order to v1 format
func convertV2OrderToV1(v2Order *v2types.Order) *Order {
	if v2Order == nil {
		return nil
	}

	// V1 doesn't have Status field, it uses IsCanceled bool
	isCanceled := v2Order.Status == v2types.CANCELLED

	return &Order{
		OrderID:    string(v2Order.OrderID),
		UserID:     string(v2Order.UserID),
		Symbol:     string(v2Order.Symbol),
		Side:       convertV2SideToV1(v2Order.Side),
		OrderType:  convertV2OrderTypeToV1(v2Order.OrderType),
		Price:      v2Order.Price,
		OrigQty:    v2Order.OrigQty,  // V2 has OrigQty field
		Quantity:   v2Order.Quantity, // V2 Quantity is the remaining quantity
		IsCanceled: isCanceled,
		Timestamp:  v2Order.Timestamp,
	}
}

// convertV2OrderTypeToV1 converts v2 order type to v1
func convertV2OrderTypeToV1(v2Type v2types.OrderType) OrderType {
	switch v2Type {
	case v2types.MARKET:
		return MARKET
	case v2types.LIMIT:
		return LIMIT
	default:
		return LIMIT
	}
}

// StateDBAdapter adapts v1 Locker to v2 StateDB interface
type StateDBAdapter struct {
	locker Locker
}

func (s *StateDBAdapter) GetTokenBalance(addr common.Address, token string) *uint256.Int {
	return s.locker.GetTokenBalance(addr, token)
}

func (s *StateDBAdapter) GetLockedTokenBalance(addr common.Address, token string) *uint256.Int {
	return s.locker.GetLockedTokenBalance(addr, token)
}

func (s *StateDBAdapter) LockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	s.locker.LockTokenBalance(addr, token, amount)
}

func (s *StateDBAdapter) UnlockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	s.locker.UnlockTokenBalance(addr, token, amount)
}

func (s *StateDBAdapter) ConsumeLockTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	s.locker.ConsumeLockTokenBalance(addr, token, amount)
}

func (s *StateDBAdapter) AddTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	s.locker.AddTokenBalance(addr, token, amount)
}

func (s *StateDBAdapter) SubTokenBalance(addr common.Address, token string, amount *uint256.Int) {
	// v2 StateDB has SubTokenBalance, but v1 Locker doesn't have it directly
	// We can implement it using ConsumeLockTokenBalance or leave unimplemented
	// For now, we'll use ConsumeLockTokenBalance as it serves similar purpose
	s.locker.ConsumeLockTokenBalance(addr, token, amount)
}

// FeeRetrieverAdapter adapts v1 FeeRetriever to v2 FeeRetriever interface
type FeeRetrieverAdapter struct {
	v1FeeGetter FeeRetriever
}

func (f *FeeRetrieverAdapter) GetMarketFees(base, quote uint64) (*big.Int, *big.Int, error) {
	return f.v1FeeGetter.GetMarketFees(base, quote)
}

// SetCurrentBlock sets the current block context for persistence
func (d *DexAdapter) SetCurrentBlock(blockNum uint64) {
	// Forward to v2 dispatcher
	d.dispatcher.SetCurrentBlock(blockNum)
}

// OnBlockEnd is called at the end of block processing for persistence tasks
func (d *DexAdapter) OnBlockEnd(blockNum uint64) {
	// Forward to v2 dispatcher
	d.dispatcher.OnBlockEnd(blockNum)
}

func (d *DexAdapter) WriteSnapshot(blockNum uint64) {
	// Forward to v2 dispatcher
	d.dispatcher.WriteSnapshot(blockNum)
}
