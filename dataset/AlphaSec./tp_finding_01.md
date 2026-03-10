# Missing Ownership Validation in Order Cancellation


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `af456cf0-7d25-11f0-908b-c3b3b024b0ed` |
| Commit | `6101af6996bf7b18cc86c89fae7bb0425663fc24` |

## Location

- **Local path:** `./src/core/types/tx_input.go`
- **ACC link:** https://acc.audit.certikpowered.info/project/af456cf0-7d25-11f0-908b-c3b3b024b0ed/source?file=$/github/kaiachain/go-ethereum/6101af6996bf7b18cc86c89fae7bb0425663fc24/core/types/tx_input.go
- **Lines:** 572–572

## Description

`CancelContext.validateBalance()` only checks for the existence of the order and does not verify that the order belongs to the provided L1Owner. There is no subsequent ownership enforcement in `dispatcher.handleCancelRequest` or `engine.CancelOrder`, so any account can cancel another user's order by supplying its orderId.

## Recommendation

Fetch the order by ID and verify order.UserID matches L1Owner before returning success.

## Vulnerable Code

```
Side:       orderbook.Side(t.Side),
		Price:      uint256.MustFromBig(t.Price),
		OrigQty:    origQty,  // Use converted quantity
		Quantity:   quantity, // Use converted quantity
		Timestamp:  time.Now().UnixNano(),
		OrderType:  orderbook.OrderType(t.OrderType),
		OrderMode:  orderMode, // Use converted mode (BASE_MODE for converted limit orders)
		IsCanceled: false,
		TPSL:       tpsl,
	}
}

type CancelContext struct {
	L1Owner common.Address `json:"l1owner"`
	OrderId common.Hash    `json:"orderId"` // typically tx hash or unique order hash
}

func (t *CancelContext) command() byte                  { return DexCommandCancel }
func (t *CancelContext) from() common.Address           { return t.L1Owner }
func (t *CancelContext) copy() DexCommandData           { return &CancelContext{t.L1Owner, t.OrderId} }
func (t *CancelContext) Serialize() ([]byte, error)     { return encode(t) }
func (t *CancelContext) Deserialize(input []byte) error { return json.Unmarshal(input, t) }
func (t *CancelContext) validate(sender common.Address, statedb BalanceGetter, orderbook orderbook.Dex, checker MarketChecker) error {
	if t.L1Owner == (common.Address{}) {
		return errors.New("from address is zero")
	}
	return t.validateBalance(statedb, orderbook)
}

func (t *CancelContext) validateBalance(statedb BalanceGetter, orderbook orderbook.Dex) error {
	orderId := t.OrderId

	// TODO-Orderbook: This is a temporary fix for TPSL order cancellation
	// TPSL orders (TP/SL) have predictable IDs (original order ID + 1 or 2 in last byte)
	// Check if this might be a conditional order by looking for the original order
	// This should be properly refactored to have a unified order validation system
	originalOrderId := orderId
	originalOrderId[31] = orderId[31] - 1  // Check if this is a TP order (original + 1)
	if _, hasOrder := orderbook.GetOrder(originalOrderId.Hex()); hasOrder {
		log.Info("CancelContext: Skipping validation for potential TP order", "orderId", orderId.Hex(), "originalOrderId", originalOrderId.Hex())
		return nil  // Original order exists, this might be a TP order - skip validation
	}
	
	originalOrderId[31] = orderId[31] - 2  // Check if this is a SL order (original + 2)
	if _, hasOrder := orderbook.GetOrder(originalOrderId.Hex()); hasOrder {
		log.Info("CancelContext: Skipping validation for potential SL order", "orderId", orderId.Hex(), "originalOrderId", originalOrderId.Hex())
		return nil  // Original order exists, this might be a SL order - skip validation
	}
	
	_, hasStopOrder := orderbook.GetStopOrder(orderId.Hex())
	if hasStopOrder {
		log.Info("CancelContext found stop order", "orderId", orderId)
		// TODO-Orderbook: validate stop order lock/unlock balance
		return nil
	}

	order, hasOrder := orderbook.GetOrder(orderId.Hex())
	if !hasOrder {
		log.Error("Order not found", "orderId", orderId)
		return fmt.Errorf("order not found: %v", orderId)
```
