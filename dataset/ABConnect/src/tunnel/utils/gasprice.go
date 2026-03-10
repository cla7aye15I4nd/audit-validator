package utils

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"reflect"
	"strings"

	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

/*
 * GetGasPrice return the gas price

	APIUrl        string
	Filed         string
	WeiMultiplier uint64

 * APIUrl: https://ethgasstation.info/api/ethgasAPI.json
 * Filed: average
 * FiledType: int
 * WeiMultiplier: 100000000

 * APIUrl: https://api.etherscan.io/api?module=gastracker&action=gasoracle
 * Filed: result.ProposeGasPrice
 * FiledType: string
 * WeiMultiplier: 1000000000

 * APIUrl: https://www.gasnow.org/api/v3/gas/price?utm_source=NewBridge
 * Filed: data.fast
 * FiledType: int
 * WeiMultiplier: 1
*/

func GetGasPrice(gs *config.GasStation) (*big.Int, error) {
	if gs == nil {
		return nil, errors.New("gas station not set")
	}

	fields := strings.Split(gs.Filed, ".")
	if len(fields) < 1 || (len(fields) == 1 && fields[0] == "") {
		return nil, fmt.Errorf("field(%s) parse error", gs.Filed)
	}

	ft := strings.ToLower(gs.FiledType)
	if ft != "string" && ft != "int" {
		return nil, fmt.Errorf("FiledType(%v) error, only `string` or `int`", gs.FiledType)
	}

	if gs.WeiMultiplier < 1 {
		return nil, fmt.Errorf("WeiMultiplier set error: %v", gs.WeiMultiplier)
	}

	res, err := http.Get(gs.APIUrl)
	if err != nil {
		return nil, err
	}
	if res.Body != nil {
		defer res.Body.Close()
	}

	ret := make(map[string]interface{})
	err = json.NewDecoder(res.Body).Decode(&ret)
	if err != nil {
		return nil, err
	}

	// "data.slow"
	f, ok := ret[fields[0]]
	if !ok {
		return nil, fmt.Errorf("filed0(%s) not found", fields[0])
	}
	for i := 1; i < len(fields); i++ {
		fm, ok := f.(map[string]interface{})
		if !ok {
			return nil, fmt.Errorf("filed(%s) not object", fields[i-1])
		}

		f, ok = fm[fields[i]]
		if !ok {
			return nil, fmt.Errorf("filed(%s) not found", fields[i])
		}
	}

	gasPrice := big.NewInt(0)
	if ft == "string" {
		fs, ok := f.(string)
		if !ok {
			return nil, fmt.Errorf("filed of gas price not string: %v", fs)
		}
		_, ok = gasPrice.SetString(fs, 10)
		if !ok {
			return nil, fmt.Errorf("convert string to big int error: %v", fs)
		}
	} else {
		var fi int64
		switch reflect.TypeOf(f).Kind() {
		case reflect.Float64:
			ff64 := f.(float64)
			fi = int64(ff64)
		case reflect.Float32:
			ff32 := f.(float32)
			fi = int64(ff32)
		case reflect.Int64:
			fi = f.(int64)
		case reflect.Int32:
			fi32 := f.(int32)
			fi = int64(fi32)
		case reflect.Int:
			fi32 := f.(int32)
			fi = int64(fi32)
		default:
			return nil, fmt.Errorf("filed of gas price not int: %v (%v)", fi, reflect.TypeOf(fi))
		}
		gasPrice.SetInt64(fi)
	}

	gasPrice.Mul(gasPrice, big.NewInt(0).SetUint64(gs.WeiMultiplier))

	if gasPrice.Cmp(big.NewInt(0)) <= 0 {
		return nil, fmt.Errorf("get gas price error: %v", gasPrice.String())
	}

	return gasPrice, nil
}
