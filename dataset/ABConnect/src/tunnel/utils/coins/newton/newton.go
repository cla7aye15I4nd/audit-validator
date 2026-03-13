package newton

import (
	"bytes"
	"errors"
	"fmt"
	"math/big"

	"github.com/btcsuite/btcd/btcutil/base58"
	"github.com/ethereum/go-ethereum/common"
)

const (
	Name   = "AB"
	Symbol = "AB"
)

type Address struct {
	ChainId *big.Int
	Address common.Address
}

func New(chainID *big.Int, newAddress string) (Address, error) {
	var a Address
	if chainID == nil {
		return a, fmt.Errorf("chain id nil")
	}
	rawAddress, err := ToAddress(chainID, newAddress)
	if err != nil {
		return a, err
	}

	a.ChainId = chainID
	a.Address = rawAddress

	return a, nil
}

func (a Address) String() string {
	return ToNewton(a.ChainId.Bytes(), a.Address)
}

func ToNewton(chainID []byte, address common.Address) string {
	input := append(chainID, address.Bytes()...)
	return "NEW" + base58.CheckEncode(input, 0)
}

func ToAddress(chainID *big.Int, newAddress string) (common.Address, error) {
	if chainID == nil {
		return common.Address{}, errors.New("chain id nil")
	}
	if newAddress[:3] != "NEW" {
		return common.Address{}, errors.New("not NEW address")
	}

	decoded, version, err := base58.CheckDecode(newAddress[3:])
	if err != nil {
		return common.Address{}, err
	}
	if version != 0 {
		return common.Address{}, errors.New("illegal version")
	}
	if len(decoded) < 20 {
		return common.Address{}, errors.New("illegal decoded length")
	}
	if !bytes.Equal(decoded[:len(decoded)-20], chainID.Bytes()) {
		return common.Address{}, errors.New("illegal ChainID")
	}

	address := common.BytesToAddress(decoded[len(decoded)-20:])

	return address, nil
}

func IsNEWAddress(newAddress string) bool {
	if newAddress[:3] != "NEW" {
		return false
	}

	decoded, version, err := base58.CheckDecode(newAddress[3:])
	if err != nil {
		return false
	}
	if version != 0 {
		return false
	}
	if len(decoded) < 20 {
		return false
	}

	return true
}

func ToAddressUnsafe(newAddress string) (common.Address, error) {
	if newAddress[:3] != "NEW" {
		return common.Address{}, errors.New("not NEW address")
	}

	decoded, version, err := base58.CheckDecode(newAddress[3:])
	if err != nil {
		return common.Address{}, err
	}
	if version != 0 {
		return common.Address{}, errors.New("illegal version")
	}
	if len(decoded) < 20 {
		return common.Address{}, errors.New("illegal decoded length")
	}

	address := common.BytesToAddress(decoded[len(decoded)-20:])

	return address, nil
}
