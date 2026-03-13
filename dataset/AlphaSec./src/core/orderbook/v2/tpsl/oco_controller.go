package tpsl

import (
	"fmt"
	"sync"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/log"
)

// DefaultOCOController implements OCOController interface
type DefaultOCOController struct {
	mu          sync.RWMutex
	pairs       map[string]*OCOPair      // PairID -> OCOPair
	orderToPair map[types.OrderID]string // OrderID -> PairID
}

// NewOCOController creates a new OCO controller
func NewOCOController() *DefaultOCOController {
	return &DefaultOCOController{
		pairs:       make(map[string]*OCOPair),
		orderToPair: make(map[types.OrderID]string),
	}
}

// RegisterPair registers a new OCO pair
func (c *DefaultOCOController) RegisterPair(pair *OCOPair) error {
	if pair == nil || pair.ID == "" {
		return fmt.Errorf("invalid OCO pair")
	}

	c.mu.Lock()
	defer c.mu.Unlock()

	// Check if pair already exists
	if _, exists := c.pairs[pair.ID]; exists {
		return fmt.Errorf("OCO pair %s already exists", pair.ID)
	}

	// Check if any order is already in another pair
	for _, orderID := range pair.OrderIDs {
		if existingPairID, exists := c.orderToPair[orderID]; exists {
			return fmt.Errorf("order %s already in OCO pair %s", orderID, existingPairID)
		}
	}

	// Register the pair
	c.pairs[pair.ID] = pair

	// Map each order to this pair
	for _, orderID := range pair.OrderIDs {
		c.orderToPair[orderID] = pair.ID
	}

	log.Debug("OCO pair registered",
		"pairID", pair.ID,
		"orders", len(pair.OrderIDs),
		"strategy", pair.Strategy)

	return nil
}

// ExecuteOCO executes OCO rule when an order completes (filled/triggered)
func (c *DefaultOCOController) ExecuteOCO(orderID types.OrderID) []types.OrderID {
	c.mu.Lock()
	defer c.mu.Unlock()

	pairID, exists := c.orderToPair[orderID]
	if !exists {
		return nil // Order not in any OCO pair
	}

	pair, exists := c.pairs[pairID]
	if !exists {
		return nil // Pair not found (shouldn't happen)
	}

	var toCancel []types.OrderID

	switch pair.Strategy {
	case OneCancelsOther, OneFillsCancelsOthers:
		// Cancel all other orders in the pair
		for _, id := range pair.OrderIDs {
			if id != orderID {
				toCancel = append(toCancel, id)
			}
		}
		// Remove the pair after processing
		c.removePairInternal(pairID)

	case AllOrNone:
		// For AllOrNone, partial fills would cancel everything
		// Full implementation would need to track fill amounts
		for _, id := range pair.OrderIDs {
			if id != orderID {
				toCancel = append(toCancel, id)
			}
		}
		c.removePairInternal(pairID)
	}

	if len(toCancel) > 0 {
		log.Debug("OCO executed",
			"triggerOrder", orderID,
			"cancelCount", len(toCancel),
			"strategy", pair.Strategy)
	}

	return toCancel
}

// CancelOCO handles when an order is manually cancelled
func (c *DefaultOCOController) CancelOCO(orderID types.OrderID) []types.OrderID {
	c.mu.Lock()
	defer c.mu.Unlock()

	pairID, exists := c.orderToPair[orderID]
	if !exists {
		return nil // Order not in any OCO pair
	}

	pair, exists := c.pairs[pairID]
	if !exists {
		return nil // Pair not found
	}

	var toCancel []types.OrderID

	switch pair.Strategy {
	case OneCancelsOther:
		// Cancel all other orders in the pair
		for _, id := range pair.OrderIDs {
			if id != orderID {
				toCancel = append(toCancel, id)
			}
		}
		c.removePairInternal(pairID)

	case AllOrNone:
		// Cancel all orders including this one
		for _, id := range pair.OrderIDs {
			if id != orderID {
				toCancel = append(toCancel, id)
			}
		}
		c.removePairInternal(pairID)

	case OneFillsCancelsOthers:
		// Manual cancellation doesn't trigger OCO
		// Just remove this order from the pair
		c.removeOrderFromPair(orderID, pairID)
	}

	if len(toCancel) > 0 {
		log.Debug("OCO triggered on cancel",
			"cancelledOrder", orderID,
			"cancelCount", len(toCancel),
			"strategy", pair.Strategy)
	}

	return toCancel
}

