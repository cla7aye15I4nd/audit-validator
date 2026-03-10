package utils

import (
	"encoding/hex"
	"errors"

	"github.com/ethereum/go-ethereum/common"
)

func AddressToEthereum(address common.Address) string {
	return "0x" + hex.EncodeToString(address.Bytes()) // must lower
}

func EthereumToAddress(ethAddress string) (common.Address, error) {
	if !common.IsHexAddress(ethAddress) {
		return common.Address{}, errors.New("invalid hex address")
	}

	return common.HexToAddress(ethAddress), nil
}
