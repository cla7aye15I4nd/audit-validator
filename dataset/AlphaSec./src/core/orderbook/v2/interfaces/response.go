package interfaces

import (
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/crypto"
)

// Topic constants for event logging (copied from v1 to avoid import cycle)
var (
	TopicTrades        = crypto.Keccak256Hash([]byte("Trades"))             // 0xd37cc1c23d72518afd1e7a67fe42c7d9c5db40d646c2d5dfc324683baede635e
	TopicCancel        = crypto.Keccak256Hash([]byte("Cancel"))             // 0x8c11276ab4208c28a9c53122199d5bcecbc5041a008b5263db3cc3c06411cc5b
	TopicCanceledIds   = crypto.Keccak256Hash([]byte("CanceledIds"))        // 0x46fbbe6e6251d0d9a80a52b6f14e2d466a9aca2578e5103c192e66ccc6786f94
	TopicTriggeredIds  = crypto.Keccak256Hash([]byte("TriggeredIds"))       // 0xc9cb97f5d3b4cf5158af621cf9753fcbc4ef2c46efa310cb3083676e6f8f6fee
	TopicTriggerAbove  = crypto.Keccak256Hash([]byte("TopicTriggerAbove"))  // 0xd5bfcf6006131052eae3f479eb1da700d54890149ccfe08214f53596148bd59a
	TopicFailedOrders  = crypto.Keccak256Hash([]byte("FailedOrders"))       // 0x99bede8559a7cac1d64053532a0e2ad472cad6c0b9cb34daee489053d2490d4f
	TopicCompletedIds  = crypto.Keccak256Hash([]byte("CompletedIds"))       // 0x4e1406ebc2f1e4058895e79817404c4848261e665d51d5c0f62a52a9af0884e9
)

// Response is the interface for all orderbook responses
type Response interface {
	// Error returns any error that occurred during processing
	Error() error

	// GetLogData returns receipt log data to write the result
	GetLogData(owner common.Address) ([]*LogData, error)
}

type LogData struct {
	Address common.Address
	Topics  []common.Hash
	Data    []byte
}

// ResponseType identifies the type of response
type ResponseType int

const (
	OrderResponseType ResponseType = iota
	CancelResponseType
	CancelAllResponseType
	ModifyResponseType
	ErrorResponseType
)

// baseResponse contains common fields for all responses
type baseResponse struct {
	success bool
	err     error
}

func (r *baseResponse) Error() error { return r.err }

// GetLogData returns empty log data for base response
func (r *baseResponse) GetLogData(owner common.Address) ([]*LogData, error) {
	if r.err != nil {
		return nil, r.err
	}
	return nil, nil
}

// OrderResponse represents the response to an order placement
type OrderResponse struct {
	baseResponse
	Order             *types.Order
	OrderStatus       types.OrderStatus
	Trades            []*types.Trade
	OrderID           string
	TriggeredOrderIDs types.OrderIDs       // IDs of orders triggered by this order
	FailedOrders      types.FailedOrders   // Orders that failed during processing
	CompletedOrderIDs types.OrderIDs       // IDs of orders that were completed (filled or cancelled)
}

func NewOrderResponse(order *types.Order, trades []*types.Trade, triggered types.OrderIDs) *OrderResponse {
	return &OrderResponse{
		baseResponse:      baseResponse{success: true},
		Order:             order,
		Trades:            trades,
		OrderID:           string(order.OrderID),
		TriggeredOrderIDs: triggered,
		FailedOrders:      types.FailedOrders{}, // Initialize empty
		CompletedOrderIDs: types.OrderIDs{},      // Initialize empty
	}
}

// NewOrderResponseWithFailures creates an order response with failed orders tracking
func NewOrderResponseWithFailures(order *types.Order, trades []*types.Trade, triggered types.OrderIDs, failed types.FailedOrders) *OrderResponse {
	return &OrderResponse{
		baseResponse:      baseResponse{success: true},
		Order:             order,
		Trades:            trades,
		OrderID:           string(order.OrderID),
		TriggeredOrderIDs: triggered,
		FailedOrders:      failed,
		CompletedOrderIDs: types.OrderIDs{}, // Initialize empty
	}
}

