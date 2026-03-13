package types

import (
	"encoding/json"
	"github.com/ethereum/go-ethereum/common"
	"github.com/shopspring/decimal"
)

// MarshalJSON marshals as JSON.
func (t TokenTransferContext) MarshalJSON() ([]byte, error) {
	type TokenTransferTx struct {
		L1Owner common.Address `json:"l1owner"`
		To      common.Address `json:"to"`
		Value   string         `json:"value"`
		Token   string         `json:"token"`
	}
	var enc TokenTransferTx
	enc.L1Owner = t.L1Owner
	enc.To = t.To
	enc.Value = decimal.NewFromBigInt(t.Value, -ScalingExp).String()
	enc.Token = t.Token
	return json.Marshal(&enc)
}

// UnmarshalJSON unmarshals from JSON.
func (t *TokenTransferContext) UnmarshalJSON(input []byte) error {
	type TokenTransferTx struct {
		L1Owner *common.Address `json:"l1owner"`
		To      *common.Address `json:"to"`
		Value   *string         `json:"value"`
		Token   *string         `json:"token"`
	}
	var dec TokenTransferTx
	if err := json.Unmarshal(input, &dec); err != nil {
		return err
	}
	if dec.L1Owner != nil {
		t.L1Owner = *dec.L1Owner
	}
	if dec.To != nil {
		t.To = *dec.To
	}
	if dec.Value != nil {
		if decimal, err := decimal.NewFromString(*dec.Value); err != nil {
			return err
		} else {
			t.Value = decimal.Mul(ScalingDecimal).BigInt()
		}
	}
	if dec.Token != nil {
		t.Token = *dec.Token
	}
	return nil
}
