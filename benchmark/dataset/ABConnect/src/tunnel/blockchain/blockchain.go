package blockchain

import (
	"strings"
)

// BlockChain type
type BlockChain int

const (
	UnknownChain BlockChain = iota
	NewChain
	Ethereum
	Bitcoin
	Dogecoin
	Tron
	Solana
	Cosmos
)

func (bc BlockChain) String() string {
	switch bc {
	case NewChain:
		return "NewChain"
	case Ethereum:
		return "Ethereum"
	case Bitcoin:
		return "Bitcoin"
	case Dogecoin:
		return "Dogecoin"
	case Tron:
		return "Tron"
	}

	return "UnknownChain"
}

// func New() (BlockChain, error) {
// 	return UnknownChain, nil
// }

func Parse(bcStr string) BlockChain {

	var bc BlockChain

	switch strings.ToLower(bcStr) {
	case "newchain", "new", "newton", "ab":
		bc = NewChain
	case "ethereum", "eth":
		bc = Ethereum
	case "bitcoin", "btc":
		bc = Bitcoin
	case "dogecoin", "doge":
		bc = Dogecoin
	case "tron":
		bc = Tron
	default:
		bc = UnknownChain
	}

	return bc
}
