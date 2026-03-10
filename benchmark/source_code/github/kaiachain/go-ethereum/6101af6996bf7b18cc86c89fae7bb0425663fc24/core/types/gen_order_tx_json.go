package types

import (
	"encoding/json"
	"github.com/ethereum/go-ethereum/common"
	"github.com/shopspring/decimal"
)

// MarshalJSON marshals as JSON.
func (o OrderContext) MarshalJSON() ([]byte, error) {
	type TPSLContext struct {
		TPLimit   string `json:"tpLimit"`
		SLTrigger string `json:"slTrigger"`
		SLLimit   string `json:"slLimit,omitempty"` // optional, if not set, SL is market order
	}
	type OrderContext struct {
		L1Owner    common.Address `json:"l1owner"`
		UserID     string         `json:"userId"`
		BaseToken  string         `json:"baseToken"`
		QuoteToken string         `json:"quoteToken"`
		Side       uint8          `json:"side"`
		Price      string         `json:"price"`
		Quantity   string         `json:"quantity"`
		OrderType  uint8          `json:"orderType"`
		OrderMode  uint8          `json:"orderMode,omitempty"`
		TPSL       *TPSLContext   `json:"tpsl,omitempty"`
	}

	var enc OrderContext
	enc.L1Owner = o.L1Owner
	enc.BaseToken = o.BaseToken
	enc.QuoteToken = o.QuoteToken
	enc.Side = o.Side
	enc.Price = decimal.NewFromBigInt(o.Price, -ScalingExp).String()
	enc.Quantity = decimal.NewFromBigInt(o.Quantity, -ScalingExp).String()
	enc.OrderType = o.OrderType
	enc.OrderMode = o.OrderMode
	if o.TPSL != nil {
		tpsl := &TPSLContext{}
		tpsl.TPLimit = decimal.NewFromBigInt(o.TPSL.TPLimit, -ScalingExp).String()
		tpsl.SLTrigger = decimal.NewFromBigInt(o.TPSL.SLTrigger, -ScalingExp).String()
		if o.TPSL.SLLimit != nil {
			tpsl.SLLimit = decimal.NewFromBigInt(o.TPSL.SLLimit, -ScalingExp).String()
		}
		enc.TPSL = tpsl
	}
	return json.Marshal(&enc)
}

// UnmarshalJSON unmarshals from JSON.
func (o *OrderContext) UnmarshalJSON(input []byte) error {
	type TPSLContextAlias struct {
		TPLimit   *string `json:"tpLimit"`
		SLTrigger *string `json:"slTrigger"`
		SLLimit   *string `json:"slLimit,omitempty"` // optional, if not set, SL is market order
	}
	type OrderContext struct {
		L1Owner    *common.Address   `json:"l1owner"`
		UserID     *string           `json:"userId"`
		BaseToken  *string           `json:"baseToken"`
		QuoteToken *string           `json:"quoteToken"`
		Side       *uint8            `json:"side"`
		Price      *string           `json:"price"`
		Quantity   *string           `json:"quantity"`
		OrderType  *uint8            `json:"orderType"`
		OrderMode  *uint8            `json:"orderMode,omitempty"`
		TPSL       *TPSLContextAlias `json:"tpsl,omitempty"`
	}
	var dec OrderContext
	if err := json.Unmarshal(input, &dec); err != nil {
		return err
	}
	if dec.L1Owner != nil {
		o.L1Owner = *dec.L1Owner
	}
	if dec.BaseToken != nil {
		o.BaseToken = *dec.BaseToken
	}
	if dec.QuoteToken != nil {
		o.QuoteToken = *dec.QuoteToken
	}
	if dec.Side != nil {
		o.Side = *dec.Side
	}
	if dec.Price != nil {
		if decimal, err := decimal.NewFromString(*dec.Price); err != nil {
			return err
		} else {
			o.Price = decimal.Mul(ScalingDecimal).BigInt()
		}
	}
	if dec.Quantity != nil {
		if decimal, err := decimal.NewFromString(*dec.Quantity); err != nil {
			return err
		} else {
			o.Quantity = decimal.Mul(ScalingDecimal).BigInt()
		}
	}
	if dec.OrderType != nil {
		o.OrderType = *dec.OrderType
	}
	if dec.OrderMode != nil {
		o.OrderMode = *dec.OrderMode
	}
	if dec.TPSL != nil {
		tpsl := &TPSLContext{}
		if dec.TPSL.TPLimit != nil {
			if decimal, err := decimal.NewFromString(*dec.TPSL.TPLimit); err != nil {
				return err
			} else {
				tpsl.TPLimit = decimal.Mul(ScalingDecimal).BigInt()
			}
		}
		if dec.TPSL.SLTrigger != nil {
			if decimal, err := decimal.NewFromString(*dec.TPSL.SLTrigger); err != nil {
				return err
			} else {
				tpsl.SLTrigger = decimal.Mul(ScalingDecimal).BigInt()
			}
		}
		if dec.TPSL.SLLimit != nil {
			if decimal, err := decimal.NewFromString(*dec.TPSL.SLLimit); err != nil {
				return err
			} else {
				tpsl.SLLimit = decimal.Mul(ScalingDecimal).BigInt()
			}
		}
		o.TPSL = tpsl
	}
	return nil
}