func (r *OrderResponse) Type() ResponseType { return OrderResponseType }

func (r *OrderResponse) GetLogData(owner common.Address) ([]*LogData, error) {
	var logs []*LogData

	// Add trade logs
	for _, trade := range r.Trades {
		bytes, err := trade.Serialize()
		if err != nil {
			return nil, err
		}
		logs = append(logs, &LogData{
			Address: owner,
			Topics:  []common.Hash{TopicTrades},
			Data:    bytes,
		})
	}

	// Add triggered order IDs log
	if len(r.TriggeredOrderIDs) > 0 {
		bytes, err := r.TriggeredOrderIDs.Serialize()
		if err != nil {
			return nil, err
		}
		logs = append(logs, &LogData{
			Address: owner,
			Topics:  []common.Hash{TopicTriggeredIds},
			Data:    bytes,
		})
	}

	// Add failed orders log
	if len(r.FailedOrders) > 0 {
		bytes, err := r.FailedOrders.Serialize()
		if err != nil {
			return nil, err
		}
		logs = append(logs, &LogData{
			Address: owner,
			Topics:  []common.Hash{TopicFailedOrders},
			Data:    bytes,
		})
	}

	// Add completed order IDs log
	if len(r.CompletedOrderIDs) > 0 {
		bytes, err := r.CompletedOrderIDs.Serialize()
		if err != nil {
			return nil, err
		}
		logs = append(logs, &LogData{
			Address: owner,
			Topics:  []common.Hash{TopicCompletedIds},
			Data:    bytes,
		})
	}

	return logs, nil
}

// CancelResponse represents the response to a cancel request
type CancelResponse struct {
	baseResponse
	CancelledOrderIDs types.OrderIDs
}

func NewCancelResponse(cancelledIDs types.OrderIDs) *CancelResponse {
	return &CancelResponse{
		baseResponse:      baseResponse{success: true},
		CancelledOrderIDs: cancelledIDs,
	}
}

func (r *CancelResponse) Type() ResponseType { return CancelResponseType }

func (r *CancelResponse) GetLogData(owner common.Address) ([]*LogData, error) {
	var logs []*LogData

	// Add cancelled order IDs log
	if len(r.CancelledOrderIDs) > 0 {
		bytes, err := r.CancelledOrderIDs.Serialize()
		if err != nil {
			return nil, err
		}
		logs = append(logs, &LogData{
			Address: owner,
			Topics:  []common.Hash{TopicCanceledIds},
			Data:    bytes,
		})
	}

	return logs, nil
}

// CancelAllResponse represents the response to a cancel all request
type CancelAllResponse struct {
	baseResponse
	CancelledOrderIDs types.OrderIDs
}

func NewCancelAllResponse(orderIDs types.OrderIDs) *CancelAllResponse {
	return &CancelAllResponse{
		baseResponse:      baseResponse{success: true},
		CancelledOrderIDs: orderIDs,
	}
}

func (r *CancelAllResponse) Type() ResponseType { return CancelAllResponseType }

func (r *CancelAllResponse) GetLogData(owner common.Address) ([]*LogData, error) {
	var logs []*LogData

	// Add cancelled order IDs log
	if len(r.CancelledOrderIDs) > 0 {
		bytes, err := r.CancelledOrderIDs.Serialize()
		if err != nil {
			return nil, err
		}
		logs = append(logs, &LogData{
			Address: owner,
			Topics:  []common.Hash{TopicCanceledIds},
			Data:    bytes,
		})
	}

	return logs, nil
}

