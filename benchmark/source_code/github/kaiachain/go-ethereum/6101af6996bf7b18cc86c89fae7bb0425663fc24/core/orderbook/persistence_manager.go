package orderbook

import (
	"container/heap"
	"fmt"
	"path"
	"sync"
	
	"github.com/ethereum/go-ethereum/log"
)

// PersistenceManager coordinates WAL logging and snapshots
type PersistenceManager struct {
	eventLogger     *EventWALLogger
	snapshotManager *PersistenceSnapshotManager

	currentBlock    uint64
	lastRecoveredBlock uint64 // Track the last recovered snapshot block
	enabled         bool
	dataDir         string

	mu sync.Mutex
}

// NewPersistenceManager creates a new persistence manager
func NewPersistenceManager(dataDir string, snapshotInterval uint64) (*PersistenceManager, error) {
	// Initialize event-based WAL logger
	eventLogger, err := NewEventWALLogger(path.Join(dataDir, "events"))
	if err != nil {
		return nil, fmt.Errorf("failed to create event WAL logger: %w", err)
	}
	
	// Initialize snapshot manager
	snapshotManager, err := NewPersistenceSnapshotManager(path.Join(dataDir, "snapshots"), snapshotInterval)
	if err != nil {
		eventLogger.Close()
		return nil, fmt.Errorf("failed to create snapshot manager: %w", err)
	}
	
	pm := &PersistenceManager{
		eventLogger:     eventLogger,
		snapshotManager: snapshotManager,
		enabled:         true,
		dataDir:         dataDir,
	}
	
	log.Info("Persistence manager initialized", 
		"dataDir", dataDir,
		"snapshotInterval", snapshotInterval)
	
	return pm, nil
}

// SetBlock sets the current block number for WAL logging
func (pm *PersistenceManager) SetBlock(blockNum uint64) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	
	if blockNum != pm.currentBlock {
		pm.currentBlock = blockNum
		
		// Update event logger's block context
		pm.eventLogger.SetBlockContext(blockNum)
		
		log.Debug("Persistence manager block updated", "block", blockNum)
	}
}

// LogRequestResponse logs events from response to WAL
func (pm *PersistenceManager) LogRequestResponse(resp Response) {
	if !pm.enabled || resp == nil {
		return
	}
	
	// Log events if present in response
	events := resp.Events()
	if len(events) > 0 {
		pm.eventLogger.LogEvents(events)
		log.Debug("Logged events", "count", len(events), "block", pm.currentBlock)
	}
}

// OnBlockEnd handles end-of-block tasks like snapshots and event flushing
func (pm *PersistenceManager) OnBlockEnd(blockNum uint64, dispatcher *Dispatcher) {
	if !pm.enabled {
		return
	}
	
	// Flush events for this block
	if err := pm.eventLogger.OnBlockEnd(blockNum); err != nil {
		log.Error("Failed to flush events at block end", "block", blockNum, "error", err)
	}
	
	// Check if snapshot is needed
	if blockNum > 0 && blockNum % pm.snapshotManager.snapshotInterval == 0 {
		log.Info("Requesting snapshot", "block", blockNum)
		pm.snapshotManager.RequestSnapshot(blockNum, dispatcher)
	}
}

// Close shuts down the persistence manager
func (pm *PersistenceManager) Close() error {
	pm.enabled = false
	
	log.Info("Closing persistence manager")
	
	var firstErr error
	
	// Close event logger (will flush all pending events)
	if err := pm.eventLogger.Close(); err != nil {
		log.Error("Failed to close event logger", "error", err)
		if firstErr == nil {
			firstErr = err
		}
	}
	
	// Close snapshot manager
	if err := pm.snapshotManager.Close(); err != nil {
		log.Error("Failed to close snapshot manager", "error", err)
		if firstErr == nil {
			firstErr = err
		}
	}
	
	return firstErr
}

// IsEnabled returns whether persistence is enabled
func (pm *PersistenceManager) IsEnabled() bool {
	return pm.enabled
}

// GetLastRecoveredBlock returns the last recovered snapshot block number
// Returns 0 if no snapshot was recovered
func (pm *PersistenceManager) GetLastRecoveredBlock() uint64 {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	return pm.lastRecoveredBlock
}

