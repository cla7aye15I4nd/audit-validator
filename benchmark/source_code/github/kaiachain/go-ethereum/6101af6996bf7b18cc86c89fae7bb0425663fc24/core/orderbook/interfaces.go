package orderbook

import (
	"errors"

	"github.com/ethereum/go-ethereum/common"
)

// IOrderbookSystem defines the interface for orderbook system implementations
// This allows both v1 and v2 orderbook systems to be used interchangeably
type IOrderbookSystem interface {
	// GetDispatcher returns the DEX dispatcher for handling orderbook operations
	GetDispatcher() Dex

	// Start starts the orderbook system
	Start()

	// Close gracefully shuts down the orderbook system
	Close() error

	// GetLastSnapshotBlock returns the last recovered snapshot block number
	// Returns 0 if no snapshot was recovered
	GetLastSnapshotBlock() uint64
}

// Request is the interface for all orderbook requests
type Request interface {
	StateDB() Locker
	FeeGetter() FeeRetriever
	ResponseChannel() chan Response
	Clone(respCh chan Response) Request
}

// Response is the interface for all orderbook responses
type Response interface {
	Events() []OrderbookEvent
	GetLogData(owner common.Address) ([]*LogData, error)
	SetError(err error)
	Error() error
}

// -- Request Implementations --

// BaseRequest contains common fields for all requests
type baseRequest struct {
	stateDB   Locker
	feeGetter FeeRetriever
	respCh    chan Response
}

func (r *baseRequest) StateDB() Locker                { return r.stateDB }
func (r *baseRequest) FeeGetter() FeeRetriever        { return r.feeGetter }
func (r *baseRequest) ResponseChannel() chan Response { return r.respCh }

// OrderRequest handles order placement
type OrderRequest struct {
	baseRequest
	Order *Order
}

func (r *OrderRequest) Clone(respCh chan Response) Request {
	return &OrderRequest{
		baseRequest: baseRequest{
			stateDB:   r.stateDB,
			feeGetter: r.feeGetter,
			respCh:    respCh,
		},
		Order: r.Order,
	}
}

// CancelRequest handles order cancellation
type CancelRequest struct {
	baseRequest
	OrderID string
}

func (r *CancelRequest) Clone(respCh chan Response) Request {
	return &CancelRequest{
		baseRequest: baseRequest{
			stateDB:   r.stateDB,
			feeGetter: r.feeGetter,
			respCh:    respCh,
		},
		OrderID: r.OrderID,
	}
}

// CancelAllRequest handles cancelling all orders for a user
type CancelAllRequest struct {
	baseRequest
	UserID string
}

func (r *CancelAllRequest) Clone(respCh chan Response) Request {
	return &CancelAllRequest{
		baseRequest: baseRequest{
			stateDB:   r.stateDB,
			feeGetter: r.feeGetter,
			respCh:    respCh,
		},
		UserID: r.UserID,
	}
}

// ModifyRequest handles order modification
type ModifyRequest struct {
	baseRequest
	Args *ModifyArgs
}

func (r *ModifyRequest) Clone(respCh chan Response) Request {
	return &ModifyRequest{
		baseRequest: baseRequest{
			stateDB:   r.stateDB,
			feeGetter: r.feeGetter,
			respCh:    respCh,
		},
		Args: r.Args,
	}
}

// StopOrderRequest handles stop order placement
type StopOrderRequest struct {
	baseRequest
	StopOrder *StopOrder
}

func (r *StopOrderRequest) Clone(respCh chan Response) Request {
	return &StopOrderRequest{
		baseRequest: baseRequest{
			stateDB:   r.stateDB,
			feeGetter: r.feeGetter,
			respCh:    respCh,
		},
		StopOrder: r.StopOrder,
	}
}

// -- Response Implementations --

type LogData struct {
	Address common.Address
	Topics  []common.Hash
	Data    []byte
}

// ErrorResponse is a generic error response for any request
type ErrorResponse struct {
	baseResponse
}

func (r *ErrorResponse) GetLogData(owner common.Address) ([]*LogData, error) {
	if r.err != nil {
		return nil, r.err
	}
	return nil, nil
}

// BaseResponse contains common fields for all responses
type baseResponse struct {
	events []OrderbookEvent
	err    error
}

func (r *baseResponse) Events() []OrderbookEvent { return r.events }
func (r *baseResponse) Error() error             { return r.err }
func (r *baseResponse) SetError(err error)       { r.err = err }

// OrderResponse handles order placement responses
type OrderResponse struct {
	baseResponse
	Trades            []*Trade
	TriggeredOrderIDs OrderIds
}

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

	return logs, nil
}

// CancelResponse handles cancel request responses
type CancelResponse struct {
	baseResponse
	IsCanceled        bool
	CancelledOrderIDs OrderIds
}

