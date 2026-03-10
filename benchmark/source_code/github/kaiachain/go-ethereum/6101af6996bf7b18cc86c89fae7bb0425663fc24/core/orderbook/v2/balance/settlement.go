package balance

import (
	"fmt"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/metrics"
	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
)

// settlementContext holds all data needed for trade settlement
type settlementContext struct {
	buyer          common.Address
	seller         common.Address
	baseToken      string
	quoteToken     string
	buyerLock      *types.LockInfo
	sellerLock     *types.LockInfo
	cost           *uint256.Int
	buyerFee       *uint256.Int
	sellerFee      *uint256.Int
	buyerReceives  *uint256.Int
	sellerReceives *uint256.Int
}

// SettleTrade handles balance updates after trade execution
func (m *Manager) SettleTrade(trade *types.Trade) error {
	// Validate trade
	if err := m.validateTrade(trade); err != nil {
		return fmt.Errorf("trade validation failed: %w", err)
	}

	// Extract settlement context
	ctx, err := m.prepareSettlementContext(trade)
	if err != nil {
		return fmt.Errorf("failed to prepare settlement: %w", err)
	}

	// Verify and consume locks
	if err := m.verifyAndConsumeLocks(ctx, trade); err != nil {
		return fmt.Errorf("lock processing failed: %w", err)
	}

	// Calculate net amounts after fees
	if err := m.calculateSettlementAmounts(ctx, trade); err != nil {
		return fmt.Errorf("amount calculation failed: %w", err)
	}

	// Execute asset transfers
	m.executeAssetTransfers(ctx)

	// Transfer fees to collector
	m.transferFeesToCollector(ctx)

	// Update Fee information on trade
	m.updateTradeFeeInfo(ctx, trade)

	// TEMPORARY FIX: Balance manager for TPSL lock inheritance
	// TODO-Orderbook: Refactor to proper architecture after settlement timing is fixed
	// Handle TPSL lock inheritance
	//m.handleTPSLLockInheritance(trade, ctx)

	// Update metrics
	metrics.BalanceSettlementsCounter.Inc(1)

	log.Info("Trade settled",
		"tradeID", trade.TradeID,
		"symbol", trade.Symbol,
		"price", trade.Price.String(),
		"quantity", trade.Quantity.String(),
		"buyOrderID", trade.BuyOrderID,
		"sellOrderID", trade.SellOrderID,
		"buyer", ctx.buyer.Hex(),
		"seller", ctx.seller.Hex(),
		"cost", ctx.cost.String(),
		"buyerFee", ctx.buyerFee.String(),
		"sellerFee", ctx.sellerFee.String())

	return nil
}

// updateTradeFeeInfo update trade fee information on trade
func (m *Manager) updateTradeFeeInfo(ctx *settlementContext, trade *types.Trade) {
	// Update buyer fee info - buyer pays fee in base token (what they receive)
	trade.BuyFeeTokenID = ctx.baseToken
	trade.BuyFeeAmount = ctx.buyerFee
	
	// Update seller fee info - seller pays fee in quote token (what they receive)  
	trade.SellFeeTokenID = ctx.quoteToken
	trade.SellFeeAmount = ctx.sellerFee
}

// validateTrade validates the trade object
func (m *Manager) validateTrade(trade *types.Trade) error {
	if trade == nil {
		return fmt.Errorf("trade cannot be nil")
	}
	if trade.Quantity == nil || trade.Quantity.Sign() <= 0 {
		return fmt.Errorf("invalid trade quantity")
	}
	if trade.Price == nil || trade.Price.Sign() <= 0 {
		return fmt.Errorf("invalid trade price")
	}
	return nil
}

// prepareSettlementContext prepares all necessary data for settlement
func (m *Manager) prepareSettlementContext(trade *types.Trade) (*settlementContext, error) {
	// Get buyer and seller locks
	buyerLock, hasBuyLock := m.GetLock(string(trade.BuyOrderID))
	if !hasBuyLock {
		return nil, fmt.Errorf("no lock found for buy order %s", trade.BuyOrderID)
	}

	sellerLock, hasSellLock := m.GetLock(string(trade.SellOrderID))
	if !hasSellLock {
		return nil, fmt.Errorf("no lock found for sell order %s", trade.SellOrderID)
	}

	// Calculate trade cost
	cost := common.Uint256MulScaledDecimal(trade.Price, trade.Quantity)

	baseToken, quoteToken := types.GetTokens(trade.Symbol)

	return &settlementContext{
		buyer:      buyerLock.UserAddr,
		seller:     sellerLock.UserAddr,
		baseToken:  baseToken,
		quoteToken: quoteToken,
		buyerLock:  buyerLock,
		sellerLock: sellerLock,
		cost:       cost,
	}, nil
}

