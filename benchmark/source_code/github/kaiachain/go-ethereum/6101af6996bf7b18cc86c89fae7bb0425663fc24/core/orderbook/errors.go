package orderbook

import (
	"errors"
)

// Error types for orderbook operations
var (
	// Order related errors
	ErrOrderNotFound       = errors.New("order not found")
	ErrOrderAlreadyCanceled = errors.New("order is already canceled")
	ErrOrderUserMismatch   = errors.New("order user mismatch")
	ErrInvalidOrderType    = errors.New("invalid order type")
	ErrMarketOrderCannotCancel = errors.New("market order cannot be canceled")
	ErrNoOrderChanges      = errors.New("no changes specified for order modification")
	ErrInvalidQuantity     = errors.New("invalid quantity")
	ErrNewQuantityLessThanFilled = errors.New("new quantity less than filled quantity")
	
	// TPSL related errors
	ErrTPSLMissingOrders   = errors.New("TPSL order must have both TP and SL orders")
	ErrTPSLInvalidOrder    = errors.New("TPSL order must have at least one of TP or SL order")
	
	// Symbol and token errors
	ErrFailedToParseSymbol = errors.New("failed to parse symbol to tokens")
	ErrInvalidSymbol       = errors.New("invalid symbol")
	
	// Processing errors
	ErrNilLocker           = errors.New("locker is nil")
	ErrUnknownRequestType  = errors.New("unknown request type")
)

// Log message formats
const (
	// Order processing log messages
	LogProcessingOrder       = "Processing OrderContext"
	LogProcessingCancelOrder = "Processing cancel order"
	LogProcessingTrade       = "Processing trade"
	LogOrderCanceled         = "Order canceled"
	LogOrderNotFoundOrCanceled = "The order does not exist or is already canceled"
	
	// TPSL log messages
	LogCheckingTPSLOrders    = "Checking TPSL orders"
	LogTPSLOrderAdded        = "Added TPSL order"
	LogTPSLOrderCanceled     = "TPSL order canceled"
	LogTPOrderTriggered      = "TP order triggered"
	LogSLOrderTriggered      = "SL order triggered"
	LogTPOrderCanceled       = "TP order canceled"
	LogSLOrderCanceled       = "SL order canceled"
	LogTPSLRemovedPartialFill = "TPSL removed due to TP partial fill"
	LogTPCanceledDueToSL     = "TP order canceled due to SL trigger"
	
	// Lock/Unlock log messages
	LogLockedQuoteTokenBuy   = "Locked quoteToken for BUY"
	LogLockedBaseTokenSell   = "Locked baseToken for SELL"
	LogUnlockedQuoteTokenCancel = "Unlocked quoteToken for BUY cancel"
	LogUnlockedBaseTokenCancel  = "Unlocked baseToken for SELL cancel"
	LogCancelAllUnlockedBuy  = "CancelAll unlocked BUY"
	LogCancelAllUnlockedSell = "CancelAll unlocked SELL"
	LogCancelAllTPSL         = "CancelAll TPSL"
	LogCancelAllUnlockedTP   = "CancelAll unlocked TP"
	LogCancelAllUnlockedSL   = "CancelAll unlocked SL"
	
	// Modification log messages
	LogModifyFailed          = "Modify failed"
	LogModifySkipped         = "Modify skipped: no changes"
	LogModifyCompleted       = "Modify completed"
	
	// Engine lifecycle messages
	LogEngineShuttingDown    = "Symbol engine shutting down"
)
