package orderbook

import (
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/log"
	"github.com/holiman/uint256"
	"github.com/shopspring/decimal"
)

// TODO-Orderbook: FeeRate should not be constant, but should be set by the DEX owner.
var (
	//FeeRate       uint64 = 5000 // *0.02% (=/5000) fee rate
	FeeScalingExp = uint256.NewInt(10e6)
)

type FeeRetriever interface {
	GetMarketFees(base, quote uint64) (*big.Int, *big.Int, error)
}

type Locker interface {
	AddTokenBalance(addr common.Address, token string, amount *uint256.Int)
	ConsumeLockTokenBalance(addr common.Address, token string, amount *uint256.Int)
	GetTokenBalance(addr common.Address, token string) *uint256.Int
	LockTokenBalance(addr common.Address, token string, amount *uint256.Int)
	UnlockTokenBalance(addr common.Address, token string, amount *uint256.Int)
	GetLockedTokenBalance(addr common.Address, token string) *uint256.Int
}

func toDecimal(value *uint256.Int) decimal.Decimal {
	return decimal.NewFromBigInt(value.ToBig(), -ScalingExp)
}

var RewardAddress = common.HexToAddress("0xdd")

type DefaultLocker struct {
	Locker
	makerFee, takerFee *big.Int
}

func wrapLocker(db Locker, makerFee, takerFee *big.Int) *DefaultLocker {
	if db == nil {
		log.Error("wrapLocker called with nil Locker")
		return nil
	}
	return &DefaultLocker{db, makerFee, takerFee}
}

func (l *DefaultLocker) LockMarketOrder(user common.Address, token string) *uint256.Int {
	locked := l.GetTokenBalance(user, token)
	l.LockTokenBalance(user, token, locked)
	log.Info("MarketOrder token locked", "user", user.Hex(), "token", token, "lockedAmount", toDecimal(locked))
	return locked
}

func (l *DefaultLocker) UnlockMarketRefund(user common.Address, token string, locked, used *uint256.Int) {
	refund := new(uint256.Int).Sub(locked, used)
	if refund.Sign() > 0 {
		l.UnlockTokenBalance(user, token, refund)
		log.Info("Market order unfilled amount unlocked", "userID", user.Hex(), "token", token, "amount", toDecimal(refund))
	}
}

func (l *DefaultLocker) ConsumeTradeBalance(buyer, seller common.Address, baseToken, quoteToken string, qty, cost *uint256.Int, isBuyerMaker bool) (*uint256.Int, *uint256.Int, *uint256.Int, *uint256.Int, error) {
	quoteLocked := l.GetLockedTokenBalance(buyer, quoteToken)
	if quoteLocked.Cmp(cost) < 0 {
		log.Error("Insufficient locked balance for buyer", "userID", buyer.Hex(), "token", quoteToken, "locked", toDecimal(quoteLocked), "required", toDecimal(cost))
		return nil, nil, nil, nil, fmt.Errorf("insufficient locked balance for buyer")
	}
	baseLocked := l.GetLockedTokenBalance(seller, baseToken)
	if baseLocked.Cmp(qty) < 0 {
		log.Error("Insufficient locked balance for seller", "userID", seller.Hex(), "token", baseToken, "locked", toDecimal(baseLocked), "required", toDecimal(qty))
		return nil, nil, nil, nil, fmt.Errorf("insufficient locked balance for seller")
	}

	feeQty := new(uint256.Int).SetUint64(0) // No fee
	if isBuyerMaker {
		feeTmp := new(uint256.Int).Mul(qty, uint256.MustFromBig(l.makerFee))
		feeQty = new(uint256.Int).Div(feeTmp, FeeScalingExp)
	} else {
		feeTmp := new(uint256.Int).Mul(qty, uint256.MustFromBig(l.takerFee))
		feeQty = new(uint256.Int).Div(feeTmp, FeeScalingExp)
	}
	//if FeeRate != 0 {
	//	feeQty = new(uint256.Int).Div(qty, new(uint256.Int).SetUint64(FeeRate)) // 0.02% fee
	//}
	deductedQty := new(uint256.Int).Sub(qty, feeQty)

	// Buyer receives baseToken, pays quoteToken
	l.AddTokenBalance(RewardAddress, baseToken, feeQty)
	l.AddTokenBalance(buyer, baseToken, deductedQty)
	l.ConsumeLockTokenBalance(buyer, quoteToken, cost)
	log.Info("Buyer trade executed", "userID", buyer.Hex(), "base", baseToken, "add", toDecimal(deductedQty), "fee", toDecimal(feeQty), "quote", quoteToken, "consume", toDecimal(cost))

	feeCost := new(uint256.Int).SetUint64(0) // No fee
	if isBuyerMaker {
		feeTmp := new(uint256.Int).Mul(cost, uint256.MustFromBig(l.takerFee))
		feeCost = new(uint256.Int).Div(feeTmp, FeeScalingExp)
	} else {
		feeTmp := new(uint256.Int).Mul(cost, uint256.MustFromBig(l.makerFee))
		feeCost = new(uint256.Int).Div(feeTmp, FeeScalingExp)
	}
	//if FeeRate != 0 {
	//	feeCost = new(uint256.Int).Div(cost, new(uint256.Int).SetUint64(FeeRate)) // 0.02% fee
	//}
	deductedCost := new(uint256.Int).Sub(cost, feeCost)

	// Seller receives quoteToken, pays baseToken
	l.AddTokenBalance(RewardAddress, quoteToken, feeCost)
	l.AddTokenBalance(seller, quoteToken, deductedCost)
	l.ConsumeLockTokenBalance(seller, baseToken, qty)
	log.Info("Seller trade executed", "userID", seller.Hex(), "quote", quoteToken, "add", toDecimal(cost), "fee", toDecimal(feeCost), "base", baseToken, "consume", toDecimal(qty))

	return deductedQty, feeQty, deductedCost, feeCost, nil
}

