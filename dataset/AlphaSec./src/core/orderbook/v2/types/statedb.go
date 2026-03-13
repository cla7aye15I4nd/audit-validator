package types

import (
	"github.com/ethereum/go-ethereum/common"
	"github.com/holiman/uint256"
)

// StateDB interface for balance operations
// This matches go-ethereum/core/vm/interface.go StateDB
type StateDB interface {
	GetTokenBalance(common.Address, string) *uint256.Int
	GetLockedTokenBalance(common.Address, string) *uint256.Int
	LockTokenBalance(common.Address, string, *uint256.Int)
	UnlockTokenBalance(common.Address, string, *uint256.Int)
	ConsumeLockTokenBalance(common.Address, string, *uint256.Int)
	AddTokenBalance(common.Address, string, *uint256.Int)
	SubTokenBalance(common.Address, string, *uint256.Int)
}