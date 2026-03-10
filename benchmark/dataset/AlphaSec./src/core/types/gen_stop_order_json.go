package types

import (
	"encoding/json"
	"github.com/ethereum/go-ethereum/common"
	"github.com/shopspring/decimal"
)

// MarshalJSON marshals as JSON.
func (s StopOrderContext) MarshalJSON() ([]byte, error) {
	type StopOrder struct {
		L1Owner    common.Address `json:"l1owner"`
		BaseToken  string         `json:"baseToken"`
		QuoteToken string         `json:"quoteToken"`
		StopPrice  string         `json:"stopPrice"`
		Price      string         `json:"price"`
		Quantity   string         `json:"quantity"`
		Side       uint8          `json:"side"`
		OrderType  uint8          `json:"orderType"`
		OrderMode  uint8          `json:"orderMode,omitempty"`
	}
	var enc StopOrder
	enc.L1Owner = s.L1Owner
	enc.BaseToken = s.BaseToken
	enc.QuoteToken = s.QuoteToken
	enc.StopPrice = decimal.NewFromBigInt(s.StopPrice, -ScalingExp).String()
	enc.Price = decimal.NewFromBigInt(s.Price, -ScalingExp).String()
	enc.Quantity = decimal.NewFromBigInt(s.Quantity, -ScalingExp).String()
	enc.Side = s.Side
	enc.OrderType = s.OrderType
	enc.OrderMode = s.OrderMode
	return json.Marshal(&enc)
}

// UnmarshalJSON unmarshals from JSON.
func (s *StopOrderContext) UnmarshalJSON(input []byte) error {
	type StopOrder struct {
		L1Owner    *common.Address `json:"l1owner"`
		BaseToken  *string         `json:"baseToken"`
		QuoteToken *string         `json:"quoteToken"`
		StopPrice  *string         `json:"stopPrice"`
		Price      *string         `json:"price"`
		Quantity   *string         `json:"quantity"`
		Side       *uint8          `json:"side"`
		OrderType  *uint8          `json:"orderType"`
		OrderMode  *uint8          `json:"orderMode,omitempty"`
	}
	var dec StopOrder
	if err := json.Unmarshal(input, &dec); err != nil {
		return err
	}
	if dec.L1Owner != nil {
		s.L1Owner = *dec.L1Owner
	}
	if dec.BaseToken != nil {
		s.BaseToken = *dec.BaseToken
	}
	if dec.QuoteToken != nil {
		s.QuoteToken = *dec.QuoteToken
	}
	if dec.StopPrice != nil {
		if stopPrice, err := decimal.NewFromString(*dec.StopPrice); err != nil {
			return err
		} else {
			s.StopPrice = stopPrice.Mul(ScalingDecimal).BigInt()
		}
	}
	if dec.Price != nil {
		if price, err := decimal.NewFromString(*dec.Price); err != nil {
			return err
		} else {
			s.Price = price.Mul(ScalingDecimal).BigInt()
		}
	}
	if dec.Quantity != nil {
		if quantity, err := decimal.NewFromString(*dec.Quantity); err != nil {
			return err
		} else {
			s.Quantity = quantity.Mul(ScalingDecimal).BigInt()
		}
	}
	if dec.Side != nil {
		s.Side = *dec.Side
	}
	if dec.OrderType != nil {
		s.OrderType = *dec.OrderType
	}
	if dec.OrderMode != nil {
		s.OrderMode = *dec.OrderMode
	}
	return nil
}
