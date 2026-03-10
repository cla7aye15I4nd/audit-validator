package conditional

import (
	"fmt"
	"sync"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/metrics"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/tpsl"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// Manager is the conditional order manager using clean TPSL pattern
type Manager struct {
	mu sync.RWMutex

	// Core modules - simplified to 3 modules (removed ExecutionContext)
	triggerManager tpsl.TriggerManager
	activationRule tpsl.ActivationRule
	ocoController  tpsl.OCOController

	// Callbacks for order operations
	orderProcessor func(*types.Order) error  // Add to orderbook
	orderCanceller func(types.OrderID) error // Cancel from orderbook
}

// NewManager creates a new conditional order manager with clean architecture
func NewManager() *Manager {
	return &Manager{
		triggerManager: tpsl.NewTriggerManager(),
		activationRule: tpsl.NewActivationRule(),
		ocoController:  tpsl.NewOCOController(),
	}
}

// SetOrderProcessor sets the callback for processing orders that need immediate execution
func (m *Manager) SetOrderProcessor(processor func(*types.Order) error) {
	m.orderProcessor = processor
}

// SetOrderCanceller sets the callback for cancelling orders in the orderbook
func (m *Manager) SetOrderCanceller(canceller func(types.OrderID) error) {
	m.orderCanceller = canceller
}

// AddStopOrder adds a standalone stop order
func (m *Manager) AddStopOrder(stopOrder *types.StopOrder) error {
	if stopOrder == nil || stopOrder.Order == nil {
		return types.ErrInvalidOrder
	}

	// Create a stop order trigger
	trigger := tpsl.NewStopOrderTrigger(
		stopOrder.Order,
		stopOrder.StopPrice,
		stopOrder.TriggerAbove,
	)

	// Add to trigger manager
	err := m.triggerManager.AddTrigger(trigger)
	if err == nil {
		metrics.ConditionalOrdersActiveGauge.Inc(1)
	}
	return err
}

// CreateTPSLForFilledOrder creates and activates TPSL for a filled order
func (m *Manager) CreateTPSLForFilledOrder(order *types.Order) error {
	if order == nil {
		return types.ErrInvalidOrder
	}

	// Check if TPSL should be activated
	if !m.activationRule.ShouldActivate(order) {
		return nil // No TPSL to create
	}

	// Activate TPSL
	activation, err := m.activationRule.Activate(order)
	if err != nil {
		return fmt.Errorf("failed to activate TPSL: %w", err)
	}

	// Step 1: Execute TP order immediately (goes to orderbook)
	if activation.TPOrder != nil {
		if m.orderProcessor == nil {
			return fmt.Errorf("order processor not set")
		}
		if err := m.orderProcessor(activation.TPOrder); err != nil {
			return fmt.Errorf("failed to process TP order: %w", err)
		}
	}

	// Step 2: Add SL trigger to trigger manager
	if activation.SLTrigger != nil {
		err = m.triggerManager.AddTrigger(activation.SLTrigger)
		if err != nil {
			// Rollback TP order if SL trigger fails
			if activation.TPOrder != nil && m.orderCanceller != nil {
				if cancelErr := m.orderCanceller(activation.TPOrder.OrderID); cancelErr != nil {
					log.Error("Failed to rollback TP order",
						"tpOrderID", activation.TPOrder.OrderID,
						"error", cancelErr)
				}
			}
			return fmt.Errorf("failed to add SL trigger: %w", err)
		}
	}

	// Step 3: Register OCO relationship
	if activation.OCOPair != nil {
		err = m.ocoController.RegisterPair(activation.OCOPair)
		if err != nil {
			// Rollback both TP and SL if OCO registration fails
			if activation.TPOrder != nil && m.orderCanceller != nil {
				if cancelErr := m.orderCanceller(activation.TPOrder.OrderID); cancelErr != nil {
					log.Error("Failed to rollback TP order",
						"tpOrderID", activation.TPOrder.OrderID,
						"error", cancelErr)
				}
			}
			if activation.SLTrigger != nil {
				m.triggerManager.RemoveTrigger(activation.SLTrigger.GetOrderID())
			}
			return fmt.Errorf("failed to register OCO pair: %w", err)
		}
	}

	var tpOrderID, slOrderID types.OrderID
	if activation.TPOrder != nil {
		tpOrderID = activation.TPOrder.OrderID
	}
	if activation.SLTrigger != nil {
		slOrderID = activation.SLTrigger.GetOrderID()
	}

	log.Debug("TPSL created successfully",
		"originalOrderID", order.OrderID,
		"tpOrderID", tpOrderID,
		"slOrderID", slOrderID)

	// Update TPSL active metrics
	metrics.ConditionalOrdersActiveGauge.Inc(1)

	return nil
}

// CheckTriggers checks all conditional orders and returns triggered orders
func (m *Manager) CheckTriggers(currentPrice *uint256.Int) ([]*types.Order, []types.OrderID) {
	if currentPrice == nil {
		return nil, nil
	}

	log.Debug("Checking conditional triggers", "price", currentPrice)

	// Check triggers
	triggeredOrders := m.triggerManager.CheckTriggers(currentPrice)

	var orders []*types.Order
	var cancelledOrders []types.OrderID

	for _, triggered := range triggeredOrders {
		if triggered.Order != nil {
			orders = append(orders, triggered.Order)
			log.Debug("Conditional order triggered",
				"orderID", triggered.Order.OrderID,
				"type", triggered.TriggerType,
				"triggerPrice", currentPrice)
			metrics.ConditionalOrdersTriggeredCounter.Inc(1)
			metrics.ConditionalOrdersActiveGauge.Dec(1)
		}

		// Handle OCO if this is a SL trigger
		if triggered.TriggerType == tpsl.TriggerTypeStopLoss {
			// Get related orders from OCO controller
			relatedOrders := m.ocoController.ExecuteOCO(triggered.Order.OrderID)

			// Cancel related orders (typically TP order) via callback
			for _, orderID := range relatedOrders {
				if m.orderCanceller != nil {
					if err := m.orderCanceller(orderID); err != nil {
						log.Error("Failed to cancel OCO order",
							"orderID", orderID,
							"error", err)
					} else {
						cancelledOrders = append(cancelledOrders, orderID)
						log.Debug("OCO order cancelled",
							"orderID", orderID,
							"triggeredBy", triggered.Order.OrderID)
					}
				}
			}
		}
	}

	if len(orders) > 0 {
		log.Debug("Conditional orders triggered",
			"count", len(orders),
			"ocoancelledCount", len(cancelledOrders))
	}

	// Return triggered orders and IDs of cancelled orders (for event generation)
	return orders, cancelledOrders
}

// HandleOrderFill handles when an order is filled/triggered for OCO processing
// This is called when a TP order fills or SL order triggers
// Returns order IDs that were cancelled due to OCO
func (m *Manager) HandleOrderFill(orderID types.OrderID) []types.OrderID {
	m.mu.Lock()
	defer m.mu.Unlock()

	var cancelledOrders []types.OrderID

	// Check OCO controller for related orders (for TPSL, this returns the SL order)
	relatedOrders := m.ocoController.ExecuteOCO(orderID)

	// Cancel related SL triggers
	for _, slOrderID := range relatedOrders {
		// SL orders are always in triggers (conditional orders)
		if m.triggerManager.RemoveTrigger(slOrderID) {
			cancelledOrders = append(cancelledOrders, slOrderID)
			log.Debug("SL trigger cancelled due to TP fill (OCO)",
				"slOrderID", slOrderID,
				"tpOrderID", orderID)
			metrics.ConditionalOrdersTriggeredCounter.Inc(1)
			metrics.ConditionalOrdersActiveGauge.Dec(1)
		}
	}

	return cancelledOrders
}

func (m *Manager) CancelSingleOrder(id types.OrderID) (types.OrderID, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Try to remove as trigger first
	if m.triggerManager.RemoveTrigger(id) {
		metrics.ConditionalOrdersActiveGauge.Dec(1)
		return id, true
	}

	// If not a trigger, try to cancel from orderbook
	if m.orderCanceller != nil {
		if err := m.orderCanceller(id); err != nil {
			log.Error("Failed to cancel order from orderbook",
				"orderID", id,
				"error", err)
			return "", false
		}
		return id, true
	}
	return "", false
}

// CancelOrder cancels a conditional order
func (m *Manager) CancelOrder(orderID types.OrderID) (bool, []types.OrderID) {
	m.mu.Lock()
	defer m.mu.Unlock()

	var cancelledIds []types.OrderID

	// Helper function to cancel an order (either from triggers or orderbook)
	cancelSingleOrder := func(id types.OrderID) bool {
		// Try to remove as trigger first
		if m.triggerManager.RemoveTrigger(id) {
			metrics.ConditionalOrdersActiveGauge.Dec(1)
			cancelledIds = append(cancelledIds, id)
			return true
		}
		
		// If not a trigger, try to cancel from orderbook
		if m.orderCanceller != nil {
			if err := m.orderCanceller(id); err != nil {
				log.Error("Failed to cancel order from orderbook",
					"orderID", id,
					"error", err)
				return false
			}
			cancelledIds = append(cancelledIds, id)
			return true
		}
		return false
	}

	// Step 1: Cancel the original order
	originalCancelled := cancelSingleOrder(orderID)
	
	// Step 2: Cancel related OCO orders
	// Note: CancelOCO returns the OTHER orders that need to be cancelled
	relatedOrders := m.ocoController.CancelOCO(orderID)
	for _, relatedID := range relatedOrders {
		cancelSingleOrder(relatedID)
	}

	return originalCancelled || len(relatedOrders) > 0, cancelledIds
}

// CancelUserOrders cancels all conditional orders for a user
func (m *Manager) CancelUserOrders(userID types.UserID) []types.OrderID {
	m.mu.Lock()
	defer m.mu.Unlock()

	var allCancelled []types.OrderID

	// Step 1: Remove all triggers for the user (Stop orders, SL orders)
	cancelledTriggers := m.triggerManager.RemoveUserTriggers(userID)
	allCancelled = append(allCancelled, cancelledTriggers...)

	// Update metrics for cancelled triggers
	if len(cancelledTriggers) > 0 {
		metrics.ConditionalOrdersActiveGauge.Dec(int64(len(cancelledTriggers)))
	}

	// Step 2: Get all OCO pairs that might be affected
	// For each cancelled trigger, check if it has OCO relationships
	for _, triggerID := range cancelledTriggers {
		relatedOrders := m.ocoController.CancelOCO(triggerID)

		// Cancel related orderbook orders via callback
		for _, orderID := range relatedOrders {
			if m.orderCanceller != nil {
				if err := m.orderCanceller(orderID); err == nil {
					allCancelled = append(allCancelled, orderID)
				}
			}
		}
	}

	// Note: We don't need to explicitly handle TPSL here because:
	// - SL orders are handled by RemoveUserTriggers
	// - TP orders in orderbook should be cancelled by SymbolEngine directly
	// - OCO relationships ensure proper cleanup

	log.Debug("User conditional orders cancelled",
		"userID", userID,
		"totalCancelled", len(allCancelled))

	return allCancelled
}

// GetQueueSize returns the number of active triggers
func (m *Manager) GetQueueSize() int {
	triggerManager, ok := m.triggerManager.(*tpsl.DefaultTriggerManager)
	if ok {
		return triggerManager.GetQueueSize()
	}
	return 0
}

// Clear removes all conditional orders
func (m *Manager) Clear() {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Clear all modules
	if tm, ok := m.triggerManager.(*tpsl.DefaultTriggerManager); ok {
		tm.Clear()
	}
	if oc, ok := m.ocoController.(*tpsl.DefaultOCOController); ok {
		oc.Clear()
	}

	// Reset metrics to 0
	metrics.ConditionalOrdersActiveGauge.Update(0)

	log.Debug("All conditional orders cleared")
}

func (m *Manager) GetRelatedOrders(orderID types.OrderID) []types.OrderID {
	m.mu.RLock()
	defer m.mu.RUnlock()

	return m.ocoController.GetRelatedOrders(orderID)
}

// HasTPSL checks if an order has active TPSL
func (m *Manager) HasTPSL(orderID types.OrderID) bool {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Check if there are related orders in OCO controller
	// For TPSL, the original order ID would be used to generate TP and SL order IDs
	tpOrderID := types.GenerateTPOrderID(orderID)
	relatedOrders := m.ocoController.GetRelatedOrders(tpOrderID)
	return len(relatedOrders) > 0
}

// GetAllStopOrders returns all stop orders for persistence
func (m *Manager) GetAllStopOrders() []*types.StopOrder {
	triggers := m.triggerManager.GetAllTriggers()

	var stopOrders []*types.StopOrder
	for _, trigger := range triggers {
		if stopTrigger, ok := trigger.(*tpsl.StopOrderTrigger); ok {
			// Extract stop order details from trigger
			stopOrder := &types.StopOrder{
				Order:        stopTrigger.GetOrder(),
				StopPrice:    stopTrigger.GetStopPrice(),
				TriggerAbove: stopTrigger.IsTriggerAbove(),
				Status:       types.TRIGGER_WAIT,
				CreatedAt:    0, // We don't store creation time in trigger
			}
			stopOrders = append(stopOrders, stopOrder)
		}
	}

	return stopOrders
}

// Snapshot methods for persistence

// GetTriggerState returns the current trigger state for persistence
func (m *Manager) GetTriggerState() (triggers []types.ConditionalTrigger, queue []types.OrderID) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	// Get trigger manager state
	if tm, ok := m.triggerManager.(*tpsl.DefaultTriggerManager); ok {
		allTriggers := tm.GetAllTriggers()
		triggers = make([]types.ConditionalTrigger, 0, len(allTriggers))
		
		for _, trigger := range allTriggers {
			var triggerType string

			// Determine trigger type and extract data
			switch trigger.(type) {
			case *tpsl.StopOrderTrigger:
				triggerType = "stop_order"
			case *tpsl.StopLossTrigger:
				triggerType = "stop_loss"
			default:
				// Skip unknown trigger types
				continue
			}
			
			triggers = append(triggers, types.ConditionalTrigger{
				OrderID:      trigger.GetOrderID(),
				TriggerType:  triggerType,
				Order:        trigger.GetOrder(),
				TriggerPrice: trigger.GetStopPrice(),
				TriggerAbove: trigger.IsTriggerAbove(),
			})
		}
		
		// Get queue
		queue = tm.GetQueue()
	}
	
	return triggers, queue
}

