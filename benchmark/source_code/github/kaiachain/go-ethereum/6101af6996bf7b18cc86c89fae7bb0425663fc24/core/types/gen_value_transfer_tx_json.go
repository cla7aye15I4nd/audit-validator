package types

import (
	"encoding/json"
	"github.com/ethereum/go-ethereum/common"
	"github.com/shopspring/decimal"
)

// MarshalJSON marshals as JSON.
func (v ValueTransferContext) MarshalJSON() ([]byte, error) {
	type ValueTransferTx struct {
		L1Owner common.Address `json:"l1owner"`
		To      common.Address `json:"to"`
		Value   string         `json:"value"`
	}
	var enc ValueTransferTx
	enc.L1Owner = v.L1Owner
	enc.To = v.To
	enc.Value = decimal.NewFromBigInt(v.Value, -ScalingExp).String()
	return json.Marshal(&enc)
}

// UnmarshalJSON unmarshals from JSON.
func (v *ValueTransferContext) UnmarshalJSON(input []byte) error {
	type ValueTransferTx struct {
		L1Owner *common.Address `json:"l1owner"`
		To      *common.Address `json:"to"`
		Value   *string         `json:"value"`
	}
	var dec ValueTransferTx
	if err := json.Unmarshal(input, &dec); err != nil {
		return err
	}
	if dec.L1Owner != nil {
		v.L1Owner = *dec.L1Owner
	}
	if dec.To != nil {
		v.To = *dec.To
	}
	if dec.Value != nil {
		if decimal, err := decimal.NewFromString(*dec.Value); err != nil {
			return err
		} else {
			v.Value = decimal.Mul(ScalingDecimal).BigInt()
		}
	}
	return nil
}
