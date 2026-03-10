package chain

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"

	dbtcutil "github.com/dogecoinw/doged/btcutil"
)

// indexer

const JSONContentType = "application/json"

type DRC20Client struct {
	baseURL string
	c       *http.Client
}

func NewDRC20Client(baseURL string) *DRC20Client {
	return &DRC20Client{
		baseURL: baseURL,
		c:       http.DefaultClient,
	}
}

func (d *DRC20Client) Balance(tick string, address dbtcutil.Address) (*big.Int, error) {
	p := BalanceParams{
		Tick:           tick,
		ReceiveAddress: address.String(),
	}
	pb, err := json.Marshal(p)
	if err != nil {
		return nil, err
	}
	url := fmt.Sprintf("%s/v3/drc20/address/tick", d.baseURL)
	resp, err := d.c.Post(url, JSONContentType, bytes.NewBuffer(pb))
	if err != nil {
		return nil, err
	}
	if resp.Body == nil {
		return nil, fmt.Errorf("body is nil")
	}
	defer resp.Body.Close()

	// Read the response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Fatal(err)
	}

	var b BalanceResult
	err = json.Unmarshal(body, &b)
	if err != nil {
		return nil, err
	}
	if b.Code != 200 || b.Msg != "success" {
		return nil, fmt.Errorf("get balance error")
	}
	if b.Data == nil {
		return big.NewInt(0), nil
	}
	if b.Data.Tick != tick {
		return nil, fmt.Errorf("get balance tick error")
	}

	return b.Data.Amt, nil
}

type BalanceParams struct {
	Tick           string `json:"tick"`
	ReceiveAddress string `json:"receive_address"`
}

// {"code":200,"msg":"success","data":null,"total":0}
// {"code":200,"msg":"success","data":{"tick":"WDOGE(WRAPPED-DOGE)","amt":33400000000,"inscription":"Xi0"},"total":0}
type BalanceResult struct {
	Code  int                `json:"code"`
	Msg   string             `json:"msg"`
	Data  *BalanceResultData `json:"data"`
	Total int64              `json:"total"`
}

type BalanceResultData struct {
	Tick        string   `json:"tick"`
	Amt         *big.Int `json:"amt"`
	Inscription string   `json:"inscription"`
}