// GetOCOPairs returns the current OCO pairs for persistence
func (m *Manager) GetOCOPairs() []types.OCOPairSnapshot {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	if oc, ok := m.ocoController.(*tpsl.DefaultOCOController); ok {
		pairs := oc.GetAllPairs()
		snapshots := make([]types.OCOPairSnapshot, 0, len(pairs))
		
		for _, pair := range pairs {
			snapshots = append(snapshots, types.OCOPairSnapshot{
				PairID:   pair.ID,
				OrderIDs: pair.OrderIDs,
			})
		}
		
		return snapshots
	}
	
	return nil
}

// RestoreTriggerState restores triggers from persistence
func (m *Manager) RestoreTriggerState(triggers []types.ConditionalTrigger, queue []types.OrderID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	if tm, ok := m.triggerManager.(*tpsl.DefaultTriggerManager); ok {
		// Clear existing triggers first
		tm.Clear()
		
		// Restore triggers
		for _, trigger := range triggers {
			var trig tpsl.Trigger
			
			switch trigger.TriggerType {
			case "stop_order":
				trig = tpsl.NewStopOrderTrigger(
					trigger.Order,
					trigger.TriggerPrice,
					trigger.TriggerAbove,
				)
			case "stop_loss":
				trig = tpsl.NewStopLossTrigger(
					trigger.Order,
					trigger.TriggerPrice,
					trigger.TriggerAbove,
				)
			default:
				log.Warn("Unknown trigger type during restore", "type", trigger.TriggerType)
				continue
			}
			
			if err := tm.AddTrigger(trig); err != nil {
				log.Error("Failed to restore trigger", "orderID", trigger.OrderID, "error", err)
			}
		}
		
		// Restore queue order
		tm.RestoreQueue(queue)
	}
	
	return nil
}

