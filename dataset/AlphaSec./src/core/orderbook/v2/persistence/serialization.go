package persistence

import (
	"encoding/json"
	"fmt"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/interfaces"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
)

// SerializedRequest represents a serialized request with its type information
type SerializedRequest struct {
	Type        string          `json:"type"`
	RequestData json.RawMessage `json:"request_data"`
	BlockNumber uint64          `json:"block_number"`
}

// RequestSerializer handles serialization and deserialization of requests
type RequestSerializer struct{}

// NewRequestSerializer creates a new request serializer
func NewRequestSerializer() *RequestSerializer {
	return &RequestSerializer{}
}

// SerializeRequest serializes an interfaces.Request to bytes
func (s *RequestSerializer) SerializeRequest(req interfaces.Request, blockNumber uint64) ([]byte, error) {
	if req == nil {
		return nil, fmt.Errorf("request cannot be nil")
	}

	// Determine request type and serialize accordingly
	var requestType string
	var requestData interface{}

	switch r := req.(type) {
	case *interfaces.OrderRequest:
		requestType = "ORDER"
		requestData = struct {
			Order *types.Order `json:"order"`
		}{
			Order: r.Order,
		}

	case *interfaces.CancelRequest:
		requestType = "CANCEL"
		requestData = struct {
			OrderID string `json:"order_id"`
		}{
			OrderID: r.OrderID,
		}

	case *interfaces.CancelAllRequest:
		requestType = "CANCEL_ALL"
		requestData = struct {
			UserID string `json:"user_id"`
		}{
			UserID: r.UserID,
		}

	case *interfaces.ModifyRequest:
		requestType = "MODIFY"
		requestData = struct {
			ModifyArgs *types.ModifyArgs `json:"modify_args"`
		}{
			ModifyArgs: r.ModifyArgs,
		}

	case *interfaces.StopOrderRequest:
		requestType = "STOP_ORDER"
		requestData = struct {
			StopOrder *types.StopOrder `json:"stop_order"`
		}{
			StopOrder: r.StopOrder,
		}

	default:
		return nil, fmt.Errorf("unknown request type: %T", req)
	}

	// Serialize request data
	reqDataBytes, err := json.Marshal(requestData)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize request data: %w", err)
	}

	// Create serialized request
	serialized := SerializedRequest{
		Type:         requestType,
		RequestData:  reqDataBytes,
		BlockNumber:  blockNumber,
	}

	// Marshal to JSON
	return json.Marshal(serialized)
}

// DeserializeRequest deserializes bytes back to an interfaces.Request
// Note: StateDB and FeeGetter must be provided separately as they cannot be serialized
func (s *RequestSerializer) DeserializeRequest(data []byte, stateDB types.StateDB, feeGetter types.FeeRetriever) (interfaces.Request, uint64, error) {
	var serialized SerializedRequest
	if err := json.Unmarshal(data, &serialized); err != nil {
		return nil, 0, fmt.Errorf("failed to unmarshal serialized request: %w", err)
	}

	var request interfaces.Request

	switch serialized.Type {
	case "ORDER":
		var orderData struct {
			Order *types.Order `json:"order"`
		}
		if err := json.Unmarshal(serialized.RequestData, &orderData); err != nil {
			return nil, 0, fmt.Errorf("failed to unmarshal order data: %w", err)
		}
		request = interfaces.NewOrderRequest(orderData.Order, stateDB, feeGetter)

	case "CANCEL":
		var cancelData struct {
			OrderID string `json:"order_id"`
		}
		if err := json.Unmarshal(serialized.RequestData, &cancelData); err != nil {
			return nil, 0, fmt.Errorf("failed to unmarshal cancel data: %w", err)
		}
		request = interfaces.NewCancelRequest(cancelData.OrderID, stateDB, feeGetter)

	case "CANCEL_ALL":
		var cancelAllData struct {
			UserID string `json:"user_id"`
		}
		if err := json.Unmarshal(serialized.RequestData, &cancelAllData); err != nil {
			return nil, 0, fmt.Errorf("failed to unmarshal cancel all data: %w", err)
		}
		request = interfaces.NewCancelAllRequest(cancelAllData.UserID, stateDB, feeGetter)

	case "MODIFY":
		var modifyData struct {
			ModifyArgs *types.ModifyArgs `json:"modify_args"`
		}
		if err := json.Unmarshal(serialized.RequestData, &modifyData); err != nil {
			return nil, 0, fmt.Errorf("failed to unmarshal modify data: %w", err)
		}
		request = interfaces.NewModifyRequest(modifyData.ModifyArgs, stateDB, feeGetter)

	case "STOP_ORDER":
		var stopOrderData struct {
			StopOrder *types.StopOrder `json:"stop_order"`
		}
		if err := json.Unmarshal(serialized.RequestData, &stopOrderData); err != nil {
			return nil, 0, fmt.Errorf("failed to unmarshal stop order data: %w", err)
		}
		request = interfaces.NewStopOrderRequest(stopOrderData.StopOrder, stateDB, feeGetter)

	default:
		return nil, 0, fmt.Errorf("unknown request type: %s", serialized.Type)
	}

	return request, serialized.BlockNumber, nil
}

// SerializeResponse serializes an interfaces.Response to bytes
func (s *RequestSerializer) SerializeResponse(resp interfaces.Response) ([]byte, error) {
	if resp == nil {
		return nil, fmt.Errorf("response cannot be nil")
	}

	// Create a generic response structure
	responseData := struct {
		Error string      `json:"error,omitempty"`
		Data  interface{} `json:"data,omitempty"`
	}{}

	if resp.Error() != nil {
		responseData.Error = resp.Error().Error()
	}

	// Add type-specific data
	switch r := resp.(type) {
	case *interfaces.OrderResponse:
		responseData.Data = struct {
			Trades            []*types.Trade `json:"trades"`
			TriggeredOrderIDs types.OrderIDs `json:"triggered_order_ids"`
		}{
			Trades:            r.Trades,
			TriggeredOrderIDs: r.TriggeredOrderIDs,
		}

	case *interfaces.CancelResponse:
		responseData.Data = struct {
			CancelledOrderIDs types.OrderIDs `json:"cancelled_order_ids"`
		}{
			CancelledOrderIDs: r.CancelledOrderIDs,
		}

	case *interfaces.CancelAllResponse:
		responseData.Data = struct {
			CancelledOrderIDs types.OrderIDs `json:"cancelled_order_ids"`
		}{
			CancelledOrderIDs: r.CancelledOrderIDs,
		}

	case *interfaces.ModifyResponse:
		responseData.Data = struct {
			Trades            []*types.Trade `json:"trades"`
			CancelledOrderIDs types.OrderIDs `json:"cancelled_order_ids"`
			TriggeredOrderIDs types.OrderIDs `json:"triggered_order_ids"`
		}{
			Trades:            r.Trades,
			CancelledOrderIDs: r.CancelledOrderIDs,
			TriggeredOrderIDs: r.TriggeredOrderIDs,
		}

	case *interfaces.StopOrderResponse:
		triggerAbove := r.TriggerAbove // Copy the bool value
		responseData.Data = struct {
			Trades            []*types.Trade `json:"trades"`
			TriggeredOrderIDs types.OrderIDs `json:"triggered_order_ids"`
			TriggerAbove      *bool          `json:"trigger_above,omitempty"`
		}{
			Trades:            r.Trades,
			TriggeredOrderIDs: r.TriggeredOrderIDs,
			TriggerAbove:      &triggerAbove,
		}
	}

	return json.Marshal(responseData)
}
