package orderbook

import (
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// StopOrderHandler handles single stop orders (TP or SL only)
type StopOrderHandler struct{}

// NewStopOrderHandler creates a new StopOrderHandler
func NewStopOrderHandler() *StopOrderHandler {
	return &StopOrderHandler{}
}

// ShouldTrigger checks if a stop order should trigger
func (h *StopOrderHandler) ShouldTrigger(data interface{}, lastPrice *uint256.Int) bool {
	tpsl, ok := data.(*TPSLOrder)
	if !ok {
		return false
	}
	
	// Single TP order
	if tpsl.TPOrder != nil && tpsl.SLOrder == nil {
		stop := tpsl.TPOrder
		return (stop.TriggerAbove && lastPrice.Cmp(stop.StopPrice) >= 0) ||
			(!stop.TriggerAbove && lastPrice.Cmp(stop.StopPrice) <= 0)
	}
	
	// Single SL order
	if tpsl.SLOrder != nil && tpsl.TPOrder == nil {
		stop := tpsl.SLOrder
		return (stop.TriggerAbove && lastPrice.Cmp(stop.StopPrice) >= 0) ||
			(!stop.TriggerAbove && lastPrice.Cmp(stop.StopPrice) <= 0)
	}
	
	return false
}

// Process handles a triggered stop order
func (h *StopOrderHandler) Process(entry *ConditionalOrderEntry, lastPrice *uint256.Int, userBook *UserBook, 
	locker *DefaultLocker, cancelFunc func(string, *DefaultLocker) bool) *TriggeredOrder {
	
	tpsl, ok := entry.Data.(*TPSLOrder)
	if !ok {
		entry.ShouldRemove = true
		return nil
	}
	
	// Single TP order
	if tpsl.TPOrder != nil && tpsl.SLOrder == nil {
		order := tpsl.TPOrder.Order
		locker.UnlockStopOrder(order, tpsl.TPOrder.StopPrice)
		log.Info(LogTPOrderTriggered, "orderId", order.OrderID, "stopPrice", toDecimal(tpsl.TPOrder.StopPrice))
		entry.ShouldRemove = true // Stop order is triggered and should be removed
		return &TriggeredOrder{order, STOPLIMIT}
	}
	
	// Single SL order
	if tpsl.SLOrder != nil && tpsl.TPOrder == nil {
		order := tpsl.SLOrder.Order
		locker.UnlockStopOrder(order, tpsl.SLOrder.StopPrice)
		log.Info("SL order triggered", "orderId", order.OrderID, "stopPrice", toDecimal(tpsl.SLOrder.StopPrice))
		entry.ShouldRemove = true // Stop order is triggered and should be removed
		return &TriggeredOrder{order, STOPLIMIT}
	}
	
	entry.ShouldRemove = true // Invalid stop order
	return nil
}

// Cancel cancels a stop order by direct ID match
func (h *StopOrderHandler) Cancel(orderID string, data interface{}, locker *DefaultLocker,
	cancelOrderbookFunc func(string, *DefaultLocker) bool) []string {
	
	tpsl, ok := data.(*TPSLOrder)
	if !ok {
		return nil
	}
	
	// Single TP order
	if tpsl.TPOrder != nil && tpsl.SLOrder == nil {
		if tpsl.TPOrder.Order.OrderID == orderID {
			locker.UnlockStopOrder(tpsl.TPOrder.Order, tpsl.TPOrder.StopPrice)
			log.Info(LogTPOrderCanceled, "orderID", orderID)
			return []string{orderID}
		}
	}
	
	// Single SL order
	if tpsl.SLOrder != nil && tpsl.TPOrder == nil {
		if tpsl.SLOrder.Order.OrderID == orderID {
			locker.UnlockStopOrder(tpsl.SLOrder.Order, tpsl.SLOrder.StopPrice)
			log.Info(LogSLOrderCanceled, "orderID", orderID)
			return []string{orderID}
		}
	}
	
	return nil
}


// CancelByUser cancels stop orders for a user
func (h *StopOrderHandler) CancelByUser(userId string, data interface{}, locker *DefaultLocker) []string {
	tpsl, ok := data.(*TPSLOrder)
	if !ok {
		return nil
	}
	
	var cancelledIds []string
	
	// Single TP order
	if tpsl.TPOrder != nil && tpsl.SLOrder == nil {
		if tpsl.TPOrder.Order.UserID == userId {
			locker.UnlockStopOrder(tpsl.TPOrder.Order, tpsl.TPOrder.StopPrice)
			cancelledIds = append(cancelledIds, tpsl.TPOrder.Order.OrderID)
			log.Info(LogCancelAllUnlockedTP, "userId", userId, "orderID", tpsl.TPOrder.Order.OrderID)
		}
	}
	
	// Single SL order
	if tpsl.SLOrder != nil && tpsl.TPOrder == nil {
		if tpsl.SLOrder.Order.UserID == userId {
			locker.UnlockStopOrder(tpsl.SLOrder.Order, tpsl.SLOrder.StopPrice)
			cancelledIds = append(cancelledIds, tpsl.SLOrder.Order.OrderID)
			log.Info(LogCancelAllUnlockedSL, "userId", userId, "orderID", tpsl.SLOrder.Order.OrderID)
		}
	}
	
	return cancelledIds
}

// GetOrderIDs returns the order IDs for a stop order entry
func (h *StopOrderHandler) GetOrderIDs(data interface{}) []string {
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

// GetUserID returns the user ID for a stop order entry
func (h *StopOrderHandler) GetUserID(data interface{}) string {
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