// RestoreOCOPairs restores OCO pairs from persistence
func (m *Manager) RestoreOCOPairs(pairs []types.OCOPairSnapshot) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	if oc, ok := m.ocoController.(*tpsl.DefaultOCOController); ok {
		// Clear existing pairs first
		oc.Clear()
		
		// Restore pairs
		for _, snapshot := range pairs {
			pair := &tpsl.OCOPair{
				ID:       snapshot.PairID,
				OrderIDs: snapshot.OrderIDs,
			}
			
			if err := oc.RegisterPair(pair); err != nil {
				log.Error("Failed to restore OCO pair", "pairID", snapshot.PairID, "error", err)
			}
		}
	}
	
	return nil
}

// RestoreStopOrder restores a stop order from persistence
func (m *Manager) RestoreStopOrder(stopOrder *types.StopOrder) error {
	if stopOrder == nil || stopOrder.Order == nil {
		return types.ErrInvalidOrder
	}

	// Create a stop order trigger
	trigger := tpsl.NewStopOrderTrigger(
		stopOrder.Order,
		stopOrder.StopPrice,
		stopOrder.TriggerAbove,
	)

	// Restore to trigger manager
	return m.triggerManager.RestoreTrigger(trigger)
}

// GetUserOrders returns all conditional order IDs for a user
func (m *Manager) GetUserOrders(userID types.UserID) []types.OrderID {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Get triggers from TriggerManager (Stop orders, SL orders)
	// Note: TP orders are in the orderbook, not conditional orders
	return m.triggerManager.GetUserTriggers(userID)
}
