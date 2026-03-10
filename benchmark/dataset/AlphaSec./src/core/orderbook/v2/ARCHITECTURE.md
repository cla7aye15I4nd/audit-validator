# Orderbook V2 Architecture

## Design Principles
1. **Clear Dependencies** - Unidirectional dependency flow
2. **Interface-First** - Define contracts before implementations
3. **Testability** - Each package independently testable
4. **No Circular Dependencies** - Strict layering

## Dependency Hierarchy (Top to Bottom)

```
Level 0: Foundation (No Dependencies)
├── types/       - Pure data structures
└── interfaces/  - Contract definitions (Request/Response interfaces)

Level 1: Core Logic (Depends on Level 0)
├── matching/    - Order matching algorithms
├── queue/       - Order queue management
└── book/        - Order book structures

Level 2: Business Logic (Depends on Level 0-1)
├── balance/     - Balance management and locking
├── engine/      - Symbol engine orchestration
├── conditional/ - TPSL/Stop order logic
└── pipeline/    - Processing pipelines

Level 3: Persistence (Depends on Level 0-2)
├── storage/     - Persistence layer
└── snapshot/    - State snapshots

Level 4: External Interface (Depends on Level 0-3)
├── api/         - External API
├── dispatcher/  - Async request routing with channel-based pattern
└── system/      - System orchestration and lifecycle management
```

## Package Definitions

### Level 0: Foundation

#### `types/` - Pure Data Structures
```go
// No external dependencies, only stdlib
- Order
- Trade  
- OrderID, UserID, Symbol
- Price, Quantity (uint256 wrappers)
- OrderType, OrderSide, OrderStatus enums
- OrderMode (BASE_MODE, QUOTE_MODE)
```

#### `interfaces/` - Contracts
```go
// Depends only on types
// Core business logic interfaces
- OrderMatcher
- OrderQueue
- OrderBook
- StorageBackend

- ConditionalOrderManager

// Request/Response interfaces (NEW)
- Request (with concrete implementations)
  - OrderRequest
  - CancelRequest
  - CancelAllRequest
  - ModifyRequest
  - StopOrderRequest
  - TPSLOrderRequest
- Response (with concrete implementations)
  - OrderResponse
  - CancelResponse
  - CancelAllResponse
  - ModifyResponse
  - ErrorResponse
```


### Level 1: Core Logic

#### `matching/` - Matching Algorithms
```go
// Implements: OrderMatcher interface
// Depends on: types, interfaces
- PriceTimePriority
- ProRata (future)
- Auction (future)
```

#### `queue/` - Queue Management
```go
// Implements: OrderQueue interface
// Depends on: types, interfaces
- BuyQueue (max heap)
- SellQueue (min heap)
- QueueManager
```

#### `book/` - Order Book Structures
```go
// Implements: OrderBook interface
// Depends on: types, interfaces, queue
- OrderBook (full orderbook with state management)
  - Buy/Sell queues
  - Price level aggregation
  - User order tracking
  - Current price & last trade time
  - Depth calculation
```

### Level 2: Business Logic

#### `balance/` - Balance Management
```go
// Depends on: types, interfaces
- BalanceManager (user balance tracking and locking)
  - Lock balance for order placement
  - Unlock on cancellation/expiry
  - Partial unlock on partial fills
  - Multi-token support (base/quote)
  - Atomic operations for consistency
```

#### `engine/` - Orchestration
```go
// Depends on: types, interfaces, book, matching, conditional
- SymbolEngine (per-symbol processing)
  - Direct OrderBook management
  - Pipeline stages (commented for future extraction)
  - Order validation & matching
  - Order processing
  - Conditional order integration
```

#### `conditional/` - Conditional Orders
```go
// Depends on: types, interfaces
- Manager (unified conditional order management)
  - Stop order tracking
  - TPSL order management
  - Price-based trigger detection
  - User order tracking
```

#### `tpsl/` - Take Profit/Stop Loss System
```go
// Depends on: types, interfaces
- TriggerManager (unified trigger management)
  - Price-based trigger detection
  - OCO (One-Cancels-Other) order handling
  - Activation rules (price crossing logic)
  - Execution strategies (Market/Limit conversions)
- StopTrigger & TPSLTrigger implementations
  - Directional price crossing detection
  - Parent order relationship tracking
- OCOController
  - Mutual cancellation logic
  - Parent-child order lifecycle management
```

