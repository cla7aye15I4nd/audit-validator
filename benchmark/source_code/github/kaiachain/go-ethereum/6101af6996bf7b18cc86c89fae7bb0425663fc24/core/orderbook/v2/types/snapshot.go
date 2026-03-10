package types

import "github.com/holiman/uint256"

// ConditionalTrigger represents a serializable trigger for snapshots
type ConditionalTrigger struct {
	OrderID      OrderID      `json:"order_id"`
	UserID       UserID       `json:"user_id"`
	Order        *Order       `json:"order"`
	TriggerType  string       `json:"trigger_type"` // "stop_loss" or "stop_order"
	StopPrice    *uint256.Int `json:"stop_price"`
	TriggerPrice *uint256.Int `json:"trigger_price"` // Alias for StopPrice
	TriggerAbove bool         `json:"trigger_above"`
}

// OCOPairSnapshot represents a serializable OCO pair for snapshots
type OCOPairSnapshot struct {
	ID        string    `json:"id"`
	PairID    string    `json:"pair_id"` // Alias for ID
	OrderIDs  []OrderID `json:"order_ids"`
	Strategy  string    `json:"strategy"` // OCO strategy type
	CreatedAt int64     `json:"created_at"`
}

// EngineSnapshotData represents minimal engine state for persistence
type EngineSnapshotData struct {
	Symbol        Symbol              `json:"symbol"`
	Orders        []*Order            `json:"orders"`
	CurrentPrice  *Price              `json:"current_price"`
	LastTradeTime int64               `json:"last_trade_time"`
	Triggers      []ConditionalTrigger `json:"triggers,omitempty"`
	TriggerQueue  []OrderID           `json:"trigger_queue,omitempty"`
	OCOPairs      []OCOPairSnapshot   `json:"oco_pairs,omitempty"`
	BlockNumber   uint64              `json:"block_number"`
}

// DispatcherSnapshotData represents the dispatcher state for persistence
type DispatcherSnapshotData struct {
	// Balance Manager state
	Locks     map[string]*LockInfo `json:"locks"`      // All active locks
	LockAlias map[string]string    `json:"lock_alias"` // Alias mappings for TP/SL orders
	
	// Routing and cache
	SymbolRouting map[string]Symbol  `json:"symbol_routing"` // OrderID -> Symbol mapping
	OrderCache    map[string]*Order  `json:"order_cache"`    // Cached orders
	
	// Engine snapshots
	Engines map[Symbol]*EngineSnapshotData `json:"engines"`
	
	// Block context
	BlockNumber uint64 `json:"block_number"`
}