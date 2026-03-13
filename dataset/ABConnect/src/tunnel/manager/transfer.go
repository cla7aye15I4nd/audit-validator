package manager

import (
	"math/big"

	"github.com/ethereum/go-ethereum/common"
)

type Transaction struct {
	From     common.Address
	To       common.Address
	Value    *big.Int
	Data     []byte
	GasLimit uint64
	GasPrice *big.Int
	Nonce    uint64
}

type Token struct {
	AssetId   uint64
	Address   common.Address
	Name      string
	Symbol    string
	Decimals  uint8
	Attribute int
	BalanceOf BalanceOf
}
