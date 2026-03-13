# Order Pipeline Flow Documentation

## Order States

Orders can be in the following states during their lifecycle:

```
1. NEW         - Order just created, not yet processed
2. VALIDATING  - Order being validated
3. PENDING     - Order validated, awaiting matching
4. MATCHING    - Order actively being matched
5. PARTIAL     - Order partially filled, remaining in queue
6. FILLED      - Order completely filled
7. QUEUED      - Order in orderbook queue awaiting match
8. CANCELED    - Order canceled by user
9. REJECTED    - Order rejected (validation failed, insufficient balance, etc.)
10. TRIGGERED  - Conditional order triggered (TPSL/Stop)
```

## Pipeline Stages Overview

The 7-stage pipeline processes orders in the following sequence:

1. **ValidationStage** - Validates order parameters and permissions
2. **LockingStage** - Locks assets and acquires state mutex
3. **MatchingStage** - Matches order against opposite queue
4. **ConditionalCheckStage** - Checks and triggers TPSL/Stop orders
5. **SettlementStage** - Settles trades and updates balances
6. **QueueUpdateStage** - Adds unfilled orders to queue
7. **EventGenerationStage** - Generates events and releases mutex

## Action Flow Diagrams

### 1. Regular Order (without TPSL)

```
State: NEW
│
├─→ ValidationStage
│   State: VALIDATING
│   - Check order fields
│   - Verify permissions
│
├─→ LockingStage  
│   State: PENDING
│   - Lock state mutex
│   - Lock user assets (quote for BUY, base for SELL)
│
├─→ MatchingStage
│   State: MATCHING
│   - Match against opposite queue
│   - Generate trades
│   - Update order quantity
│
├─→ ConditionalCheckStage
│   - Check if trades triggered any TPSL orders
│   - Collect triggered orders for later processing
│
├─→ SettlementStage
│   - Process trades
│   - Update balances
│   - Collect fees
│   State: FILLED (if quantity = 0) or PARTIAL
│
├─→ QueueUpdateStage
│   State: QUEUED (if LIMIT && quantity > 0)
│   - Add to buy/sell queue
│   - Mark price level dirty
│
└─→ EventGenerationStage
    - Generate OrderAddedEvent (if queued)
    - Generate TradeExecutedEvent (per trade)
    - Generate OrderRemovedEvent (if filled)
    - Unlock state mutex
```

### 2. Order with TPSL

```
State: NEW (with TPSL attached)
│
├─→ [Same as Regular Order through MatchingStage]
│
├─→ ConditionalCheckStage
│   - If order FILLED:
│     * Activate TPSL orders
│     * Add to conditional manager
│   - Check price triggers
│
├─→ SettlementStage
│   State: FILLED
│   - TPSL orders now PENDING
│
├─→ QueueUpdateStage
│   - Main order not queued (filled)
│
└─→ EventGenerationStage
    - Generate TPSLOrderAddedEvent
    - Other standard events
```

### 3. Stop Order

```
State: NEW (Stop order)
│
├─→ Check trigger price immediately
│
├─→ If should trigger now:
│   └─→ Process as regular order (full pipeline)
│
└─→ If not triggered:
    - Add to conditional manager
    - State: PENDING
    - Generate TPSLOrderAddedEvent
    - Wait for price trigger
```

### 4. Cancel Order

```
Current State: QUEUED or PARTIAL
│
├─→ ValidationStage
│   - Verify order exists
│   - Check ownership
│
├─→ LockingStage
│   - Lock state mutex
│
├─→ Cancel Logic (not full pipeline)
│   - Mark order.IsCanceled = true
│   - Remove from queue
│   - Unlock assets
│   - Check for attached TPSL
│   State: CANCELED
│
└─→ EventGenerationStage
    - Generate OrderRemovedEvent
    - Generate TPSLOrderRemovedEvent (if had TPSL)
    - Unlock state mutex
```

### 5. Cancel All Orders

```
User's orders: [QUEUED, PARTIAL, PENDING (TPSL)]
│
├─→ ValidationStage
│   - Verify user
│
├─→ LockingStage
│   - Lock state mutex
│
├─→ Batch Cancel Logic
│   - Iterate buy queue → cancel user's orders
│   - Iterate sell queue → cancel user's orders
│   - Cancel all conditional orders
│   - Unlock all assets
│   All orders → State: CANCELED
│
└─→ EventGenerationStage
    - Generate OrderRemovedEvent (per order)
    - Generate TPSLOrderRemovedEvent (per conditional)
    - Unlock state mutex
```

### 6. Modify Order

```
Current State: QUEUED or PARTIAL
│
├─→ ValidationStage
│   - Verify order exists
│   - Check ownership
│   - Validate new price/quantity
│
├─→ Cancel existing order
│   State: CANCELED
│
├─→ Create new order with modifications
│   State: NEW
│
└─→ Process new order (full pipeline)
    State: Based on matching result
```

## Triggered Order Processing

When ConditionalCheckStage detects triggered orders:

```
TPSL Order State: PENDING
│
├─→ Price crosses trigger
│   State: TRIGGERED
│
├─→ Add to triggered list
│
└─→ After main pipeline completes:
    └─→ Process each triggered order
        - Full pipeline execution
        - State transitions as regular order
```

## State Transitions Summary

```
NEW → VALIDATING → PENDING → MATCHING → {FILLED, PARTIAL, QUEUED}
                                     ↓
                                  CANCELED (via cancel)
                            
PENDING (TPSL) → TRIGGERED → [Regular order flow]

QUEUED/PARTIAL → CANCELED (via cancel)
               → MATCHING (when matched)
               → FILLED (when fully matched)
```

## Pipeline Suitability Analysis

### Current Pipeline Strengths:
- ✅ Handles regular orders (limit/market)
- ✅ Supports TPSL attachment and activation
- ✅ Processes stop orders
- ✅ Clear separation of concerns

### Current Pipeline Limitations:

1. **Cancel/CancelAll** - Don't use full pipeline, only need:
   - ValidationStage
   - LockingStage (for mutex)
   - Custom cancel logic
   - EventGenerationStage

2. **Modify** - Hybrid approach:
   - Uses cancel logic + full pipeline for new order
   - Could benefit from dedicated ModifyStage

3. **Stop Order** - Special handling:
   - Immediate trigger check happens outside pipeline
   - Only uses pipeline if triggered immediately

## Recommendations

1. **Create specialized pipelines:**
   ```go
   - OrderPipeline (7 stages) - for orders
   - CancelPipeline (3 stages) - for cancellations
   - ModifyPipeline (custom) - for modifications
   ```

2. **Or add conditional stage execution:**
   ```go
   type Stage interface {
       ShouldExecute(ctx *OrderContext) bool
       Process(ctx *OrderContext) error
       Rollback(ctx *OrderContext) error
   }
   ```

3. **Add action type to context:**
   ```go
   type OrderContext struct {
       ActionType ActionType // ORDER, CANCEL, MODIFY, etc.
       // ... existing fields
   }
   ```

This would allow stages to skip themselves based on action type.