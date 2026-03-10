package interfaces

import (
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
)

// Dispatcher defines the interface for request dispatching
type Dispatcher interface {
	// DispatchReq dispatches a request asynchronously
	DispatchReq(req Request)
	
	// ProcessRequestSync processes a request synchronously (for recovery)
	ProcessRequestSync(req Request) Response
	
	// GetEngine returns the engine for a symbol (returns interface{} to avoid circular dependency)
	GetEngine(symbol types.Symbol) interface{}
	
	// GetEngines returns all engines (returns interface{} to avoid circular dependency)
	GetEngines() interface{}
	
	// GetSnapshotData returns the complete dispatcher state for persistence
	GetSnapshotData(blockNumber uint64) *types.DispatcherSnapshotData
	
	// RestoreFromSnapshot restores the dispatcher state from a snapshot
	RestoreFromSnapshot(snapshot *types.DispatcherSnapshotData) error
	
	// Start starts the dispatcher
	Start()
	
	// Stop stops the dispatcher
	Stop() error
}