// verifyAndConsumeLocks verifies sufficient locks and consumes them
func (m *Manager) verifyAndConsumeLocks(ctx *settlementContext, trade *types.Trade) error {
	// Verify buyer has sufficient locked quote tokens
	if ctx.cost.Cmp(ctx.buyerLock.Amount) > 0 {
		return fmt.Errorf("insufficient locked balance for buyer: need %s, have %s",
			ctx.cost.String(), ctx.buyerLock.Amount.String())
	}

	// Verify seller has sufficient locked base tokens
	if trade.Quantity.Cmp(ctx.sellerLock.Amount) > 0 {
		return fmt.Errorf("insufficient locked balance for seller: need %s, have %s",
			trade.Quantity.String(), ctx.sellerLock.Amount.String())
	}

	// Consume locks
	if err := m.ConsumeLock(ctx.buyerLock.OrderID, ctx.cost); err != nil {
		return fmt.Errorf("failed to consume buyer lock: %w", err)
	}

	if err := m.ConsumeLock(ctx.sellerLock.OrderID, trade.Quantity); err != nil {
		return fmt.Errorf("failed to consume seller lock: %w", err)
	}

	return nil
}

// calculateSettlementAmounts calculates fees and net amounts
func (m *Manager) calculateSettlementAmounts(ctx *settlementContext, trade *types.Trade) error {
	// Calculate fees based on maker/taker roles
	var err error
	ctx.buyerFee, ctx.sellerFee, err = m.calculateTradeFees(
		trade.Symbol, trade.Quantity, ctx.cost, trade.IsBuyerMaker)
	if err != nil {
		return fmt.Errorf("failed to calculate trade fees: %w", err)
	}

	// Calculate net amounts after fees
	ctx.buyerReceives, err = SafeSub(trade.Quantity, ctx.buyerFee)
	if err != nil {
		return fmt.Errorf("failed to calculate buyer receives: %w", err)
	}

	ctx.sellerReceives, err = SafeSub(ctx.cost, ctx.sellerFee)
	if err != nil {
		return fmt.Errorf("failed to calculate seller receives: %w", err)
	}

	return nil
}

// executeAssetTransfers transfers tokens to traders
func (m *Manager) executeAssetTransfers(ctx *settlementContext) {
	m.stateDB.AddTokenBalance(ctx.buyer, ctx.baseToken, ctx.buyerReceives)
	m.stateDB.AddTokenBalance(ctx.seller, ctx.quoteToken, ctx.sellerReceives)
}

// transferFeesToCollector transfers fees to the fee collector
func (m *Manager) transferFeesToCollector(ctx *settlementContext) {
	feeCollector := m.config.FeeConfig.FeeCollector
	if feeCollector == (common.Address{}) {
		return
	}

	if ctx.buyerFee.Sign() > 0 {
		m.stateDB.AddTokenBalance(feeCollector, ctx.baseToken, ctx.buyerFee)
	}
	if ctx.sellerFee.Sign() > 0 {
		m.stateDB.AddTokenBalance(feeCollector, ctx.quoteToken, ctx.sellerFee)
	}
}

// handleTPSLLockInheritance handles TPSL lock creation for filled orders
func (m *Manager) handleTPSLLockInheritance(trade *types.Trade, ctx *settlementContext) {
	// Buyer TPSL: lock the received base tokens
	if trade.BuyOrderHasTPSL && trade.BuyOrderFullyFilled {
		m.createTPSLLockForOrder(trade.BuyOrderID, ctx.buyer, ctx.baseToken, ctx.buyerReceives)
	}

	// Seller TPSL: lock the received quote tokens
	if trade.SellOrderHasTPSL && trade.SellOrderFullyFilled {
		m.createTPSLLockForOrder(trade.SellOrderID, ctx.seller, ctx.quoteToken, ctx.sellerReceives)
	}
}

