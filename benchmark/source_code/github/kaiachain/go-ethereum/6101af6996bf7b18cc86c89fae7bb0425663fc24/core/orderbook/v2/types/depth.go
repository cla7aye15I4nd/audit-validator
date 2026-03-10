package types

// Aggregated represents a full orderbook snapshot at a specific block
type Aggregated struct {
	BlockNumber uint64     `json:"block"`
	Symbol      string     `json:"symbol"`
	Bids        [][]string `json:"bids"` // [[price, quantity], ...]
	Asks        [][]string `json:"asks"`
}

// DepthUpdate represents incremental depth changes for a symbol
type DepthUpdate struct {
	Stream string     `json:"stream"` // Stream name (e.g., "KAIA/USDT@depth")
	Data   *DeltaData `json:"data"`
}

// DeltaData contains the depth update details
type DeltaData struct {
	EventType string     `json:"e"` // Event type
	EventTime int64      `json:"E"` // Event time
	Symbol    string     `json:"s"` // Symbol (e.g., "KAIA/USDT")
	FirstID   string     `json:"U"` // First update ID in event (block number)
	FinalID   string     `json:"u"` // Final update ID in event (block number)
	Bids      [][]string `json:"b"` // Bids (price and quantity)
	Asks      [][]string `json:"a"` // Asks (price and quantity)
}