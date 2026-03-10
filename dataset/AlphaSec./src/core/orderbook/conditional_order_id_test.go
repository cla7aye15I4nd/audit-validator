package orderbook

import (
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/stretchr/testify/assert"
)

func TestConditionalOrderIDGeneration(t *testing.T) {
	tests := []struct {
		name          string
		txHashHex     string
		increment     byte
		expectedIDHex string
	}{
		{
			name:          "TP order ID generation",
			txHashHex:     "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd00",
			increment:     TPIncrement,
			expectedIDHex: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd01",
		},
		{
			name:          "SL order ID generation",
			txHashHex:     "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd00",
			increment:     SLIncrement,
			expectedIDHex: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd02",
		},
		{
			name:          "Overflow case - TP",
			txHashHex:     "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdff",
			increment:     TPIncrement,
			expectedIDHex: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd00",
		},
		{
			name:          "Overflow case - SL",
			txHashHex:     "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdfe",
			increment:     SLIncrement,
			expectedIDHex: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd00",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			txHash := common.HexToHash(tt.txHashHex)
			result := GenerateConditionalOrderID(txHash, tt.increment)
			assert.Equal(t, tt.expectedIDHex, result, "Generated ID should match expected")
		})
	}
}

func TestConditionalOrderIDUniqueness(t *testing.T) {
	// Test that different increments produce different IDs
	txHash := common.HexToHash("0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd00")
	
	originalID := txHash.Hex()
	tpID := GenerateConditionalOrderID(txHash, TPIncrement)
	slID := GenerateConditionalOrderID(txHash, SLIncrement)
	
	// All IDs should be different
	assert.NotEqual(t, originalID, tpID, "TP ID should differ from original")
	assert.NotEqual(t, originalID, slID, "SL ID should differ from original")
	assert.NotEqual(t, tpID, slID, "TP ID should differ from SL ID")
}

func TestDispatcherRouting(t *testing.T) {
	dispatcher := NewDispatcher()
	
	// Create a symbol engine manually
	symbol := "BTCUSDT"
	dispatcher.mu.Lock()
	dispatcher.symbols[symbol] = struct{}{}
	dispatcher.engines[symbol] = NewSymbolEngine(symbol)
	dispatcher.mu.Unlock()
	
	// Test original order routing
	originalHash := common.HexToHash("0xabc0000000000000000000000000000000000000000000000000000000000010")
	originalID := originalHash.Hex()
	
	// Simulate registering a TPSL order
	tpID := GenerateConditionalOrderID(originalHash, TPIncrement)
	slID := GenerateConditionalOrderID(originalHash, SLIncrement)
	
	// Register routing for all IDs
	dispatcher.mu.Lock()
	dispatcher.orderRouting[originalID] = OrderRoutingInfo{
		Symbol: symbol,
	}
	dispatcher.orderRouting[tpID] = OrderRoutingInfo{
		Symbol: symbol,
	}
	dispatcher.orderRouting[slID] = OrderRoutingInfo{
		Symbol: symbol,
	}
	dispatcher.mu.Unlock()
	
	// Verify routing lookup
	routes := dispatcher.GetOrderRouting()
	
	// Find routes and verify
	var foundOriginal, foundTP, foundSL bool
	for _, route := range routes {
		if route.OrderId == originalID {
			foundOriginal = true
			assert.Equal(t, symbol, route.Symbol)
		}
		if route.OrderId == tpID {
			foundTP = true
			assert.Equal(t, symbol, route.Symbol)
		}
		if route.OrderId == slID {
			foundSL = true
			assert.Equal(t, symbol, route.Symbol)
		}
	}
	
	assert.True(t, foundOriginal, "Original order should be in routing")
	assert.True(t, foundTP, "TP order should be in routing")
	assert.True(t, foundSL, "SL order should be in routing")
}