package orderbook

import (
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// TPSLHandler handles TPSL orders (orders with both TP and SL)
type TPSLHandler struct{}

// NewTPSLHandler creates a new TPSLHandler
func NewTPSLHandler() *TPSLHandler {
	return &TPSLHandler{}
}

// ShouldTrigger checks if a TPSL order should trigger
func (h *TPSLHandler) ShouldTrigger(data interface{}, lastPrice *uint256.Int) bool {
	tpsl, ok := data.(*TPSLOrder)
	if !ok || tpsl.TPOrder == nil || tpsl.SLOrder == nil {
		return false
	}
	
	// For TPSL orders, we always need to call Process to check various conditions:
	// 1. Initial TP submission
	// 2. TP partial fill check
	// 3. SL trigger check
	// The Process function will determine what action to take
	return true
}

// Process handles a triggered TPSL order
// Returns: TriggeredOrder if an order should be placed, nil otherwise
// Note: Returning nil does NOT mean remove from queue for TPSL orders
func (h *TPSLHandler) Process(entry *ConditionalOrderEntry, lastPrice *uint256.Int, userBook *UserBook, 
	locker *DefaultLocker, cancelFunc func(string, *DefaultLocker) bool) *TriggeredOrder {
	
	tpsl, ok := entry.Data.(*TPSLOrder)
	if !ok || tpsl.TPOrder == nil || tpsl.SLOrder == nil {
		// Invalid TPSL, mark for removal
		entry.ShouldRemove = true
		return nil
	}
	
	if !tpsl.submitted {
		// First trigger - submit TP order
		order := tpsl.TPOrder.Order
		tpsl.submitted = true
		log.Info("TPSL order triggered (TP submitted)", "orderId", order.OrderID)
		// Keep in queue to monitor for next stage
		return &TriggeredOrder{order, TAKEPROFIT}
	}
	
	// After TP is submitted, check for two conditions:
	// 1. TP order has been partially filled - remove entire TPSL
	tpOrder, exists := userBook.GetOrder(tpsl.TPOrder.Order.OrderID)
	if exists && tpOrder.Quantity.Cmp(tpOrder.OrigQty) != 0 {
		// TP has been partially filled, mark for removal
		log.Info("TPSL removed due to TP partial fill", "orderId", tpsl.TPOrder.Order.OrderID, 
			"currentQty", tpOrder.Quantity.String(), "origQty", tpOrder.OrigQty.String())
		entry.ShouldRemove = true
		return nil
	}
	
	// 2. SL stop price is triggered - cancel TP and trigger SL
	if (tpsl.SLOrder.TriggerAbove && lastPrice.Cmp(tpsl.SLOrder.StopPrice) >= 0) ||
		(!tpsl.SLOrder.TriggerAbove && lastPrice.Cmp(tpsl.SLOrder.StopPrice) <= 0) {
		// Cancel the TP order
		cancelFunc(tpsl.TPOrder.Order.OrderID, locker)
		log.Info("TP order cancelled due to SL trigger", "orderId", tpsl.TPOrder.Order.OrderID)
		
		// Trigger the SL order
		order := tpsl.SLOrder.Order
		log.Info("SL order triggered", "orderId", order.OrderID, "stopPrice", toDecimal(tpsl.SLOrder.StopPrice))
		entry.ShouldRemove = true
		return &TriggeredOrder{order, STOPLOSS}
	}
	
	// Neither condition met - keep monitoring (do NOT set ShouldRemove)
	return nil
}

// Cancel cancels a TPSL order by direct ID match (TP or SL ID)
func (h *TPSLHandler) Cancel(orderID string, data interface{}, locker *DefaultLocker,
	cancelOrderbookFunc func(string, *DefaultLocker) bool) []string {
	
	tpsl, ok := data.(*TPSLOrder)
	if !ok {
		return nil
	}
	
	// Check if orderID matches either TP or SL
	matchesTP := tpsl.TPOrder != nil && tpsl.TPOrder.Order.OrderID == orderID
	matchesSL := tpsl.SLOrder != nil && tpsl.SLOrder.Order.OrderID == orderID
	
	if !matchesTP && !matchesSL {
		return nil // Not this order
	}
	
	// Behavioral rule: cannot cancel individual TPSL orders before trigger
	if !tpsl.submitted && tpsl.TPOrder != nil && tpsl.SLOrder != nil {
		log.Warn("Cannot cancel individual TPSL order before trigger", "orderID", orderID)
		return nil
	}
	
	var cancelledIDs []string
	
	// After trigger (executed=true), TP is in the orderbook
	if tpsl.submitted && tpsl.TPOrder != nil {
		// Cancel TP from the regular orderbook
		if cancelOrderbookFunc(tpsl.TPOrder.Order.OrderID, locker) {
			cancelledIDs = append(cancelledIDs, tpsl.TPOrder.Order.OrderID)
			log.Info(LogTPSLOrderCanceled, "orderID", tpsl.TPOrder.Order.OrderID)
		}
		// Also cancel SL that's still waiting
		if tpsl.SLOrder != nil {
			cancelledIDs = append(cancelledIDs, tpsl.SLOrder.Order.OrderID)
			log.Info(LogTPSLOrderCanceled, "orderID", tpsl.SLOrder.Order.OrderID)
		}
	}
	
	return cancelledIDs
}


// CancelByUser cancels TPSL orders for a user
func (h *TPSLHandler) CancelByUser(userId string, data interface{}, locker *DefaultLocker) []string {
	tpsl, ok := data.(*TPSLOrder)
	if !ok {
		return nil
	}

	var cancelledIds []string
	// Check if this order belongs to the user
	if tpsl.TPOrder != nil && tpsl.TPOrder.Order.UserID == userId {
		log.Info(LogCancelAllTPSL, "userId", userId, "orderID", tpsl.TPOrder.Order.OrderID)
		// TP order is placed already, so we do not add it here.
	}
	if tpsl.SLOrder != nil && tpsl.SLOrder.Order.UserID == userId {
		log.Info(LogCancelAllTPSL, "userId", userId, "orderID", tpsl.SLOrder.Order.OrderID)
		cancelledIds = append(cancelledIds, tpsl.SLOrder.Order.OrderID)
	}
	
	return cancelledIds
}

// GetOrderIDs returns the order IDs for a TPSL entry
func (h *TPSLHandler) GetOrderIDs(data interface{}) []string {
	tpsl, ok := data.(*TPSLOrder)
	if !ok {
		return nil
	}
	
	var ids []string
	if tpsl.TPOrder != nil && tpsl.TPOrder.Order != nil {
		ids = append(ids, tpsl.TPOrder.Order.OrderID)
	}
	if tpsl.SLOrder != nil && tpsl.SLOrder.Order != nil {
		ids = append(ids, tpsl.SLOrder.Order.OrderID)
	}
	return ids
}

// GetUserID returns the user ID for a TPSL entry
func (h *TPSLHandler) GetUserID(data interface{}) string {
	tpsl, ok := data.(*TPSLOrder)
	if !ok {
		return ""
	}
	
	if tpsl.TPOrder != nil && tpsl.TPOrder.Order != nil {
		return tpsl.TPOrder.Order.UserID
	}
	if tpsl.SLOrder != nil && tpsl.SLOrder.Order != nil {
		return tpsl.SLOrder.Order.UserID
	}
	return ""
}