// GetRelatedOrders returns all orders related to the given order
func (c *DefaultOCOController) GetRelatedOrders(orderID types.OrderID) []types.OrderID {
	c.mu.RLock()
	defer c.mu.RUnlock()

	pairID, exists := c.orderToPair[orderID]
	if !exists {
		return nil
	}

	pair, exists := c.pairs[pairID]
	if !exists {
		return nil
	}

	// Return all orders except the given one
	var related []types.OrderID
	for _, id := range pair.OrderIDs {
		if id != orderID {
			related = append(related, id)
		}
	}

	return related
}

// RemovePair removes an OCO pair
func (c *DefaultOCOController) RemovePair(pairID string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()

	return c.removePairInternal(pairID)
}

// removePairInternal removes a pair (must be called with lock held)
func (c *DefaultOCOController) removePairInternal(pairID string) bool {
	pair, exists := c.pairs[pairID]
	if !exists {
		return false
	}

	// Remove order mappings
	for _, orderID := range pair.OrderIDs {
		delete(c.orderToPair, orderID)
	}

	// Remove the pair
	delete(c.pairs, pairID)

	log.Debug("OCO pair removed", "pairID", pairID)
	return true
}

// removeOrderFromPair removes a single order from a pair
func (c *DefaultOCOController) removeOrderFromPair(orderID types.OrderID, pairID string) {
	delete(c.orderToPair, orderID)

	pair, exists := c.pairs[pairID]
	if !exists {
		return
	}

	// Remove order from pair's order list
	var remaining []types.OrderID
	for _, id := range pair.OrderIDs {
		if id != orderID {
			remaining = append(remaining, id)
		}
	}
	pair.OrderIDs = remaining

	// If only one order left, remove the pair
	if len(remaining) <= 1 {
		c.removePairInternal(pairID)
	}
}

// GetPairCount returns the number of active OCO pairs
func (c *DefaultOCOController) GetPairCount() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return len(c.pairs)
}

// GetUserPairs returns all OCO pairs that contain orders from a specific user
// This requires OCOPair to track UserID, which we'll add if needed
func (c *DefaultOCOController) GetUserPairs(userID types.UserID) []*OCOPair {
	c.mu.RLock()
	defer c.mu.RUnlock()

	var userPairs []*OCOPair

	// Note: This is a simplified implementation
	// In a real system, we'd need to track UserID in OCOPair
	// or have a separate mapping

	return userPairs
}

// Clear removes all OCO pairs
func (c *DefaultOCOController) Clear() {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.pairs = make(map[string]*OCOPair)
	c.orderToPair = make(map[types.OrderID]string)

	log.Debug("All OCO pairs cleared")
}

// GetAllPairs returns all active OCO pairs
func (c *DefaultOCOController) GetAllPairs() []*OCOPair {
	c.mu.RLock()
	defer c.mu.RUnlock()
	
	var pairs []*OCOPair
	for _, pair := range c.pairs {
		// Make a copy to avoid concurrent modification
		pairCopy := &OCOPair{
			ID:        pair.ID,
			OrderIDs:  append([]types.OrderID{}, pair.OrderIDs...),
			Strategy:  pair.Strategy,
			CreatedAt: pair.CreatedAt,
		}
		pairs = append(pairs, pairCopy)
	}
	
	return pairs
}
