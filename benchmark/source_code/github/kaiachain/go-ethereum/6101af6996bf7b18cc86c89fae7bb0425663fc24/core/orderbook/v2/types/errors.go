package types

import "errors"

// General orderbook errors
var (
	// Order validation errors
	ErrOrderNil           = errors.New("order cannot be nil")
	ErrOrderNotFound      = errors.New("order not found")
	ErrOrderExists        = errors.New("order already exists")
	ErrOrderAlreadyExists = errors.New("order already exists")
	ErrInvalidOrder       = errors.New("invalid order")
	ErrInvalidOrderType   = errors.New("invalid order type")
	ErrOrderIDRequired    = errors.New("order ID is required")
	ErrUserIDRequired     = errors.New("user ID is required")
	ErrSymbolMismatch     = errors.New("symbol mismatch")
	ErrInvalidQuantity    = errors.New("quantity must be positive")
	ErrLimitPriceRequired = errors.New("limit order must have price")
	ErrSymbolEmpty        = errors.New("symbol cannot be empty")
	ErrInvalidSymbol      = errors.New("invalid symbol")
	ErrInvalidPrice       = errors.New("invalid price")

	// Queue errors
	ErrQueueNil = errors.New("opposite queue cannot be nil")

	// Matching errors
	ErrMatchingFailed       = errors.New("matching failed")
	ErrUnsupportedOrderType = errors.New("unsupported order type")

	// Conditional order errors
	ErrTPSLMissingOrders = errors.New("TPSL order must have at least one of TP or SL")

	// Event errors
	ErrInvalidEvent           = errors.New("invalid event data")
	ErrEventApplicationFailed = errors.New("failed to apply event")
	ErrUnknownEventType       = errors.New("unknown event type")
)
