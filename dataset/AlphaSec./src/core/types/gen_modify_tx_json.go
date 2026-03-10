package types

import (
	"encoding/json"
	"github.com/ethereum/go-ethereum/common"
	"github.com/shopspring/decimal"
)

// MarshalJSON marshals as JSON.
func (m ModifyContext) MarshalJSON() ([]byte, error) {
	type ModifyTx struct {
		L1Owner   common.Address `json:"l1owner"`
		OrderID   common.Hash    `json:"orderId"`
		NewPrice  string         `json:"newPrice"`
		NewQty    string         `json:"newQty"`
		OrderMode uint8          `json:"orderMode,omitempty"`
	}
	var enc ModifyTx
	enc.L1Owner = m.L1Owner
	enc.OrderID = m.OrderID
	enc.NewPrice = decimal.NewFromBigInt(m.NewPrice, -ScalingExp).String()
	enc.NewQty = decimal.NewFromBigInt(m.NewQty, -ScalingExp).String()
	enc.OrderMode = m.OrderMode
	return json.Marshal(&enc)
}

// UnmarshalJSON unmarshals from JSON.
func (m *ModifyContext) UnmarshalJSON(input []byte) error {
	type ModifyTx struct {
		L1Owner   *common.Address `json:"l1owner"`
		OrderID   *common.Hash    `json:"orderId"`
		NewPrice  *string         `json:"newPrice"`
		NewQty    *string         `json:"newQty"`
		OrderMode *uint8          `json:"orderMode,omitempty"`
	}
	var dec ModifyTx
	if err := json.Unmarshal(input, &dec); err != nil {
		return err
	}
	if dec.L1Owner != nil {
		m.L1Owner = *dec.L1Owner
	}
	if dec.OrderID != nil {
		m.OrderID = *dec.OrderID
	}
	if dec.NewPrice != nil {
		if decimal, err := decimal.NewFromString(*dec.NewPrice); err != nil {
			return err
		} else {
			m.NewPrice = decimal.Mul(ScalingDecimal).BigInt()
		}
	}
	if dec.NewQty != nil {
		if decimal, err := decimal.NewFromString(*dec.NewQty); err != nil {
			return err
		} else {
			m.NewQty = decimal.Mul(ScalingDecimal).BigInt()
		}
	}
	if dec.OrderMode != nil {
		m.OrderMode = *dec.OrderMode
	}
	return nil
}
