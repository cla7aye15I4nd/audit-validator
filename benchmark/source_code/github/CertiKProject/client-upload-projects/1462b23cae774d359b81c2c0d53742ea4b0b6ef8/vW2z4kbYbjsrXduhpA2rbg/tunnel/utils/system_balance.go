package utils

import "math/big"

type AssetBalance struct {
	AssetId uint64

	BlockchainId uint64 `db:"blockchain_id"`
	Asset        string `db:"asset"`

	Name      string `db:"name"`
	Symbol    string `db:"symbol"`
	Decimals  uint8  `db:"decimals"`
	Attribute uint64 `db:"attribute"`
	AssetType string `db:"asset_type"`

	Network   string
	ChainId   string
	BaseChain string
	Slug      string

	TotalDeposit         *big.Int
	TotalWithdraw        *big.Int
	TotalDepositLastDay  *big.Int
	TotalWithdrawLastDay *big.Int
	TotalFee             *big.Int
}
