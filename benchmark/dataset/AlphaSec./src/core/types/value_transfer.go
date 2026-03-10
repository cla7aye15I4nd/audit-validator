package types

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/orderbook"
	"github.com/holiman/uint256"
)

type ValueTransferContext struct {
	L1Owner common.Address `json:"l1owner"`
	To      common.Address `json:"to"`
	Value   *big.Int       `json:"value"`
}

func (s *ValueTransferContext) command() byte        { return DexCommandTransfer }
func (s *ValueTransferContext) from() common.Address { return s.L1Owner }
func (s *ValueTransferContext) copy() DexCommandData {
	var valueCopy *big.Int
	if s.Value != nil {
		valueCopy = new(big.Int).Set(s.Value)
	}
	return &ValueTransferContext{s.L1Owner, s.To, valueCopy}
}
func (s *ValueTransferContext) Serialize() ([]byte, error) { return encode(s) }
func (s *ValueTransferContext) Deserialize(b []byte) error { return json.Unmarshal(b, s) }
func (s *ValueTransferContext) validate(sender common.Address, statedb BalanceGetter, orderbook orderbook.Dex, checker MarketChecker) error {
	if s.L1Owner == (common.Address{}) {
		return errors.New("sender address (From) is zero")
	}
	if s.Value == nil {
		return errors.New("value is nil")
	}
	if s.Value.Sign() < 0 {
		return errors.New("amount must be positive")
	}
	if s.Value != nil && s.Value.Cmp(uint256Max) > 0 {
		return errors.New("price exceeds uint256 max value")
	}
	return s.validateBalance(statedb)
}

func (s *ValueTransferContext) validateBalance(statedb BalanceGetter) error {
	balance := statedb.GetBalance(s.L1Owner)
	val := uint256.MustFromBig(s.Value)
	if balance.Cmp(val) < 0 {
		return fmt.Errorf("insufficient balance: have %s, need %s", balance.Dec(), val.Dec())
	}
	return nil
}

func (s *ValueTransferContext) Copy() *ValueTransferContext {
	if s == nil {
		return nil
	}
	return &ValueTransferContext{
		L1Owner: s.L1Owner,
		To:      s.To,
		Value:   new(big.Int).SetBytes(s.Value.Bytes()),
	}
}
