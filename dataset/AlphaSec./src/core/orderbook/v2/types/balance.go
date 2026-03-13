package types

import (
	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
)

// LockInfo stores information about a locked balance
type LockInfo struct {
	OrderID  string
	UserAddr common.Address
	Token    string
	Amount   *uint256.Int
}

// FeeConfig holds fee configuration
type FeeConfig struct {
	// Fee rates are now retrieved dynamically via FeeRetriever per request
	// No static MakerFeeRate or TakerFeeRate stored here
	FeeCollector common.Address // Address to collect fees
}

// DefaultFeeConfig returns default fee configuration
func DefaultFeeConfig() FeeConfig {
	return FeeConfig{
		FeeCollector: common.HexToAddress("0x00000000000000000000000000000000000000dd"),
	}
}

// BalanceManagerConfig holds configuration for the balance manager
type BalanceManagerConfig struct {
	FeeConfig             FeeConfig
	MaxMarketOrderPercent uint8 // Maximum percentage of balance to lock for market orders (0-100)
}

// DefaultBalanceManagerConfig returns default manager configuration
func DefaultBalanceManagerConfig() BalanceManagerConfig {
	return BalanceManagerConfig{
		FeeConfig:             DefaultFeeConfig(),
		MaxMarketOrderPercent: 100, // Default: allow locking 100% of balance
	}
}