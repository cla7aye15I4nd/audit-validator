package utils

import (
	"errors"
	"math/big"
	"strings"
)

type Amount string

func New(value string) (Amount, error) {
	if value == "" {
		return "0", nil
	}
	_, err := GetAmountISAACFromText(value)
	if err != nil {
		return "", err
	}

	return Amount(value), nil
}

func FromBigInt(value *big.Int) Amount {
	if value == nil {
		return "0"
	}
	return Amount(GetAmountTextFromISAAC(value))
}

func (v *Amount) String() string {
	if *v == "" {
		return "0"
	}
	return string(*v)
}

func (v *Amount) BigInt() (*big.Int, error) {
	if *v == "" {
		return big.NewInt(0), nil
	}
	return GetAmountISAACFromText(string(*v))
}

// Add return v + x
func (v *Amount) Add(x Amount) (Amount, error) {
	xBig, err := x.BigInt()
	if err != nil {
		return "", err
	}
	vBig, err := v.BigInt()
	if err != nil {
		return "", err
	}
	return Amount(GetAmountTextFromISAAC(big.NewInt(0).Add(vBig, xBig))), nil
}

// Sub return v - x
func (v *Amount) Sub(x Amount) (Amount, error) {
	xBig, err := x.BigInt()
	if err != nil {
		return "", err
	}
	vBig, err := v.BigInt()
	if err != nil {
		return "", err
	}
	if vBig.Cmp(xBig) < 0 {
		return "", errors.New("ExValue v is less than x")
	}
	return Amount(GetAmountTextFromISAAC(big.NewInt(0).Sub(vBig, xBig))), nil
}

// Div return v / x
func (v *Amount) Div(x Amount) (Amount, error) {
	xBig, err := x.BigInt()
	if err != nil {
		return "", err
	}
	if xBig.Cmp(big.NewInt(0)) == 0 {
		return "", errors.New("x cannot be zero")
	}
	vBig, err := v.BigInt()
	if err != nil {
		return "", err
	}
	yBig := big.NewInt(0).Div(big.NewInt(0).Mul(vBig, Big1NewInISAAC), xBig)
	return Amount(GetAmountTextFromISAAC(yBig)), nil
}

// Mul return v * x
func (v *Amount) Mul(x Amount) (Amount, error) {
	xBig, err := x.BigInt()
	if err != nil {
		return "", err
	}
	vBig, err := v.BigInt()
	if err != nil {
		return "", err
	}
	yBig := big.NewInt(0).Mul(vBig, xBig)
	yBig = yBig.Div(yBig, Big1NewInISAAC)
	return Amount(GetAmountTextFromISAAC(yBig)), nil
}

// Cmp compares v and y and returns:
//
//   -1 if v <  y
//    0 if v == y
//   +1 if v >  y
//
func (v *Amount) Cmp(x Amount) (int, error) {
	xBig, err := x.BigInt()
	if err != nil {
		return 0, err
	}
	vBig, err := v.BigInt()
	if err != nil {
		return 0, err
	}
	cmp := vBig.Cmp(xBig)

	return cmp, nil
}

// =============================
// functions

const (
	Precision = 18
)

var (
	big10 = big.NewInt(10)

	// Big1NewInISAAC 1 NEW = 10^18 ISAAC
	Big1NewInISAAC = new(big.Int).Exp(big10, big.NewInt(Precision), nil)
)

// GetAmountTextFromISAAC convert 10000000000 ISAAC to 1 NEW
func GetAmountTextFromISAAC(amount *big.Int) string {
	return GetAmountTextFromISAACWithDecimals(amount, Precision)
}

// GetAmountISAACFromText convert 1 NEW to 10000000000 ISAAC
func GetAmountISAACFromText(amountStr string) (*big.Int, error) {
	return GetAmountISAACFromTextWithDecimals(amountStr, Precision)
}

func GetAmountTextFromISAACWithDecimals(amount *big.Int, decimals uint8) string {
	return getAmountTextFromISAACWithDecimals(amount, int(decimals))
}

func getAmountTextFromISAACWithDecimals(amount *big.Int, decimals int) string {
	if decimals <= 0 {
		return amount.String()
	}
	if amount == nil {
		return "0"
	}
	amountStr := amount.String()
	amountStrLen := len(amountStr)

	var amountStrDec, amountStrInt string
	if amountStrLen <= decimals {
		amountStrDec = strings.Repeat("0", decimals-amountStrLen) + amountStr
		amountStrInt = "0"
	} else {
		amountStrDec = amountStr[amountStrLen-decimals:]
		amountStrInt = amountStr[:amountStrLen-decimals]
	}
	amountStrDec = strings.TrimRight(amountStrDec, "0")
	if len(amountStrDec) <= 0 {
		return amountStrInt
	}

	return amountStrInt + "." + amountStrDec
}

// GetAmountISAACFromText convert 1 NEW to 10000000000 ISAAC
func GetAmountISAACFromTextWithDecimals(amountStr string, decimals uint8) (*big.Int, error) {
	return getAmountISAACFromTextWithDecimals(amountStr, int(decimals))
}

func getAmountISAACFromTextWithDecimals(amountStr string, decimals int) (*big.Int, error) {
	index := strings.IndexByte(amountStr, '.')
	if index <= 0 {
		amountISAAC, ok := new(big.Int).SetString(amountStr, 10)
		if !ok {
			return nil, errors.New("convert string to big error")
		}
		return new(big.Int).Mul(amountISAAC, new(big.Int).Exp(big10, big.NewInt(int64(decimals)), nil)), nil
	}
	amountStrInt := amountStr[:index]
	amountStrDec := amountStr[index+1:]
	amountStrDecLen := len(amountStrDec)
	if amountStrDecLen > decimals {
		return nil, errors.New("convert string to big error")
	}
	amountStrDec = amountStrDec + strings.Repeat("0", decimals-amountStrDecLen)
	amountStrInt = amountStrInt + amountStrDec

	amountStrIntBig, ok := new(big.Int).SetString(amountStrInt, 10)
	if !ok {
		return nil, errors.New("convert string to big error")
	}

	return amountStrIntBig, nil
}