// ModifyResponse represents the response to a modify request
type ModifyResponse struct {
	baseResponse
	Trades            []*types.Trade // If modification triggered immediate trades
	CancelledOrderIDs types.OrderIDs
	TriggeredOrderIDs types.OrderIDs
	CompletedOrderIDs types.OrderIDs // IDs of orders that were completed (filled)
}

func NewModifyResponse(trades []*types.Trade, triggeredIDs, cancelledIDs types.OrderIDs) *ModifyResponse {
	return &ModifyResponse{
		baseResponse:      baseResponse{success: true},
		Trades:            trades,
		CancelledOrderIDs: cancelledIDs,
		TriggeredOrderIDs: triggeredIDs,
		CompletedOrderIDs: types.OrderIDs{}, // Initialize empty
	}
}

func (r *ModifyResponse) Type() ResponseType { return ModifyResponseType }

func (r *ModifyResponse) GetLogData(owner common.Address) ([]*LogData, error) {
	var logs []*LogData

	// Add trade logs
	for _, trade := range r.Trades {
		bytes, err := trade.Serialize()
		if err != nil {
			return nil, err
		}
		logs = append(logs, &LogData{
			Address: owner,
			Topics:  []common.Hash{TopicTrades},
			Data:    bytes,
		})
	}

	// Add cancelled order IDs log
	if len(r.CancelledOrderIDs) > 0 {
		bytes, err := r.CancelledOrderIDs.Serialize()
		if err != nil {
			return nil, err
		}
		logs = append(logs, &LogData{
			Address: owner,
			Topics:  []common.Hash{TopicCanceledIds},
			Data:    bytes,
		})
	}

	// Add triggered order IDs log
	if len(r.TriggeredOrderIDs) > 0 {
		bytes, err := r.TriggeredOrderIDs.Serialize()
		if err != nil {
			return nil, err
		}
		logs = append(logs, &LogData{
			Address: owner,
			Topics:  []common.Hash{TopicTriggeredIds},
			Data:    bytes,
		})
	}

	// Add completed order IDs log
	if len(r.CompletedOrderIDs) > 0 {
		bytes, err := r.CompletedOrderIDs.Serialize()
		if err != nil {
			return nil, err
		}
		logs = append(logs, &LogData{
			Address: owner,
			Topics:  []common.Hash{TopicCompletedIds},
			Data:    bytes,
		})
	}

	return logs, nil
}

// StopOrderResponse represents the response to an stop order placement
type StopOrderResponse struct {
	baseResponse
	Order             *types.Order
	OrderStatus       types.OrderStatus
	Trades            []*types.Trade
	OrderID           string
	TriggeredOrderIDs types.OrderIDs
	TriggerAbove      bool
}

func NewStopOrderResponse(triggerAbove bool) *StopOrderResponse {
	return &StopOrderResponse{
		baseResponse: baseResponse{success: true},
		TriggerAbove: triggerAbove, // Will be set based on stop order type
	}
}

func (r *StopOrderResponse) Type() ResponseType { return OrderResponseType }

func (r *StopOrderResponse) GetLogData(owner common.Address) ([]*LogData, error) {
	var logs []*LogData

	b := byte(0) // 0 means trigger below
	if r.TriggerAbove {
		b = byte(1)
	}
	logs = append(logs, &LogData{
		Address: owner,
		Topics:  []common.Hash{TopicTriggerAbove},
		Data:    []byte{b},
	})

	return logs, nil
}

// ErrorResponse represents an error response
type ErrorResponse struct {
	baseResponse
	Message string
}

func NewErrorResponse(err error) *ErrorResponse {
	msg := ""
	if err != nil {
		msg = err.Error()
	}
	return &ErrorResponse{
		baseResponse: baseResponse{
			success: false,
			err:     err,
		},
		Message: msg,
	}
}

func (r *ErrorResponse) Type() ResponseType { return ErrorResponseType }

func (r *ErrorResponse) GetLogData(owner common.Address) ([]*LogData, error) {
	if r.err != nil {
		return nil, r.err
	}
	return nil, nil
}
