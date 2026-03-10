package rpc

import (
	"context"
	"encoding/json"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"testing"
)

type ChainEvent struct {
	Block *types.Block
	Hash  common.Hash
	Logs  []*types.Log
}

type DepthUpdate struct {
	Stream string `json:"stream"` // Stream name (e.g., "bandusdt@depth")
	Data   struct {
		EventType string     `json:"e"` // Event type
		EventTime int64      `json:"E"` // Event time
		Symbol    string     `json:"s"` // Symbol (e.g., "KAIA/USDT")
		FirstID   string     `json:"U"` // First update ID in event
		FinalID   string     `json:"u"` // Final update ID in event
		Bids      [][]string `json:"b"` // Bids (price and quantity)
		Asks      [][]string `json:"a"` // Asks (price and quantity)
	} `json:"data"`
}

type JsonBlock struct {
	Header       *types.Header        `json:"header"`
	Transactions []*types.Transaction `json:"transactions"`
	Logs         []*types.Log         `json:"logs"`
}

func TestClientTradeDataSubscription(t *testing.T) {
	// Connect the client.
	client, _ := Dial("ws://52.79.238.133:8548")
	blockCh := make(chan *JsonBlock)
	depthCh := make(chan []byte)
	headsCh := make(chan *types.Header)

	t.Log("Connected to the server")

	client.EthSubscribe(context.Background(), blockCh, "newBlocks")
	client.EthSubscribe(context.Background(), headsCh, "newHeads")
	client.EthSubscribe(context.Background(), depthCh, "dexTrades")

	for {
		select {
		case ret := <-blockCh:
			t.Log("Got newBlocks: ", ret)
		case ret := <-headsCh:
			t.Log("Got newHeads: ", ret)
		case ret := <-depthCh:
			depth := []*DepthUpdate{}
			if err := json.Unmarshal(ret, depth); err != nil {
				t.Log("failed to decode depth update: ", err)
			}
			t.Log("Got a new depth update: ", depth)
		}
	}
	defer client.Close()
}

// subscribeBlocks runs
