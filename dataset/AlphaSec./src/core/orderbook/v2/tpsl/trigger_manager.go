package tpsl

import (
	"sync"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// DefaultTriggerManager implements TriggerManager interface
type DefaultTriggerManager struct {
	mu       sync.RWMutex
	triggers map[types.OrderID]Trigger // OrderID -> Trigger
	queue    []types.OrderID           // FIFO processing order
}

// NewTriggerManager creates a new trigger manager
func NewTriggerManager() *DefaultTriggerManager {
	return &DefaultTriggerManager{
		triggers: make(map[types.OrderID]Trigger),
		queue:    make([]types.OrderID, 0),
	}
}

// CheckTriggers checks all triggers against current price
func (m *DefaultTriggerManager) CheckTriggers(currentPrice *uint256.Int) []TriggeredOrder {
	if currentPrice == nil {
		return nil
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	var triggered []TriggeredOrder
	var remaining []types.OrderID

	// Process triggers in FIFO order
	for _, orderID := range m.queue {
		trigger, exists := m.triggers[orderID]
		if !exists {
			continue // Trigger was removed
		}

		if trigger.ShouldTrigger(currentPrice) {
			// Execute the trigger
			order := trigger.Execute()
			if order != nil {
				// Determine trigger type
				triggerType := m.determineTriggerType(trigger)
				
				triggered = append(triggered, TriggeredOrder{
					Order:       order,
					TriggerType: triggerType,
				})
				
				// Remove from triggers
				delete(m.triggers, orderID)
				
				log.Debug("Trigger activated", 
					"orderID", orderID, 
					"type", triggerType,
					"price", currentPrice.String())
			}
		} else {
			// Keep in queue
			remaining = append(remaining, orderID)
		}
	}

	m.queue = remaining
	return triggered
}

// AddTrigger adds a new trigger to monitor
func (m *DefaultTriggerManager) AddTrigger(trigger Trigger) error {
	if trigger == nil {
		return types.ErrInvalidOrder
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	orderID := trigger.GetOrderID()
	if _, exists := m.triggers[orderID]; exists {
		return types.ErrOrderAlreadyExists
	}

	m.triggers[orderID] = trigger
	m.queue = append(m.queue, orderID)
	
	log.Debug("Trigger added", "orderID", orderID)
	return nil
}

// RemoveTrigger removes a trigger by order ID
func (m *DefaultTriggerManager) RemoveTrigger(orderID types.OrderID) bool {
	m.mu.Lock()
	defer m.mu.Unlock()

	trigger, exists := m.triggers[orderID]
	if !exists {
		return false
	}

	// Cancel the trigger
	trigger.Cancel()
	
	// Remove from map
	delete(m.triggers, orderID)
	
	// Remove from queue
	var newQueue []types.OrderID
	for _, id := range m.queue {
		if id != orderID {
			newQueue = append(newQueue, id)
		}
	}
	m.queue = newQueue
	
	log.Debug("Trigger removed", "orderID", orderID)
	return true
}

// GetTrigger returns a trigger by order ID
func (m *DefaultTriggerManager) GetTrigger(orderID types.OrderID) (Trigger, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	trigger, exists := m.triggers[orderID]
	return trigger, exists
}

// determineTriggerType determines the type of trigger
func (m *DefaultTriggerManager) determineTriggerType(trigger Trigger) TriggerType {
	// This would be better with type assertion or a GetType method on Trigger
	// For now, we'll use a simple approach
	switch trigger.(type) {
	case *StopLossTrigger:
		return TriggerTypeStopLoss
	case *StopOrderTrigger:
		return TriggerTypeStopOrder
	default:
		return TriggerTypeStopOrder
	}
}

// GetAllTriggers returns all triggers for persistence
func (m *DefaultTriggerManager) GetAllTriggers() []Trigger {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	triggers := make([]Trigger, 0, len(m.triggers))
	for _, trigger := range m.triggers {
		triggers = append(triggers, trigger)
	}
	return triggers
}

// RestoreTrigger adds a trigger for recovery (bypasses duplicate checks)
func (m *DefaultTriggerManager) RestoreTrigger(trigger Trigger) error {
	if trigger == nil {
		return types.ErrInvalidOrder
	}
	
	m.mu.Lock()
	defer m.mu.Unlock()
	
	orderID := trigger.GetOrderID()
	m.triggers[orderID] = trigger
	m.queue = append(m.queue, orderID)
	
	log.Debug("Trigger restored", "orderID", orderID)
	return nil
}

// RemoveUserTriggers removes all triggers for a specific user
func (m *DefaultTriggerManager) RemoveUserTriggers(userID types.UserID) []types.OrderID {
	m.mu.Lock()
	defer m.mu.Unlock()

	var removedIDs []types.OrderID
	var newQueue []types.OrderID

	// Check each trigger
	for _, orderID := range m.queue {
		trigger, exists := m.triggers[orderID]
		if !exists {
			continue
		}

		// If trigger belongs to user, remove it
		if trigger.GetUserID() == userID {
			trigger.Cancel()
			delete(m.triggers, orderID)
			removedIDs = append(removedIDs, orderID)
		} else {
			// Keep in queue
			newQueue = append(newQueue, orderID)
		}
	}

	m.queue = newQueue

	if len(removedIDs) > 0 {
		log.Debug("User triggers removed", 
			"userID", userID, 
			"count", len(removedIDs))
	}

	return removedIDs
}

// GetUserTriggers returns all trigger order IDs for a specific user
func (m *DefaultTriggerManager) GetUserTriggers(userID types.UserID) []types.OrderID {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var userTriggers []types.OrderID

	for orderID, trigger := range m.triggers {
		if trigger.GetUserID() == userID {
			userTriggers = append(userTriggers, orderID)
		}
	}

	return userTriggers
}

// GetQueueSize returns the number of active triggers
func (m *DefaultTriggerManager) GetQueueSize() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(m.queue)
}

// GetQueue returns the current trigger queue for persistence
func (m *DefaultTriggerManager) GetQueue() []types.OrderID {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	queue := make([]types.OrderID, len(m.queue))
	copy(queue, m.queue)
	return queue
}

// RestoreQueue restores the trigger queue order from persistence
func (m *DefaultTriggerManager) RestoreQueue(queue []types.OrderID) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	m.queue = make([]types.OrderID, len(queue))
	copy(m.queue, queue)
}

// Clear removes all triggers
func (m *DefaultTriggerManager) Clear() {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Cancel all triggers
	for _, trigger := range m.triggers {
		trigger.Cancel()
	}

	m.triggers = make(map[types.OrderID]Trigger)
	m.queue = make([]types.OrderID, 0)
	
	log.Debug("All triggers cleared")
}