#### `pipeline/` - Processing Pipelines
```go
// Depends on: types, interfaces, engine
- TradingPipeline
- ManagementPipeline
- Stages (validation, matching, etc.)
```

### Level 3: Persistence

#### `storage/` - Persistence
```go
// Implements: StorageBackend interface
// Depends on: types, interfaces
- MemoryStorage
- DiskStorage
- ArbOSStorage (blockchain)
```

#### `snapshot/` - Snapshots
```go
// Depends on: types, engine, storage
- SnapshotManager
- WAL (Write-Ahead Log)
- Recovery
```

### Level 4: External Interface

#### `api/` - External API
```go
// Depends on: all lower levels
- OrderAPI (place, cancel, modify)
- QueryAPI (orderbook, trades, positions)
- StreamAPI (real-time updates)
```

#### `dispatcher/` - Async Request Routing
```go
// Depends on: interfaces, engine, balance
- Dispatcher (main dispatcher with async processing)
  - Channel-based request processing
  - Worker goroutines for parallel processing
  - Symbol routing and order tracking
  - Balance coordination
  - Lifecycle management (Start/Stop)
- Future: SymbolRouter for sharding
- Future: LoadBalancer for multi-worker distribution
```

## Current Implementation Status

### ✅ Completed Components

#### Level 0: Foundation
- ✅ **types/** - Pure Data Structures
  - `order.go`: Order with improved status flow (NEW → PENDING → FILLED)
  - `trade.go`: Trade execution data structures
  - `conditional.go`: StopOrder and TPSLOrder types
  - `common.go`: Common types, requests, and responses
  - Added `PENDING` status for validated orders
  - Added `TRIGGER_WAIT` status for conditional orders

- ✅ **interfaces/** - Contracts
  - `core.go`: Business logic interfaces (OrderMatcher, OrderQueue, OrderBook, ConditionalOrderManager)
  - `persistence.go`: Persistence interfaces (SnapshotManager, RecoveryManager)
  - Note: StateManager removed - OrderBook now includes state management


#### Level 1: Core Logic
- ✅ **matching/** - Order matching algorithms
  - `price_time_priority.go`: Hyperliquid-style matching implementation
  - Uses OrderBook interface instead of OrderQueue
  - Direct modification of passive orders
  - Separate handling for Market/Limit orders
  - Quote mode support for market orders
  
- ✅ **queue/** - Order queue management
  - `buy_queue.go`: Max heap implementation
  - `sell_queue.go`: Min heap implementation
  - `adapters.go`: OrderQueue interface adapters
  - O(1) lookup with index map
  - Price-time priority ordering
  
- ✅ **book/** - Order book structures
  - `orderbook.go`: Full orderbook with integrated state management
  - Includes buy/sell queues
  - Price level aggregation
  - User order tracking
  - Current price and last trade time
  - Depth calculation
  - UpdateOrder for partial fills

#### Level 2: Business Logic
- ✅ **engine/** - Orchestration
  - `symbol_engine.go`: Main orchestration layer
  - Direct OrderBook management (no StateManager)
  - Pipeline stages documented for future extraction
  - Order processing with 7 clear stages
  - Event generation consolidated in generateEvents()
  - Cancel operations (single/all)
  - Conditional order integration
  
- ✅ **conditional/** - Conditional Orders
  - `manager.go`: Unified conditional order management
  - Stop order tracking and triggering
  - TPSL order management
  - Price-based trigger detection
  - User order tracking

- ✅ **tpsl/** - Take Profit/Stop Loss System
  - `trigger_manager.go`: Centralized trigger management system
  - `triggers.go`: StopTrigger and TPSLTrigger implementations
  - `activation_rule.go`: Price crossing detection logic
  - `execution_strategy.go`: Market/Limit order conversion strategies
  - `oco_controller.go`: One-Cancels-Other order management
  - `interfaces.go`: Clean contract definitions for TPSL components
  - Comprehensive test coverage for all components

- ✅ **balance/** - Balance Lock/Unlock Mechanism (Completed 2025-01)
  - `manager.go`: Balance manager with atomic operations
  - `types.go`: Balance, Lock, and related type definitions
  - Order-based balance locking with LockID tracking
  - Automatic unlock on cancellation
  - Partial unlock on partial fills
  - Multi-token support
  - Fee deduction integration

- ✅ **config/** - Symbol Configuration (Completed 2025-01)
  - `symbol_config.go`: Symbol registry and validation
  - Tick size and lot size validation
  - Min/max order limits
  - Decimal precision handling
  - Per-symbol fee configuration

- ✅ **fee/** - Fee Calculation (Completed 2025-01)
  - `calculator.go`: Fee calculation with maker/taker rates
  - Cost/proceeds estimation
  - Integration with balance manager

### 📋 TODO List

#### 🔴 Critical Priority - Essential Features

##### 1. **dispatcher/** - DispatcherV2 Implementation
- [ ] **Core DispatcherV2**
  - [ ] Create DispatcherV2 with integrated BalanceManager
  - [ ] Pre-validation of balance before engine routing
  - [ ] Symbol validation with SymbolRegistry
  - [ ] Parallel processing for different symbols
  - [ ] Lock management and settlement coordination
  
- [ ] **Request Processing Flow**
  - [ ] Validate order against symbol config (tick/lot size)
  - [ ] Calculate required balance based on order
  - [ ] Lock balance before routing to engine
  - [ ] Route to appropriate SymbolEngine
  - [ ] Handle response and settle trades
  - [ ] Release locks on failure/cancellation
  
- [ ] **Integration with V2 Components**
  - [ ] Wire up BalanceManager for pre-validation
  - [ ] Connect SymbolRegistry for order validation
  - [ ] Integrate FeeCalculator for cost estimation
  - [ ] Add EventLogger for persistence
  
- [ ] **Migration Support**
  - [ ] V1 Request to V2 Request converter
  - [ ] Response mapping for compatibility
  - [ ] Gradual migration path

#### High Priority - Core Functionality

##### 2. **persistence/** - Event & Snapshot Management
- [ ] **Event Logger Implementation**
  - [ ] Implement EventLogger interface using existing WAL infrastructure
  - [ ] Add block-based event batching for atomic writes
  - [ ] Implement event file rotation and cleanup policies
  - [ ] Add compression for historical event files
  
- [ ] **Snapshot System**
  - [ ] Implement SnapshotManager interface
  - [ ] Create snapshot serialization/deserialization logic
  - [ ] Add incremental snapshot support for efficiency
  - [ ] Implement snapshot verification and integrity checks
  
- [ ] **Recovery System**
  - [ ] Implement RecoveryManager for state reconstruction
  - [ ] Add snapshot + WAL replay recovery strategy
  - [ ] Implement recovery progress tracking and reporting
  - [ ] Add recovery validation and consistency checks
  - [ ] Create comprehensive recovery tests

##### 3. **pipeline/** - Processing Pipeline Extraction
- [ ] **Stage Extraction**
  - [ ] Extract validation stage from SymbolEngine
  - [ ] Extract locking stage for concurrency control
  - [ ] Extract matching stage with pluggable algorithms
  - [ ] Extract settlement stage for trade execution
  - [ ] Extract conditional order processing stage
  - [ ] Extract event generation stage
  - [ ] Extract queue update stage
  
- [ ] **Pipeline Framework**
  - [ ] Create pipeline composition framework
  - [ ] Implement stage chaining and error handling
  - [ ] Add pipeline metrics and monitoring hooks
  - [ ] Create pipeline configuration system
  - [ ] Implement async pipeline execution support

##### 4. **Decimal Scaling** - Precision Handling
- [ ] Fix TODOs in `types/common.go` for Price/Quantity scaling
- [ ] Fix TODOs in `matching/price_time_priority.go` for decimal calculations
- [ ] Add configurable decimal precision per symbol
- [ ] Implement overflow/underflow protection
- [ ] Add comprehensive decimal handling tests

#### Medium Priority - System Integration

##### 5. **Integration with Existing System**
- [ ] **Dispatcher Integration**
  - [ ] Update dispatcher to route to v2 engine
  - [ ] Add feature flags for v1/v2 switching
  - [ ] Implement request translation layer
  - [ ] Add performance comparison metrics
  
- [ ] **System Test Updates**
  - [ ] Update `seq_orderbook_test.go` to test v2
  - [ ] Migrate symbolic tests to v2 interfaces
  - [ ] Add v1/v2 compatibility tests
  - [ ] Create performance benchmark suite
  
- [ ] **Migration Support**
  - [ ] Create v1→v2 type adapters
  - [ ] Implement state migration scripts
  - [ ] Add rollback capability
  - [ ] Document migration procedures

##### 6. **Performance Optimization**
- [ ] Profile v2 implementation for bottlenecks
- [ ] Optimize memory allocations in hot paths
- [ ] Add object pooling for frequently allocated types
- [ ] Implement batch processing optimizations
- [ ] Add caching for frequently accessed data

#### Low Priority - Future Extensions

##### 7. **Additional Features**
- [ ] **Alternative Matching Algorithms**
  - [ ] Implement ProRata matching algorithm
  - [ ] Implement Auction-based matching
  - [ ] Add configurable algorithm selection per symbol
  
- [ ] **API Layer**
  - [ ] Implement REST API endpoints
  - [ ] Add WebSocket streaming support
  - [ ] Create GraphQL schema
  - [ ] Add rate limiting and authentication
  
- [ ] **Advanced Routing**
  - [ ] Implement multi-symbol load balancer
  - [ ] Add smart order routing capabilities
  - [ ] Create cross-symbol arbitrage detection

### Implementation Summary

**Completed**: Core orderbook functionality
- ✅ All foundation types and interfaces
- ✅ Hyperliquid-style matching engine using OrderBook interface
- ✅ High-performance order queues with O(1) lookup
- ✅ Complete orderbook with integrated state management
- ✅ Main orchestration engine with direct OrderBook control
- ✅ Conditional order management system
- ✅ TPSL (Take Profit/Stop Loss) trigger system
- ✅ OCO (One-Cancels-Other) order support
- ✅ Pipeline stages documented for future extraction

**Architecture Improvements**:
- Removed StateManager abstraction layer
- OrderBook now single source of truth
- Direct object modification in matching
- Simplified dependency hierarchy
- Clear separation of concerns

**Remaining**: Critical infrastructure components
- Balance lock/unlock mechanism (CRITICAL - highest priority)
- Event logging/recovery system (persistence layer)
- Pipeline stage extraction and framework
- Decimal scaling implementation
- System integration and migration support

## Request/Response Architecture

### Design Principles
1. **Async Processing** - Channel-based for non-blocking operations
2. **Interface-Based** - Extensible request/response types  
3. **Context Propagation** - StateDB and FeeGetter passed with requests
4. **Symbol Sharding Ready** - Designed for future parallel processing

### Request Flow
1. Client creates typed request with StateDB/FeeGetter
2. Request sent to dispatcher via `DispatchReq()`
3. Worker goroutine processes request asynchronously
4. Response sent back via request's response channel
5. Client receives response from channel

### Interface Design
```go
// Request interface
type Request interface {
    StateDB() StateDB
    FeeGetter() FeeRetriever
    ResponseChannel() chan Response
    Clone(respCh chan Response) Request
    Type() RequestType
}

// Response interface  
type Response interface {
    Success() bool
    Error() error
    SetError(err error)
    Type() ResponseType
}
```

### Async Processing Pattern
- Dispatcher maintains request channel with buffer
- Configurable number of worker goroutines (default: 1)
- Non-blocking dispatch with context-based cancellation
- Graceful shutdown with worker synchronization

### Future: Symbol Sharding
- Each symbol can have dedicated worker pool
- Requests routed by symbol for parallel processing
- Shared balance manager with proper locking
- Independent engine instances per symbol

## Architectural Decisions

### Key Design Choices

1. **Direct OrderBook Manipulation**
   - Removed intermediate StateManager layer
   - OrderBook is the single source of truth
   - Matching engine directly modifies passive orders
   - Simplifies state management and reduces overhead

2. **Trigger-Based Conditional Orders**
   - Unified trigger interface for all conditional types
   - Composable activation rules and execution strategies
   - OCO controller for complex order relationships
   - Clean separation between trigger detection and execution

3. **Event-Sourced Persistence**
   - All state changes produce events
   - Events are the source of truth for recovery
   - Snapshots for efficient startup
   - WAL for durability between snapshots

4. **Pipeline-Ready Architecture**
   - Clear stage boundaries in SymbolEngine
   - Each stage has well-defined inputs/outputs
   - Ready for extraction into separate pipeline package
   - Supports future async and parallel processing

5. **Interface-First Development**
   - All major components defined by interfaces
   - Enables testing with mocks
   - Allows alternative implementations
   - Clear contract definitions

## Benefits of V2

1. **Testability**: Each package can be tested in isolation
2. **Maintainability**: Clear boundaries and responsibilities
3. **Extensibility**: Easy to add new features (new matching algorithms, storage backends)
4. **Performance**: Can optimize each layer independently
5. **Clarity**: New developers can understand the architecture quickly
6. **Reliability**: Event-sourced architecture enables full state recovery
7. **Flexibility**: Pluggable components allow easy customization