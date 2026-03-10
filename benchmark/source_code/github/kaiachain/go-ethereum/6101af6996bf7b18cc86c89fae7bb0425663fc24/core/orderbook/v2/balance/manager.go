package balance

import (
	"context"
	"fmt"
	"sync"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/metrics"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// Manager manages balance locking and unlocking for orders
type Manager struct {
	stateDB      types.StateDB
	feeRetriever types.FeeRetriever // Dynamic fee retriever for current block
	config       types.BalanceManagerConfig

	mu        sync.RWMutex
	locks     map[string]*types.LockInfo // All locks in one map
	lockAlias map[string]string          // alias -> real lock ID mapping for TP/SL orders
}

// NewManager creates a new balance manager with default config
// StateDB and FeeRetriever will be provided dynamically per request
func NewManager() *Manager {
	return NewManagerWithConfig(types.DefaultBalanceManagerConfig())
}

// NewManagerWithConfig creates a new balance manager with custom config
// StateDB and FeeRetriever will be provided dynamically per request
func NewManagerWithConfig(config types.BalanceManagerConfig) *Manager {
	return &Manager{
		stateDB:      nil, // Will be set per request via SetStateDB
		feeRetriever: nil, // Will be set per request via SetFeeRetriever
		config:       config,
		locks:        make(map[string]*types.LockInfo),
		lockAlias:    make(map[string]string),
	}
}

// SetStateDB updates the StateDB used by the balance manager
// This is called before processing each request to ensure we use the current block's state
func (m *Manager) SetStateDB(stateDB types.StateDB) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.stateDB = stateDB
}

// SetFeeRetriever updates the FeeRetriever used by the balance manager
// This is called before processing each request to ensure we use the current block's fee configuration
func (m *Manager) SetFeeRetriever(feeRetriever types.FeeRetriever) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.feeRetriever = feeRetriever
}

