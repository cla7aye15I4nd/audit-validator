package interfaces

import (
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
)

// Request is the interface for all orderbook requests
// This aligns with v1's async channel-based pattern
type Request interface {
	// StateDB returns the state database for this request
	StateDB() types.StateDB

	// FeeGetter returns the fee retriever for this request
	FeeGetter() types.FeeRetriever

	// ResponseChannel returns the channel for sending responses
	ResponseChannel() chan Response
}

// baseRequest contains common fields for all requests
type baseRequest struct {
	stateDB   types.StateDB
	feeGetter types.FeeRetriever
	respCh    chan Response
}

func (r *baseRequest) StateDB() types.StateDB         { return r.stateDB }
func (r *baseRequest) FeeGetter() types.FeeRetriever  { return r.feeGetter }
func (r *baseRequest) ResponseChannel() chan Response { return r.respCh }

// OrderRequest represents a request to place an order
type OrderRequest struct {
	baseRequest
	Order *types.Order
}

func NewOrderRequest(order *types.Order, stateDB types.StateDB, feeGetter types.FeeRetriever) *OrderRequest {
	return &OrderRequest{
		baseRequest: baseRequest{
			stateDB:   stateDB,
			feeGetter: feeGetter,
			respCh:    make(chan Response, 1),
		},
		Order: order,
	}
}

// CancelRequest represents a request to cancel an order
type CancelRequest struct {
	baseRequest
	OrderID string
}

func NewCancelRequest(orderID string, stateDB types.StateDB, feeGetter types.FeeRetriever) *CancelRequest {
	return &CancelRequest{
		baseRequest: baseRequest{
			stateDB:   stateDB,
			feeGetter: feeGetter,
			respCh:    make(chan Response, 1),
		},
		OrderID: orderID,
	}
}

// CancelAllRequest represents a request to cancel all orders for a user
type CancelAllRequest struct {
	baseRequest
	UserID string
}

func NewCancelAllRequest(userID string, stateDB types.StateDB, feeGetter types.FeeRetriever) *CancelAllRequest {
	return &CancelAllRequest{
		baseRequest: baseRequest{
			stateDB:   stateDB,
			feeGetter: feeGetter,
			respCh:    make(chan Response, 1),
		},
		UserID: userID,
	}
}

// ModifyRequest represents a request to modify an existing order
type ModifyRequest struct {
	baseRequest
	*types.ModifyArgs
}

func NewModifyRequest(args *types.ModifyArgs, stateDB types.StateDB, feeGetter types.FeeRetriever) *ModifyRequest {
	return &ModifyRequest{
		baseRequest: baseRequest{
			stateDB:   stateDB,
			feeGetter: feeGetter,
			respCh:    make(chan Response, 1),
		},
		ModifyArgs: args,
	}
}

// StopOrderRequest represents a request to place a stop order
type StopOrderRequest struct {
	baseRequest
	StopOrder *types.StopOrder
}

func NewStopOrderRequest(stopOrder *types.StopOrder, stateDB types.StateDB, feeGetter types.FeeRetriever) *StopOrderRequest {
	return &StopOrderRequest{
		baseRequest: baseRequest{
			stateDB:   stateDB,
			feeGetter: feeGetter,
			respCh:    make(chan Response, 1),
		},
		StopOrder: stopOrder,
	}
}