func (l *DefaultLocker) LockStopOrder(order *Order, stopPrice *uint256.Int) {
	addr := common.HexToAddress(order.UserID)
	baseToken, quoteToken, _ := SymbolToTokens(order.Symbol)

	switch order.Side {
	case BUY:
		var lockAmount *uint256.Int
		if order.OrderMode == QUOTE_MODE {
			// In quote mode: quantity represents quote tokens to spend
			lockAmount = order.Quantity
		} else { // BASE_MODE
			// In base mode: calculate quote needed based on price
			if order.OrderType == LIMIT {
				lockAmount = common.Uint256MulScaledDecimal(order.Price, order.Quantity)
			} else if order.OrderType == MARKET {
				lockAmount = common.Uint256MulScaledDecimal(stopPrice, order.Quantity)
			} else {
				log.Error("Unsupported stop BUY order type", "orderType", order.OrderType)
				return
			}
		}
		l.LockTokenBalance(addr, quoteToken, lockAmount)
		log.Info("Locked quoteToken for stop BUY", "user", addr.Hex(), "token", quoteToken, "amount", toDecimal(lockAmount))

	case SELL:
		var lockAmount *uint256.Int
		if order.OrderMode == QUOTE_MODE {
			// In quote mode: need to calculate base tokens required
			// base_amount = quote_amount / price
			if order.OrderType == LIMIT && order.Price != nil && order.Price.Sign() > 0 {
				lockAmount = common.Uint256DivScaledDecimal(order.Quantity, order.Price)
			} else if order.OrderType == MARKET && stopPrice != nil && stopPrice.Sign() > 0 {
				lockAmount = common.Uint256DivScaledDecimal(order.Quantity, stopPrice)
			} else {
				log.Error("Invalid price for quote mode SELL order", "orderType", order.OrderType)
				return
			}
		} else { // BASE_MODE
			// In base mode: quantity is already in base tokens
			lockAmount = new(uint256.Int).Set(order.Quantity)
		}
		l.LockTokenBalance(addr, baseToken, lockAmount)
		log.Info("Locked baseToken for stop SELL", "user", addr.Hex(), "token", baseToken, "amount", lockAmount)

	default:
		panic("Unsupported order side")
	}
}

func (l *DefaultLocker) UnlockStopOrder(order *Order, stopPrice *uint256.Int) {
	addr := common.HexToAddress(order.UserID)
	baseToken, quoteToken, _ := SymbolToTokens(order.Symbol)

	switch order.Side {
	case BUY:
		var unlockAmount *uint256.Int
		if order.OrderMode == QUOTE_MODE {
			// In quote mode: quantity represents quote tokens to spend
			unlockAmount = order.Quantity
		} else { // BASE_MODE
			// In base mode: calculate quote needed based on price
			if order.OrderType == LIMIT {
				unlockAmount = common.Uint256MulScaledDecimal(order.Price, order.Quantity)
			} else { // MARKET
				unlockAmount = common.Uint256MulScaledDecimal(stopPrice, order.Quantity)
			}
		}
		l.UnlockTokenBalance(addr, quoteToken, unlockAmount)
		log.Info("StopOrder unlocked quoteToken", "user", addr.Hex(), "quote", quoteToken, "amount", toDecimal(unlockAmount))

	case SELL:
		var unlockAmount *uint256.Int
		if order.OrderMode == QUOTE_MODE {
			// In quote mode: need to calculate base tokens required
			// base_amount = quote_amount / price
			if order.OrderType == LIMIT && order.Price != nil && order.Price.Sign() > 0 {
				unlockAmount = common.Uint256DivScaledDecimal(order.Quantity, order.Price)
			} else if order.OrderType == MARKET && stopPrice != nil && stopPrice.Sign() > 0 {
				unlockAmount = common.Uint256DivScaledDecimal(order.Quantity, stopPrice)
			} else {
				log.Error("Invalid price for quote mode SELL order", "orderType", order.OrderType)
				return
			}
		} else { // BASE_MODE
			// In base mode: quantity is already in base tokens
			unlockAmount = new(uint256.Int).Set(order.Quantity)
		}
		l.UnlockTokenBalance(addr, baseToken, unlockAmount)
		log.Info("StopOrder unlocked baseToken", "user", addr.Hex(), "base", baseToken, "amount", toDecimal(unlockAmount))

	default:
		panic("Unsupported order side")
	}
}