// Recover recovers the dispatcher state from snapshots and events
func (pm *PersistenceManager) Recover(d *Dispatcher) error {
	if !pm.enabled {
		return fmt.Errorf("persistence is not enabled")
	}

	log.Info("Starting recovery from persistence", "dataDir", pm.dataDir)

	// First, try to load from snapshot
	snapshot, err := pm.snapshotManager.LoadLatestSnapshot()
	snapshotBlock := uint64(0)
	if err != nil {
		log.Warn("Failed to load snapshot, will recover from events only", "error", err)
	} else if snapshot != nil {
		snapshotBlock = snapshot.BlockNumber
		log.Info("Loaded snapshot", "block", snapshotBlock)
		// Apply snapshot to dispatcher
		if err := pm.applySnapshot(d, snapshot); err != nil {
			log.Error("Failed to apply snapshot", "error", err)
			return err
		}
		// Track the recovered snapshot block
		pm.lastRecoveredBlock = snapshotBlock
	}

	// Then, recover from events after snapshot
	recovery := NewEventRecovery(path.Join(pm.dataDir, "events"))
	if err := recovery.RecoverFromEvents(d, snapshotBlock+1); err != nil {
		log.Error("Failed to recover from events", "error", err)
		return err
	}

	// Start engine goroutines after full recovery
	d.mu.RLock()
	for symbol, engine := range d.engines {
		log.Debug("Starting engine goroutine after recovery", "symbol", symbol)
		go engine.run()
	}
	d.mu.RUnlock()

	log.Info("Recovery completed successfully")
	return nil
}

// applySnapshot applies a snapshot to the dispatcher
func (pm *PersistenceManager) applySnapshot(d *Dispatcher, snapshot *OrderbookSnapshot) error {
	// Restore each symbol engine from snapshot
	for symbol, symbolSnapshot := range snapshot.Symbols {
		// Rebuild userbook from orders
		userBook := NewUserBook()
		for _, order := range symbolSnapshot.BuyOrders {
			userBook.AddOrder(order)
		}
		for _, order := range symbolSnapshot.SellOrders {
			userBook.AddOrder(order)
		}
		
		// Convert orders to queues
		buyQueue := make(BuyQueue, len(symbolSnapshot.BuyOrders))
		copy(buyQueue, symbolSnapshot.BuyOrders)
		heap.Init(&buyQueue)
		
		sellQueue := make(SellQueue, len(symbolSnapshot.SellOrders))
		copy(sellQueue, symbolSnapshot.SellOrders)
		heap.Init(&sellQueue)
		
		// Create conditional order manager and populate it with legacy orders
		conditionalManager := NewConditionalOrderManager()
		conditionalManager.legacyOrders = symbolSnapshot.TPSLOrders
		
		// Rebuild the queue from legacy orders
		for _, tpsl := range symbolSnapshot.TPSLOrders {
			if tpsl.TPOrder != nil && tpsl.SLOrder != nil {
				// TPSL order
				entry := ConditionalOrderEntry{
					OrderID:   tpsl.TPOrder.Order.OrderID,
					OrderType: ConditionalTPSL,
					Data:      tpsl,
					Timestamp: tpsl.TPOrder.Order.Timestamp,
					Sequence:  conditionalManager.nextSequence,
				}
				conditionalManager.nextSequence++
				conditionalManager.queue = append(conditionalManager.queue, entry)
			} else if tpsl.TPOrder != nil || tpsl.SLOrder != nil {
				// Stop order
				var orderID string
				var timestamp int64
				if tpsl.TPOrder != nil {
					orderID = tpsl.TPOrder.Order.OrderID
					timestamp = tpsl.TPOrder.Order.Timestamp
				} else {
					orderID = tpsl.SLOrder.Order.OrderID
					timestamp = tpsl.SLOrder.Order.Timestamp
				}
				entry := ConditionalOrderEntry{
					OrderID:   orderID,
					OrderType: ConditionalStop,
					Data:      tpsl,
					Timestamp: timestamp,
					Sequence:  conditionalManager.nextSequence,
				}
				conditionalManager.nextSequence++
				conditionalManager.queue = append(conditionalManager.queue, entry)
			}
		}
		
		// Create engine
		engine := &SymbolEngine{
			symbol:                  symbol,
			buyQueue:                buyQueue,
			sellQueue:               sellQueue,
			userBook:                userBook,
			conditionalOrderManager: conditionalManager,
			snapshotManager:         NewSnapshotManager(symbol),
			marketRules:             NewMarketRules(),
			tradeMatcher:            NewTradeMatcher(symbol),
			triggered:               make([]*TriggeredOrder, 0),
			currentPrice:            symbolSnapshot.LastPrice,
			level2Book:              NewLevel2Book(),
			buyDirty:                make(map[string]struct{}),
			sellDirty:               make(map[string]struct{}),
			queue:                   make(chan Request, OrderQueueSize),
			quit:                    make(chan struct{}),
		}
		
		// Rebuild Level2 book
		engine.level2Book = engine.BuildLevel2BookFromQueues()
		
		d.mu.Lock()
		d.symbols[symbol] = struct{}{}
		d.engines[symbol] = engine
		d.mu.Unlock()
		
		// DO NOT start engine goroutine here - will be started after full recovery
		// go engine.run()
	}
	
	// Restore order routing
	d.mu.Lock()
	d.orderRouting = snapshot.OrderRouting
	d.mu.Unlock()

	return nil
}