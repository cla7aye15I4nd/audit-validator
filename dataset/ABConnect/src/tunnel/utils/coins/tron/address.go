package tron

import (
	"encoding/hex"
	"encoding/json"
	"fmt"

	"github.com/btcsuite/btcd/btcutil/base58"
	"github.com/ethereum/go-ethereum/common"
)

type Address struct {
	common.Address
}

var ZeroAddress = Address{Address: common.Address{}}

func NewAddress(tronAddress string) (Address, error) {
	var a Address

	result, version, err := base58.CheckDecode(tronAddress)
	if err != nil {
		return a, err
	}

	if version != GetNetWork()[0] {
		return a, fmt.Errorf("version error")
	}

	address := common.BytesToAddress(result)
	a.Address = address

	return a, nil
}

func IsTronAddress(tronAddress string) bool {
	result, version, err := base58.CheckDecode(tronAddress)
	if err != nil {
		return false
	}

	if version != GetNetWork()[0] {
		return false
	}

	if len(result) != 20 {
		return false
	}

	return true
}

// has0xPrefix validates str begins with '0x' or '0X'.
func has0xPrefix(str string) bool {
	return len(str) >= 2 && str[0] == '0' && (str[1] == 'x' || str[1] == 'X')
}

// hasVersion validates str begins with '41'.
func hasVersion(str string) bool {
	return len(str) >= 2 && str[0] == '4' && str[1] == '1'
}

func HexToAddress(s string) (Address, error) {
	if common.IsHexAddress(s) {
		return Address{common.HexToAddress(s)}, nil
	}
	if len(s) == 2*common.AddressLength+2 && hasVersion(s) {
		s = s[2:]
	}
	if common.IsHexAddress(s) {
		return Address{common.HexToAddress(s)}, nil
	}

	return ZeroAddress, fmt.Errorf("invalid address")

}

func BytesToAddress(b []byte) (Address, error) {
	return HexToAddress(hex.EncodeToString(b))
}

func (a Address) String() string {
	return base58.CheckEncode(a.Address.Bytes(), GetNetWork()[0])
}

func (a Address) Hex() string {
	return hex.EncodeToString(append(GetNetWork(), a.Address.Bytes()...))
}

func (a Address) MarshalJSON() ([]byte, error) { return json.Marshal(a.String()) }

func (a *Address) UnmarshalJSON(input []byte) error {
	var addrStr string
	if err := json.Unmarshal(input, &addrStr); err != nil {
		return err
	}

	addr, err := NewAddress(addrStr)
	if err != nil {
		return err
	}
	a.Address = addr.Address
	return nil
}
