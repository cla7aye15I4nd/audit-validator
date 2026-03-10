package tpsl

import (
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/holiman/uint256"
)

// TriggerManager monitors conditions and manages triggers
type TriggerManager interface {
	// CheckTriggers checks all triggers against current price and returns triggered orders
	CheckTriggers(currentPrice *uint256.Int) []TriggeredOrder

	// AddTrigger adds a new trigger to monitor
	AddTrigger(trigger Trigger) error

	// RemoveTrigger removes a trigger by order ID
	RemoveTrigger(orderID types.OrderID) bool

	// GetTrigger returns a trigger by order ID
	GetTrigger(orderID types.OrderID) (Trigger, bool)

	// RemoveUserTriggers removes all triggers for a specific user
	RemoveUserTriggers(userID types.UserID) []types.OrderID

	// GetUserTriggers returns all trigger order IDs for a specific user
	GetUserTriggers(userID types.UserID) []types.OrderID
	
	// GetAllTriggers returns all active triggers
	GetAllTriggers() []Trigger
	
	// RestoreTrigger adds a trigger for recovery (bypasses duplicate checks)
	RestoreTrigger(trigger Trigger) error
}

// Trigger represents a conditional trigger
type Trigger interface {
	GetOrder() *types.Order
	GetOrderID() types.OrderID
	GetUserID() types.UserID
	GetStopPrice() *uint256.Int
	IsTriggerAbove() bool
	ShouldTrigger(currentPrice *uint256.Int) bool
	Execute() *types.Order
	Cancel()
}

// TriggeredOrder represents an order that was triggered
type TriggeredOrder struct {
	Order       *types.Order
	TriggerType TriggerType
}

// TriggerType represents the type of trigger
type TriggerType string

const (
	TriggerTypeStopLoss   TriggerType = "STOP_LOSS"
	TriggerTypeStopOrder  TriggerType = "STOP_ORDER"
	TriggerTypeTakeProfit TriggerType = "TAKE_PROFIT"
)

// ActivationRule determines when and how to activate TPSL orders
type ActivationRule interface {
	// ShouldActivate checks if TPSL should be activated for this order
	ShouldActivate(order *types.Order) bool

	// Activate creates TPSL activation from a filled order
	Activate(order *types.Order) (*TPSLActivation, error)
}

// TPSLActivation contains all components created when TPSL is activated
type TPSLActivation struct {
	TPOrder   *types.Order // Take-profit order (goes to orderbook immediately)
	SLTrigger Trigger      // Stop-loss trigger (conditional)
	OCOPair   *OCOPair     // OCO relationship between TP and SL
}


// OCOController manages One-Cancels-Other relationships
type OCOController interface {
	// RegisterPair registers a new OCO pair
	RegisterPair(pair *OCOPair) error

	// ExecuteOCO executes OCO rule when an order completes (filled/triggered)
	// Returns order IDs that should be cancelled
	ExecuteOCO(orderID types.OrderID) []types.OrderID

	// CancelOCO handles when an order is manually cancelled
	// Returns related orders that should also be cancelled
	CancelOCO(orderID types.OrderID) []types.OrderID

	// GetRelatedOrders returns all orders related to the given order
	GetRelatedOrders(orderID types.OrderID) []types.OrderID

	// RemovePair removes an OCO pair
	RemovePair(pairID string) bool
}

// OCOPair represents a One-Cancels-Other relationship
type OCOPair struct {
	ID        string          // Unique identifier for this OCO pair
	OrderIDs  []types.OrderID // Related order IDs
	Strategy  OCOStrategy     // OCO strategy type
	CreatedAt int64           // Creation timestamp
}

// OCOStrategy defines the OCO behavior
type OCOStrategy string

const (
	// OneCancelsOther - when one order fills OR is cancelled, cancel the others
	// This is the default for TPSL: if TP or SL is manually cancelled, the other is also cancelled
	OneCancelsOther OCOStrategy = "ONE_CANCELS_OTHER"

	// AllOrNone - all orders must fill completely or all are cancelled
	AllOrNone OCOStrategy = "ALL_OR_NONE"

	// OneFillsCancelsOthers - only filling triggers cancellation, manual cancel doesn't trigger OCO
	// Use this when you want manual cancellation to leave other orders active
	OneFillsCancelsOthers OCOStrategy = "ONE_FILLS_CANCELS_OTHERS"
)