func (r *CancelResponse) GetLogData(owner common.Address) ([]*LogData, error) {
	if !r.IsCanceled {
		return nil, errors.New("cancel order is failed")
	}

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

// CancelAllResponse handles cancel all requests responses
type CancelAllResponse struct {
	baseResponse
	CancelledOrderIDs OrderIds
}

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

// ModifyResponse handles modify request responses
type ModifyResponse struct {
	baseResponse
	Trades            []*Trade
	IsModified        bool
	CancelledOrderIDs OrderIds
	TriggeredOrderIDs OrderIds
}

func (r *ModifyResponse) GetLogData(owner common.Address) ([]*LogData, error) {
	if !r.IsModified {
		return nil, errors.New("modify order is failed")
	}

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

	return logs, nil
}

// StopOrderResponse handles stop order responses
type StopOrderResponse struct {
	baseResponse
	Trades            []*Trade
	TriggeredOrderIDs OrderIds
	TriggerAbove      *bool
}

func (r *StopOrderResponse) GetLogData(owner common.Address) ([]*LogData, error) {
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

	// Add trigger above log
	if r.TriggerAbove != nil {
		b := byte(0) // 0 means trigger below
		if *r.TriggerAbove {
			b = byte(1)
		}
		logs = append(logs, &LogData{
			Address: owner,
			Topics:  []common.Hash{TopicTriggerAbove},
			Data:    []byte{b},
		})
	}

	return logs, nil
}

// -- Factory Functions for Requests --

func NewOrderRequest(order *Order, stateDB Locker, feeGetter FeeRetriever) Request {
	return &OrderRequest{
		baseRequest: baseRequest{
			stateDB:   stateDB,
			feeGetter: feeGetter,
			respCh:    make(chan Response, 1),
		},
		Order: order,
	}
}

func NewCancelRequest(orderID string, stateDB Locker, feeGetter FeeRetriever) Request {
	return &CancelRequest{
		baseRequest: baseRequest{
			stateDB:   stateDB,
			feeGetter: feeGetter,
			respCh:    make(chan Response, 1),
		},
		OrderID: orderID,
	}
}

func NewCancelAllRequest(userID string, stateDB Locker, feeGetter FeeRetriever) Request {
	return &CancelAllRequest{
		baseRequest: baseRequest{
			stateDB:   stateDB,
			feeGetter: feeGetter,
			respCh:    make(chan Response, 1),
		},
		UserID: userID,
	}
}

func NewModifyRequest(args *ModifyArgs, stateDB Locker, feeGetter FeeRetriever) Request {
	return &ModifyRequest{
		baseRequest: baseRequest{
			stateDB:   stateDB,
			feeGetter: feeGetter,
			respCh:    make(chan Response, 1),
		},
		Args: args,
	}
}

func NewStopOrderRequest(stopOrder *StopOrder, stateDB Locker, feeGetter FeeRetriever) Request {
	return &StopOrderRequest{
		baseRequest: baseRequest{
			stateDB:   stateDB,
			feeGetter: feeGetter,
			respCh:    make(chan Response, 1),
		},
		StopOrder: stopOrder,
	}
}

// -- Factory Functions for Responses --

func NewOrderResponse(trades []*Trade, triggered []string, events []OrderbookEvent) Response {
	return &OrderResponse{
		baseResponse: baseResponse{
			events: events,
		},
		Trades:            trades,
		TriggeredOrderIDs: triggered,
	}
}

func NewCancelResponse(isCanceled bool, cancelledIDs []string, events []OrderbookEvent) Response {
	return &CancelResponse{
		baseResponse: baseResponse{
			events: events,
		},
		IsCanceled:        isCanceled,
		CancelledOrderIDs: cancelledIDs,
	}
}

func NewCancelAllResponse(orderIDs []string, events []OrderbookEvent) Response {
	return &CancelAllResponse{
		baseResponse: baseResponse{
			events: events,
		},
		CancelledOrderIDs: orderIDs,
	}
}

func NewModifyResponse(trades []*Trade, triggered []string, cancelledIDs []string, modified bool, events []OrderbookEvent) Response {
	return &ModifyResponse{
		baseResponse: baseResponse{
			events: events,
		},
		Trades:            trades,
		IsModified:        modified,
		CancelledOrderIDs: cancelledIDs,
		TriggeredOrderIDs: triggered,
	}
}

func NewStopOrderResponse(trades []*Trade, triggered []string, triggerAbove *bool, events []OrderbookEvent) Response {
	return &StopOrderResponse{
		baseResponse: baseResponse{
			events: events,
		},
		Trades:            trades,
		TriggeredOrderIDs: triggered,
		TriggerAbove:      triggerAbove,
	}
}

// NewErrorResponse creates a generic error response
func NewErrorResponse(err error) Response {
	return &ErrorResponse{
		baseResponse: baseResponse{
			err: err,
		},
	}
}
