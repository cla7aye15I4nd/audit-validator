package swap

import (
	"math/big"

	"github.com/shopspring/decimal"
)

const (
	PairsSplitSep     = ","
	PairAssetSplitSet = ":"
)

type Config struct {
	Enable     bool   `json:"Enable"`
	ValueInUSD uint64 `json:"valueInUSD"` // 1 USD
	CMCAPIKey  string `json:"CMCAPIKey"`
	Pairs      string `json:"pairs"`
}

// GetAmountOfNEWValue1USD get the amount of NEW value in 1 USD
func GetAmountOfNEWValue1USD(CMCAPIKey string) (decimal.Decimal, error) {
	price, err := getCurrencyPrice(CMCAPIKey, CMCNewtonUCID)
	if err != nil {
		return decimal.Decimal{}, err
	}

	return decimal.NewFromUint64(1).Div(price), nil
}

// GetAmountOfNEWValueNUSD get the amount of NEW value in 1 USD
func GetAmountOfNEWValueNUSD(CMCAPIKey string, nUSD uint64) (decimal.Decimal, error) {
	valueOfNew1USD, err := GetAmountOfNEWValue1USD(CMCAPIKey)
	if err != nil {
		return decimal.Decimal{}, err
	}

	return valueOfNew1USD.Mul(decimal.NewFromUint64(nUSD)), nil
}

func GetSwapAmount(CMCAPIKey string, nUSD uint64) (*big.Int, error) {
	// TODO: force, only for NEW
	amountDecimal, err := GetAmountOfNEWValueNUSD(CMCAPIKey, nUSD)
	if err != nil {
		return nil, err
	}
	amount := amountDecimal.BigInt()

	amount.Mul(amount, big.NewInt(Fee))
	amount.Div(amount, big.NewInt(100))

	amount.Mul(amount, Big1NewInISAAC)

	return amount, nil
}

// newton

const (
	Precision     = 18
	CMCNewtonUCID = 3871

	Fee = 90 // 100
)

var (
	big10 = big.NewInt(10)

	// Big1NewInISAAC 1 NEW = 10^18 ISAAC
	Big1NewInISAAC = new(big.Int).Exp(big10, big.NewInt(Precision), nil)

	CapAmountOfNEWValue1USD = big.NewInt(0).Mul(big.NewInt(10000), Big1NewInISAAC) // 10000 NEW, 1 NEW = 0.0001 USD
)