// createTPSLLockForOrder creates a TPSL lock for a specific order
func (m *Manager) createTPSLLockForOrder(orderID types.OrderID, user common.Address, token string, amount *uint256.Int) {
	tpslLockID := fmt.Sprintf("%s_TPSL", orderID)

	if err := m.Lock(tpslLockID, user, token, amount); err != nil {
		log.Error("Failed to create TPSL lock",
			"orderID", orderID,
			"token", token,
			"amount", amount.String(),
			"error", err)
		// Continue even if TPSL lock fails (following CEX pattern)
	} else {
		log.Debug("TPSL lock created",
			"orderID", orderID,
			"token", token,
			"amount", amount.String())
		
		// Register TP/SL order IDs as aliases for this TPSL lock
		m.RegisterTPSLAlias(orderID)
	}
}

// calculateTradeFees calculates trade fees using dynamic FeeRetriever
func (m *Manager) calculateTradeFees(symbol types.Symbol, baseAmount, quoteAmount *uint256.Int, isBuyerMaker bool) (*uint256.Int, *uint256.Int, error) {
	// Check if FeeRetriever is available
	if m.feeRetriever == nil {
		return nil, nil, fmt.Errorf("fee retriever not set")
	}

	// Parse symbol to get base and quote token IDs
	baseToken, quoteToken := types.GetTokens(symbol)

	// Convert token strings to uint64 IDs for FeeRetriever
	// Assuming tokens are numeric strings like "2", "3"
	var baseID, quoteID uint64
	if _, err := fmt.Sscanf(baseToken, "%d", &baseID); err != nil {
		return nil, nil, fmt.Errorf("invalid base token ID: %s", baseToken)
	}
	if _, err := fmt.Sscanf(quoteToken, "%d", &quoteID); err != nil {
		return nil, nil, fmt.Errorf("invalid quote token ID: %s", quoteToken)
	}

	// Get dynamic fees from FeeRetriever
	makerFeeBP, takerFeeBP, err := m.feeRetriever.GetMarketFees(baseID, quoteID)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get market fees: %w", err)
	}

	// Check for nil fee rates
	if makerFeeBP == nil || takerFeeBP == nil {
		return nil, nil, fmt.Errorf("fee retriever returned nil fee rates")
	}

	// Convert basis points to uint256
	// SetFromBig sets the value regardless of return value
	// It returns false for values within range, true for overflow
	makerFeeRate := new(uint256.Int)
	makerFeeRate.SetFromBig(makerFeeBP)
	// Only check for actual overflow (negative or > 256 bits)
	if makerFeeBP.Sign() < 0 {
		return nil, nil, fmt.Errorf("maker fee rate cannot be negative: value=%v", makerFeeBP)
	}

	takerFeeRate := new(uint256.Int)
	takerFeeRate.SetFromBig(takerFeeBP)
	// Only check for actual overflow (negative or > 256 bits)
	if takerFeeBP.Sign() < 0 {
		return nil, nil, fmt.Errorf("taker fee rate cannot be negative: value=%v", takerFeeBP)
	}

	var buyerFee, sellerFee *uint256.Int

	if isBuyerMaker {
		// Buyer is maker, seller is taker
		buyerFee, _ = ApplyFee(baseAmount, makerFeeRate)
		sellerFee, _ = ApplyFee(quoteAmount, takerFeeRate)
	} else {
		// Buyer is taker, seller is maker
		buyerFee, _ = ApplyFee(baseAmount, takerFeeRate)
		sellerFee, _ = ApplyFee(quoteAmount, makerFeeRate)
	}

	// Ensure fees are not nil
	if buyerFee == nil {
		buyerFee = uint256.NewInt(0)
	}
	if sellerFee == nil {
		sellerFee = uint256.NewInt(0)
	}

	return buyerFee, sellerFee, nil
}

// CompleteOrder handles final cleanup when an order is fully filled or cancelled
func (m *Manager) CompleteOrder(orderID string) error {
	// Simply unlock any remaining balance
	return m.Unlock(orderID)
}
