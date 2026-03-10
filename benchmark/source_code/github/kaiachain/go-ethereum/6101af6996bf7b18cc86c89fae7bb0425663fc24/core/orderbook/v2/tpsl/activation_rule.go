package tpsl

import (
	"fmt"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/log"
)

// TPSLActivationRule implements ActivationRule interface
type TPSLActivationRule struct{}

// NewActivationRule creates a new activation rule
func NewActivationRule() *TPSLActivationRule {
	return &TPSLActivationRule{}
}

// ShouldActivate checks if TPSL should be activated for this order
func (r *TPSLActivationRule) ShouldActivate(order *types.Order) bool {
	if order == nil {
		return false
	}

	// Check if order has TPSL context
	if !order.HasTPSL() {
		return false
	}

	// Only activate for filled orders
	if order.Status != types.FILLED {
		return false
	}

	// Validate TPSL parameters
	ctx := order.TPSL
	if ctx.TPLimitPrice == nil || ctx.SLTriggerPrice == nil {
		log.Warn("Invalid TPSL parameters", "orderID", order.OrderID)
		return false
	}

	return true
}

// Activate creates TPSL activation from a filled order
func (r *TPSLActivationRule) Activate(order *types.Order) (*TPSLActivation, error) {
	if !r.ShouldActivate(order) {
		return nil, fmt.Errorf("order not eligible for TPSL activation")
	}

	ctx := order.TPSL

	// Create TP order (immediate execution to orderbook)
	tpOrder := &types.Order{
		OrderID:   types.GenerateTPOrderID(order.OrderID),
		UserID:    order.UserID,
		Symbol:    order.Symbol,
		Side:      order.Side.Opposite(), // Opposite side to close position
		OrderType: types.TP_LIMIT,
		Price:     ctx.TPLimitPrice,
		Quantity:  order.OrigQty.Clone(), // Use original quantity
		OrigQty:   order.OrigQty.Clone(),
		Status:    types.NEW,
		Timestamp: types.TimeNow(),
	}

	// Create SL order (conditional execution)
	slOrder := &types.Order{
		OrderID:   types.GenerateSLOrderID(order.OrderID),
		UserID:    order.UserID,
		Symbol:    order.Symbol,
		Side:      order.Side.Opposite(), // Opposite side to close position
		OrderType: types.SL_LIMIT,
		Price:     ctx.SLLimitPrice, // Can be nil for market order
		Quantity:  order.OrigQty.Clone(),
		OrigQty:   order.OrigQty.Clone(),
		Status:    types.TRIGGER_WAIT,
		Timestamp: types.TimeNow(),
	}

	// If no SL limit price, make it a market order
	if ctx.SLLimitPrice == nil {
		slOrder.OrderType = types.SL_MARKET
	}

	// Determine SL trigger direction based on original order side
	// For BUY orders: SL triggers when price falls below trigger price
	// For SELL orders: SL triggers when price rises above trigger price
	slTriggerAbove := order.Side == types.SELL

	// Create SL trigger
	slTrigger := NewStopLossTrigger(slOrder, ctx.SLTriggerPrice, slTriggerAbove)

	// Create OCO pair
	ocoPair := &OCOPair{
		ID:        fmt.Sprintf("TPSL_%s", order.OrderID),
		OrderIDs:  []types.OrderID{tpOrder.OrderID, slOrder.OrderID},
		Strategy:  OneCancelsOther, // Default TPSL behavior: any completion cancels the other
		CreatedAt: types.TimeNow(),
	}

	activation := &TPSLActivation{
		TPOrder:   tpOrder,
		SLTrigger: slTrigger,
		OCOPair:   ocoPair,
	}

	log.Debug("TPSL activated",
		"originalOrder", order.OrderID,
		"tpOrder", tpOrder.OrderID,
		"slOrder", slOrder.OrderID,
		"tpPrice", ctx.TPLimitPrice.String(),
		"slTriggerPrice", ctx.SLTriggerPrice.String())

	return activation, nil
}

// ValidateTPSLContext validates TPSL parameters for an order
func (r *TPSLActivationRule) ValidateTPSLContext(order *types.Order) error {
	if order == nil || order.TPSL == nil {
		return fmt.Errorf("order or TPSL context is nil")
	}

	ctx := order.TPSL
	
	// Validate required fields
	if ctx.TPLimitPrice == nil {
		return fmt.Errorf("TP limit price is required")
	}
	if ctx.SLTriggerPrice == nil {
		return fmt.Errorf("SL trigger price is required")
	}

	// Validate price relationships based on side
	if order.Side == types.BUY {
		// For BUY orders:
		// - TP should be higher than current price (profit)
		// - SL should be lower than current price (loss)
		if order.Price != nil {
			if ctx.TPLimitPrice.Cmp(order.Price) <= 0 {
				return fmt.Errorf("TP price must be higher than order price for BUY orders")
			}
			if ctx.SLTriggerPrice.Cmp(order.Price) >= 0 {
				return fmt.Errorf("SL trigger price must be lower than order price for BUY orders")
			}
		}
	} else { // SELL
		// For SELL orders:
		// - TP should be lower than current price (profit)
		// - SL should be higher than current price (loss)
		if order.Price != nil {
			if ctx.TPLimitPrice.Cmp(order.Price) >= 0 {
				return fmt.Errorf("TP price must be lower than order price for SELL orders")
			}
			if ctx.SLTriggerPrice.Cmp(order.Price) <= 0 {
				return fmt.Errorf("SL trigger price must be higher than order price for SELL orders")
			}
		}
	}

	return nil
}