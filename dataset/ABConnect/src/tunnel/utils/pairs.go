package utils

import (
	"math/big"
)

const FeeBase = int64(1000000)

const (
	AttributeTransfer           = 0b0
	AttributeMintable           = 0b1
	AttributeBurnable           = 0b10
	AttributePrechargedTransfer = 0b100 // Asset requires pre-funding before being transferred to users
)

const (
	WithdrawMainAddress = "WithdrawMainAddress"
	ColdAddress         = "ColdAddress"
	ColdAddresses       = "ColdAddresses" // list of used cold address
	ColdAddressesSplit  = ","
	FeeAddress          = "FeeAddress"

	LatestBlockHeight = "LatestBlockHeight"
)

type Token struct {
	Address            string
	Name               string
	Symbol             string
	Decimals           uint8
	MinDepositAmount   *big.Int
	WithdrawFeePercent uint64
	WithdrawFeeMin     *big.Int
}

type Pair struct {
	Id        uint64
	DogeToken *Token
	EthToken  *Token
}

const (
	AssetTypeCoin  = 1
	AssetTypeToken = 2
	AssetTypeERC20 = 3
	AssetTypeNRC6  = 4

	AssetTypeBRC20 = 100
	AssetTypeDRC20 = 101
)

var AssetTypeText = map[int]string{
	AssetTypeCoin:  "Coin",
	AssetTypeToken: "Token",
	AssetTypeERC20: "ERC-20",
	AssetTypeNRC6:  "NRC-6",

	AssetTypeBRC20: "BRC-20",
	AssetTypeDRC20: "DRC-20",
}

const (
	SymbolOfNewton = iota
	SymbolOfEthereum
	SymbolOfHecoChain
	SymbolOfBinanceSmartChain
)

var SymbolMap = map[string]int{
	"new":  SymbolOfNewton,
	"eth":  SymbolOfEthereum,
	"heco": SymbolOfHecoChain,
	"bsc":  SymbolOfBinanceSmartChain,
}