// Lock locks balance for an order
func (m *Manager) Lock(orderID string, user common.Address, token string, amount *uint256.Int) error {
	if amount == nil || amount.Sign() <= 0 {
		return fmt.Errorf("invalid lock amount")
	}

	// Check StateDB is set
	if m.stateDB == nil {
		return fmt.Errorf("stateDB not initialized")
	}

	// Check available balance
	available := m.stateDB.GetTokenBalance(user, token)
	if available == nil || available.Cmp(amount) < 0 {
		metrics.BalanceLocksFailedCounter.Inc(1)
		return fmt.Errorf("insufficient balance: need %s %s, available %s",
			amount.String(), token, available.String())
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Check if already locked
	if _, exists := m.locks[orderID]; exists {
		metrics.BalanceLocksFailedCounter.Inc(1)
		return fmt.Errorf("order %s already has a lock", orderID)
	}

	// Lock the balance
	m.stateDB.LockTokenBalance(user, token, amount)

	// Record lock
	m.locks[orderID] = &types.LockInfo{
		OrderID:  orderID,
		UserAddr: user,
		Token:    token,
		Amount:   Clone(amount),
	}

	// Update metrics
	metrics.BalanceLocksCreatedCounter.Inc(1)
	metrics.BalanceLocksActiveGauge.Update(int64(len(m.locks)))

	log.Debug("Balance locked",
		"orderID", orderID,
		"user", user.Hex(),
		"token", token,
		"amount", amount.String())

	return nil
}

// Unlock unlocks balance for an order
func (m *Manager) Unlock(orderID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Check if this is an alias and get the real lock ID
	realID := orderID
	if aliasTarget, hasAlias := m.lockAlias[orderID]; hasAlias {
		realID = aliasTarget
		// Remove this specific alias
		delete(m.lockAlias, orderID)
		log.Debug("Using alias for unlock",
			"orderID", orderID,
			"realID", realID)
	}

	lock, exists := m.locks[realID]
	if !exists {
		// Not an error - order might not have a lock
		log.Debug("No lock found for unlock",
			"orderID", orderID,
			"realID", realID,
			"availableLocks", len(m.locks),
			"availableAliases", len(m.lockAlias))

		if log.Root().Enabled(context.Background(), log.LevelDebug) {
			// Log available locks for debugging
			for id := range m.locks {
				log.Debug("Available lock", "lockID", id)
			}
		}
		return nil
	}

	// Unlock the balance
	m.stateDB.UnlockTokenBalance(lock.UserAddr, lock.Token, lock.Amount)

	// Remove lock record
	delete(m.locks, realID)

	// Clean up all aliases pointing to this lock (for TPSL locks)
	if len(realID) > 5 && realID[len(realID)-5:] == "_TPSL" {
		m.cleanupTPSLAliases(realID)
	}

	// Update metrics
	metrics.BalanceLocksReleasedCounter.Inc(1)
	metrics.BalanceLocksActiveGauge.Update(int64(len(m.locks)))

	log.Debug("Balance unlocked",
		"orderID", orderID,
		"realID", realID,
		"user", lock.UserAddr.Hex(),
		"token", lock.Token,
		"amount", lock.Amount.String())

	return nil
}

// ConsumeLock consumes locked balance (for trades)
func (m *Manager) ConsumeLock(orderID string, consumeAmount *uint256.Int) error {
	if consumeAmount == nil || consumeAmount.Sign() <= 0 {
		return fmt.Errorf("invalid consume amount")
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Check if this is an alias and get the real lock ID
	realID := orderID
	if aliasTarget, hasAlias := m.lockAlias[orderID]; hasAlias {
		realID = aliasTarget
	}

	lock, exists := m.locks[realID]
	if !exists {
		return fmt.Errorf("no lock found for order %s (checked %s)", orderID, realID)
	}

	if consumeAmount.Cmp(lock.Amount) > 0 {
		return fmt.Errorf("consume amount %s exceeds locked amount %s",
			consumeAmount.String(), lock.Amount.String())
	}

	// Consume from locked balance
	m.stateDB.ConsumeLockTokenBalance(lock.UserAddr, lock.Token, consumeAmount)

	// Update lock amount
	lock.Amount = new(uint256.Int).Sub(lock.Amount, consumeAmount)

	// If fully consumed, remove lock
	if lock.Amount.IsZero() {
		delete(m.locks, orderID)
		log.Debug("Lock fully consumed", "orderID", orderID)
	} else {
		log.Debug("Partial consume",
			"orderID", orderID,
			"consumed", consumeAmount.String(),
			"remaining", lock.Amount.String())
	}

	return nil
}

// GetLock returns lock info for an order
func (m *Manager) GetLock(orderID string) (*types.LockInfo, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Check if this is an alias and get the real lock ID
	if realID, hasAlias := m.lockAlias[orderID]; hasAlias {
		orderID = realID
	}

	lock, exists := m.locks[orderID]
	if !exists {
		return nil, false
	}

	// Return a copy to prevent external modification
	return &types.LockInfo{
		OrderID:  lock.OrderID,
		UserAddr: lock.UserAddr,
		Token:    lock.Token,
		Amount:   Clone(lock.Amount),
	}, true
}

func (m *Manager) UpdateLock(orderID string, newAmount *uint256.Int) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Check if this is an alias and get the real lock ID
	if realID, hasAlias := m.lockAlias[orderID]; hasAlias {
		orderID = realID
	}

	lock, exists := m.locks[orderID]
	if !exists {
		return fmt.Errorf("lock not found: %v", orderID)
	}

	lock.Amount = newAmount.Clone()
	return nil
}

// HasLock checks if an order has a lock
func (m *Manager) HasLock(orderID string) bool {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Check if this is an alias and get the real lock ID
	if realID, hasAlias := m.lockAlias[orderID]; hasAlias {
		orderID = realID
	}

	_, exists := m.locks[orderID]
	return exists
}

// UnlockAllForUser unlocks all orders for a user
func (m *Manager) UnlockAllForUser(userID string) []string {
	user := common.HexToAddress(userID)
	unlockedOrders := []string{}

	m.mu.Lock()
	defer m.mu.Unlock()

	for orderID, lock := range m.locks {
		if lock.UserAddr == user {
			// Unlock the balance
			m.stateDB.UnlockTokenBalance(lock.UserAddr, lock.Token, lock.Amount)
			unlockedOrders = append(unlockedOrders, orderID)
			delete(m.locks, orderID)

			log.Debug("Order unlocked (cancel all)",
				"orderID", orderID,
				"token", lock.Token,
				"amount", lock.Amount.String())
		}
	}

	log.Debug("All orders unlocked for user",
		"user", user.Hex(),
		"count", len(unlockedOrders))

	return unlockedOrders
}

// LockForOrder locks balance for regular orders (MARKET and LIMIT)
// These orders execute immediately and go directly to the orderbook
func (m *Manager) LockForOrder(order *types.Order) error {
	if order == nil {
		return fmt.Errorf("order cannot be nil")
	}

	if order.OrderType.IsTPSL() {
		return fmt.Errorf("cannot lock for TPSL orders")
	}

	// Only handle regular orders
	if order.OrderType != types.MARKET && order.OrderType != types.LIMIT {
		return fmt.Errorf("LockForOrder only handles MARKET and LIMIT orders, use LockForStopOrder for stop orders")
	}

	user := common.HexToAddress(string(order.UserID))
	baseToken, quoteToken := types.GetTokens(order.Symbol)

	var amount *uint256.Int
	var token string

	switch order.OrderType {
	case types.MARKET:
		amount, token = m.calculateMarketOrderAmount(order, user, baseToken, quoteToken)
		// Set lock info in order for market orders
		order.LockedAmount = Clone(amount)
		log.Debug("Calculated market order lock",
			"orderID", order.OrderID,
			"side", order.Side,
			"mode", order.OrderMode,
			"amount", amount,
			"token", token)
	case types.LIMIT:
		var err error
		amount, token, err = m.calculateLimitOrderAmount(order, baseToken, quoteToken)
		if err != nil {
			return err
		}
		// Limit orders don't need lock info in matching
		order.LockedAmount = nil
		log.Debug("Calculated limit order lock",
			"orderID", order.OrderID,
			"side", order.Side,
			"amount", amount,
			"token", token)
	default:
		return fmt.Errorf("unsupported order type: %v", order.OrderType)
	}

	return m.Lock(string(order.OrderID), user, token, amount)
}

// UpdateLockForTriggeredMarketOrder updates the lock for a triggered stop market order
// This ensures sufficient balance is locked when the market order actually executes
func (m *Manager) UpdateLockForTriggeredMarketOrder(order *types.Order) error {
	if order == nil {
		return fmt.Errorf("order cannot be nil")
	}

	// Only process STOP_MARKET and SL_MARKET orders
	if order.OrderType != types.STOP_MARKET && order.OrderType != types.SL_MARKET {
		return nil // Not a stop market order, no update needed
	}

	user := common.HexToAddress(string(order.UserID))
	baseToken, quoteToken := types.GetTokens(order.Symbol)

	var tokenToLock string
	if order.Side == types.BUY {
		tokenToLock = quoteToken
	} else {
		tokenToLock = baseToken
	}

	// Get existing lock information for this order
	existingLock, hasLock := m.GetLock(string(order.OrderID))
	if !hasLock || existingLock == nil {
		return fmt.Errorf("no existing lock: %v", order.OrderID)
	}

	// GetTokenBalance returns the available (unlocked) balance
	var availableBalance *uint256.Int
	if m.stateDB != nil {
		availableBalance = m.stateDB.GetTokenBalance(user, tokenToLock)
	}

	if availableBalance == nil || availableBalance.Sign() <= 0 {
		// No additional balance available, keep existing lock
		log.Debug("No additional balance available for triggered market order",
			"orderID", order.OrderID,
			"availableBalance", availableBalance)
		// Update the order's locked amount
		order.LockedAmount = Clone(existingLock.Amount)
		return nil
	}

	if m.stateDB != nil {
		m.stateDB.LockTokenBalance(user, tokenToLock, availableBalance)
	}

	// Simply add available balance to existing lock
	additionalAmount := Clone(availableBalance)
	previousAmount := Clone(existingLock.Amount)
	newAmount := new(uint256.Int).Add(existingLock.Amount, additionalAmount)
	if err := m.UpdateLock(string(order.OrderID), newAmount); err != nil {
		log.Error("failed to update lock amount",
			"orderID", order.OrderID,
			"newAmount", newAmount,
			"prevAmount", previousAmount)
		return err
	}

	// Update the order's locked amount
	order.LockedAmount = Clone(existingLock.Amount)

	log.Debug("Updated lock for triggered stop market order",
		"orderID", order.OrderID,
		"orderType", order.OrderType,
		"side", order.Side,
		"previousLock", previousAmount,
		"additionalLock", additionalAmount,
		"totalLock", existingLock.Amount,
		"token", tokenToLock)

	return nil
}

// LockForStopOrder locks balance for stop orders (STOP_MARKET and STOP_LIMIT)
// These are conditional orders that only execute when the stop price is triggered
func (m *Manager) LockForStopOrder(stopOrder *types.StopOrder) error {
	if stopOrder == nil || stopOrder.Order == nil {
		return fmt.Errorf("stop order cannot be nil")
	}

	order := stopOrder.Order
	user := common.HexToAddress(string(order.UserID))
	baseToken, quoteToken := types.GetTokens(order.Symbol)

	var amount *uint256.Int
	var token string

	// StopOrder only contains STOP_MARKET or STOP_LIMIT
	switch order.OrderType {
	case types.STOP_MARKET:
		amount, token = m.calculateStopMarketOrderAmount(stopOrder, baseToken, quoteToken)
		// Set lock info for stop market orders
		order.LockedAmount = Clone(amount)
		log.Debug("Calculated stop market order lock",
			"orderID", order.OrderID,
			"stopPrice", stopOrder.StopPrice,
			"amount", amount,
			"token", token)

	case types.STOP_LIMIT:
		var err error
		amount, token, err = m.calculateStopLimitOrderAmount(stopOrder, baseToken, quoteToken)
		if err != nil {
			return err
		}
		// Stop limit orders don't need lock info in matching (they have price)
		order.LockedAmount = nil
		log.Debug("Calculated stop limit order lock",
			"orderID", order.OrderID,
			"stopPrice", stopOrder.StopPrice,
			"limitPrice", order.Price,
			"amount", amount,
			"token", token)

	default:
		return fmt.Errorf("invalid order type for stop order: %v (expected STOP_MARKET or STOP_LIMIT)", order.OrderType)
	}

	return m.Lock(string(order.OrderID), user, token, amount)
}

// calculateMarketOrderAmount calculates amount to lock for regular market orders
// Market orders lock based on order mode and available balance
func (m *Manager) calculateMarketOrderAmount(order *types.Order, user common.Address,
	baseToken, quoteToken string) (*uint256.Int, string) {

	var tokenToLock string
	var amountToLock *uint256.Int

	if order.Side == types.BUY {
		tokenToLock = quoteToken

		if order.OrderMode == types.QUOTE_MODE {
			// Quote mode BUY: quantity represents the exact quote amount to spend
			amountToLock = Clone(order.Quantity)
		} else {
			// Base mode BUY: we don't know the final price, lock available balance
			available := m.stateDB.GetTokenBalance(user, tokenToLock)
			if available == nil || available.Sign() <= 0 {
				return uint256.NewInt(0), tokenToLock
			}

			// Apply maximum percentage limit if configured
			amountToLock = available
			if m.config.MaxMarketOrderPercent < 100 {
				amountToLock = new(uint256.Int).Mul(available, uint256.NewInt(uint64(m.config.MaxMarketOrderPercent)))
				amountToLock.Div(amountToLock, uint256.NewInt(100))
			}
		}
	} else {
		// SELL side
		tokenToLock = baseToken

		if order.OrderMode == types.QUOTE_MODE {
			// Quote mode SELL: we need to lock enough base to generate the quote amount
			// Since we don't know the price, we must lock available balance
			available := m.stateDB.GetTokenBalance(user, tokenToLock)
			if available == nil || available.Sign() <= 0 {
				return uint256.NewInt(0), tokenToLock
			}

			// Apply maximum percentage limit if configured
			amountToLock = available
			if m.config.MaxMarketOrderPercent < 100 {
				amountToLock = new(uint256.Int).Mul(available, uint256.NewInt(uint64(m.config.MaxMarketOrderPercent)))
				amountToLock.Div(amountToLock, uint256.NewInt(100))
			}
		} else {
			// Base mode SELL: quantity represents the exact base amount to sell
			amountToLock = Clone(order.Quantity)
		}
	}

	return amountToLock, tokenToLock
}

// calculateStopMarketOrderAmount calculates amount to lock for stop market orders
// Stop market orders are conditional orders that become market orders when triggered.
// We lock based on the stop price to ensure sufficient funds when the order triggers.
func (m *Manager) calculateStopMarketOrderAmount(stopOrder *types.StopOrder,
	baseToken, quoteToken string) (*uint256.Int, string) {

	if stopOrder == nil || stopOrder.Order == nil || stopOrder.StopPrice == nil {
		return nil, ""
	}

	order := stopOrder.Order
	var tokenToLock string
	var amountToLock *uint256.Int

	// For stop market orders:
	// - stopOrder.StopPrice contains the trigger price
	// - When triggered, it becomes a market order
	// - We use stop price as a conservative estimate

	if order.Side == types.BUY {
		tokenToLock = quoteToken

		if order.OrderMode == types.QUOTE_MODE {
			// Quote mode BUY: quantity represents the exact quote amount to spend
			amountToLock = Clone(order.Quantity)
		} else {
			// Base mode BUY: calculate quote needed using stop price
			// Amount = stop_price * quantity (worst case execution)
			if !stopOrder.StopPrice.IsZero() {
				amountToLock = common.Uint256MulScaledDecimal(stopOrder.StopPrice, order.Quantity)
			} else {
				// This should not happen - stop orders must have a stop price
				return nil, ""
			}
		}
	} else {
		// SELL side
		tokenToLock = baseToken

		if order.OrderMode == types.QUOTE_MODE {
			// Quote mode SELL: calculate base needed using stop price
			// Amount = quantity / stop_price (conservative estimate)
			if !stopOrder.StopPrice.IsZero() {
				baseAmount := common.Uint256DivScaledDecimal(order.Quantity, stopOrder.StopPrice)
				amountToLock = baseAmount
			} else {
				return nil, ""
			}
		} else {
			// Base mode SELL: quantity represents the exact base amount to sell
			amountToLock = Clone(order.Quantity)
		}
	}

	return amountToLock, tokenToLock
}

// calculateLimitOrderAmount calculates exact amount needed for regular limit orders
func (m *Manager) calculateLimitOrderAmount(order *types.Order,
	baseToken, quoteToken string) (*uint256.Int, string, error) {

	switch order.Side {
	case types.BUY:
		// Base mode: calculate quote needed (price * quantity / 10^18)
		if order.Price == nil || order.Price.IsZero() {
			return nil, "", fmt.Errorf("price required for base mode buy order")
		}
		cost := common.Uint256MulScaledDecimal(order.Price, order.Quantity)
		return cost, quoteToken, nil

	case types.SELL:
		// Base mode: quantity is already base amount
		return order.Quantity, baseToken, nil

	default:
		return nil, "", fmt.Errorf("invalid order side: %v", order.Side)
	}
}

// calculateStopLimitOrderAmount calculates exact amount needed for stop limit orders
// Stop limit orders are conditional orders that become limit orders when triggered.
// We lock based on the limit price since that's the worst case execution price.
func (m *Manager) calculateStopLimitOrderAmount(stopOrder *types.StopOrder,
	baseToken, quoteToken string) (*uint256.Int, string, error) {

	if stopOrder == nil || stopOrder.Order == nil || stopOrder.StopPrice == nil {
		return nil, "", fmt.Errorf("invalid stop order")
	}

	order := stopOrder.Order

	// For stop limit orders:
	// - stopOrder.StopPrice determines when to trigger
	// - order.Price contains the limit price for execution
	// - We lock based on the limit price (worst case)

	// Validate that we have a limit price
	if order.Price == nil || order.Price.IsZero() {
		return nil, "", fmt.Errorf("stop limit order must have a limit price")
	}

	// Calculate lock amount same as limit orders
	// The only difference is stop limit orders are conditional
	switch order.Side {
	case types.BUY:
		if order.OrderMode == types.QUOTE_MODE {
			// Quote mode: quantity is already quote amount
			return order.Quantity, quoteToken, nil
		}
		// Base mode: calculate quote needed (limit_price * quantity)
		cost := common.Uint256MulScaledDecimal(order.Price, order.Quantity)
		return cost, quoteToken, nil

	case types.SELL:
		if order.OrderMode == types.QUOTE_MODE {
			// Quote mode: calculate base needed (quantity / limit_price)
			base := common.Uint256DivScaledDecimal(order.Quantity, order.Price)
			return base, baseToken, nil
		}
		// Base mode: quantity is already base amount
		return order.Quantity, baseToken, nil

	default:
		return nil, "", fmt.Errorf("invalid order side: %v", order.Side)
	}
}

// ModifyOrderLock handles order modification atomically
// Only supports modifying LIMIT orders with the same token
func (m *Manager) ModifyOrderLock(oldOrderID string, newOrder *types.Order) error {
	if newOrder == nil {
		return fmt.Errorf("new order cannot be nil")
	}

	// Only LIMIT orders can be modified
	if newOrder.OrderType != types.LIMIT {
		return fmt.Errorf("only LIMIT orders can be modified, got: %v", newOrder.OrderType)
	}

	// Calculate requirements for new order
	user := common.HexToAddress(string(newOrder.UserID))
	baseToken, quoteToken := types.GetTokens(newOrder.Symbol)

	newAmount, newToken, err := m.calculateLimitOrderAmount(newOrder, baseToken, quoteToken)
	if err != nil {
		return fmt.Errorf("failed to calculate new order requirements: %w", err)
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Get old lock
	oldLock, exists := m.locks[oldOrderID]
	if !exists {
		return fmt.Errorf("no lock found for order %s", oldOrderID)
	}

	// Only allow modification with same token
	if oldLock.Token != newToken {
		return fmt.Errorf("cannot modify order: token change not allowed (old: %s, new: %s). Cancel and place new order instead",
			oldLock.Token, newToken)
	}

	// Calculate difference
	diff := new(uint256.Int).Sub(newAmount, oldLock.Amount)

	if diff.Sign() > 0 {
		// Need more tokens
		available := m.stateDB.GetTokenBalance(user, newToken)
		if available == nil || available.Cmp(diff) < 0 {
			return fmt.Errorf("insufficient balance for modification: need additional %s %s",
				diff.String(), newToken)
		}
		// Lock additional amount
		m.stateDB.LockTokenBalance(user, newToken, diff)
	} else if diff.Sign() < 0 {
		// Need less tokens - unlock the difference
		unlockAmount := new(uint256.Int).Neg(diff)
		m.stateDB.UnlockTokenBalance(user, newToken, unlockAmount)
	}

	// Update lock record
	oldLock.OrderID = string(newOrder.OrderID)
	oldLock.Amount = Clone(newAmount)
	m.locks[string(newOrder.OrderID)] = oldLock
	delete(m.locks, oldOrderID)

	log.Debug("Order modified, lock updated",
		"oldOrderID", oldOrderID,
		"newOrderID", newOrder.OrderID,
		"token", newToken,
		"oldAmount", oldLock.Amount.String(),
		"newAmount", newAmount.String())

	return nil
}

// GetLockInfo returns the lock information for an order
func (m *Manager) GetLockInfo(orderID string) *types.LockInfo {
	m.mu.RLock()
	defer m.mu.RUnlock()

	lock, exists := m.locks[orderID]
	if !exists {
		return nil
	}

	// Return a copy to prevent external modification
	return &types.LockInfo{
		OrderID:  lock.OrderID,
		UserAddr: lock.UserAddr,
		Token:    lock.Token,
		Amount:   Clone(lock.Amount),
	}
}

// TransformLock transforms a lock from one token to another (used for TPSL after main order fills)
func (m *Manager) TransformLock(orderID string, fromToken, toToken string, toAmount *uint256.Int) error {
	if toAmount == nil || toAmount.Sign() <= 0 {
		return fmt.Errorf("invalid transform amount")
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Get existing lock
	lock, exists := m.locks[orderID]
	if !exists {
		return fmt.Errorf("no lock found for order %s", orderID)
	}

	// Verify it's the expected token
	if lock.Token != fromToken {
		return fmt.Errorf("lock token mismatch: expected %s, got %s", fromToken, lock.Token)
	}

	// Unlock the old token
	m.stateDB.UnlockTokenBalance(lock.UserAddr, lock.Token, lock.Amount)

	// Lock the new token
	m.stateDB.LockTokenBalance(lock.UserAddr, toToken, toAmount)

	// Transform the lock record
	lock.Token = toToken
	lock.Amount = Clone(toAmount)

	log.Debug("Lock transformed for TPSL",
		"orderID", orderID,
		"user", lock.UserAddr.Hex(),
		"fromToken", fromToken,
		"fromAmount", lock.Amount.String(),
		"toToken", toToken,
		"toAmount", toAmount.String())

	return nil
}

// GetFeeConfig returns the current fee configuration
func (m *Manager) GetFeeConfig() types.FeeConfig {
	return m.config.FeeConfig
}

// Clone creates a copy of uint256 value
func Clone(v *uint256.Int) *uint256.Int {
	if v == nil {
		return nil
	}
	return new(uint256.Int).Set(v)
}

// GetAllLocks returns all balance locks for persistence
func (m *Manager) GetAllLocks() []*types.LockInfo {
	m.mu.RLock()
	defer m.mu.RUnlock()

	locks := make([]*types.LockInfo, 0, len(m.locks))
	for _, lock := range m.locks {
		// Return copies to prevent external modification
		locks = append(locks, &types.LockInfo{
			OrderID:  lock.OrderID,
			UserAddr: lock.UserAddr,
			Token:    lock.Token,
			Amount:   Clone(lock.Amount),
		})
	}
	return locks
}

// RestoreLock restores a balance lock from persistence
func (m *Manager) RestoreLock(lock *types.LockInfo) error {
	if lock == nil {
		return fmt.Errorf("nil lock info")
	}

	// Validate lock fields
	if lock.OrderID == "" {
		return fmt.Errorf("empty order ID in lock info")
	}
	if lock.Token == "" {
		return fmt.Errorf("empty token in lock info")
	}
	if lock.Amount == nil || lock.Amount.Sign() <= 0 {
		return fmt.Errorf("invalid lock amount for order %s", lock.OrderID)
	}
	if lock.UserAddr == (common.Address{}) {
		return fmt.Errorf("invalid user address in lock info for order %s", lock.OrderID)
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Check for duplicate
	if _, exists := m.locks[lock.OrderID]; exists {
		log.Warn("Duplicate lock being restored", "orderID", lock.OrderID)
	}

	m.locks[lock.OrderID] = lock
	log.Debug("Lock restored",
		"orderID", lock.OrderID,
		"user", lock.UserAddr.Hex(),
		"token", lock.Token,
		"amount", lock.Amount.String())
	return nil
}

// RegisterTPSLAlias registers TP and SL order IDs as aliases for the TPSL lock
// TEMPORARY: Made public for early TPSL lock creation in symbol engine
// TODO-Orderbook: Refactor to proper architecture after settlement timing is fixed
func (m *Manager) RegisterTPSLAlias(originalOrderID types.OrderID) {
	m.mu.Lock()
	defer m.mu.Unlock()

	tpslLockID := fmt.Sprintf("%s_TPSL", originalOrderID)
	tpOrderID := types.GenerateTPOrderID(originalOrderID)
	slOrderID := types.GenerateSLOrderID(originalOrderID)

	// Register aliases: TP/SL OrderID -> TPSL lock ID
	m.lockAlias[string(tpOrderID)] = tpslLockID
	m.lockAlias[string(slOrderID)] = tpslLockID

	log.Debug("TPSL aliases registered",
		"originalOrder", originalOrderID,
		"tpOrder", tpOrderID,
		"slOrder", slOrderID,
		"tpslLock", tpslLockID)
}

// cleanupTPSLAliases removes all aliases pointing to a TPSL lock
func (m *Manager) cleanupTPSLAliases(tpslLockID string) {
	// Note: caller must hold the lock
	aliasesRemoved := 0
	for alias, target := range m.lockAlias {
		if target == tpslLockID {
			delete(m.lockAlias, alias)
			aliasesRemoved++
		}
	}

	if aliasesRemoved > 0 {
		log.Debug("TPSL aliases cleaned up",
			"tpslLock", tpslLockID,
			"aliasesRemoved", aliasesRemoved)
	}
}

// GetSnapshotData returns the balance manager state for persistence
func (m *Manager) GetSnapshotData() (locks map[string]*types.LockInfo, lockAlias map[string]string) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Make copies of the maps to avoid concurrent modification
	locks = make(map[string]*types.LockInfo)
	for k, v := range m.locks {
		// Create a copy of the LockInfo
		lockCopy := &types.LockInfo{
			OrderID:  v.OrderID,
			UserAddr: v.UserAddr,
			Token:    v.Token,
			Amount:   v.Amount.Clone(),
		}
		locks[k] = lockCopy
	}

	lockAlias = make(map[string]string)
	for k, v := range m.lockAlias {
		lockAlias[k] = v
	}

	return locks, lockAlias
}

// RestoreFromSnapshot restores the balance manager state from a snapshot
func (m *Manager) RestoreFromSnapshot(locks map[string]*types.LockInfo, lockAlias map[string]string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Clear existing state
	m.locks = make(map[string]*types.LockInfo)
	m.lockAlias = make(map[string]string)

	// Restore locks
	for k, v := range locks {
		// Create a copy of the LockInfo
		lockCopy := &types.LockInfo{
			OrderID:  v.OrderID,
			UserAddr: v.UserAddr,
			Token:    v.Token,
			Amount:   v.Amount.Clone(),
		}
		m.locks[k] = lockCopy
	}

	// Restore aliases
	for k, v := range lockAlias {
		m.lockAlias[k] = v
	}

	log.Debug("Balance manager restored from snapshot",
		"locks", len(m.locks),
		"aliases", len(m.lockAlias))

	return nil
}
