package chain

import (
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"

	dbtcutil "github.com/dogecoinw/doged/btcutil"
	"github.com/dogecoinw/doged/chaincfg/chainhash"
)

// BlockBook Client
// https://github.com/trezor/blockbook/blob/master/docs/api.md

type BlockBookClient struct {
	baseURL string
	c       *http.Client
}

func NewBlockBookClient(baseURL string) *BlockBookClient {
	return &BlockBookClient{
		baseURL: baseURL,
		c:       http.DefaultClient,
	}
}

// [{"txid":"2a5389c4645a55f1b7b6d3db8513cf7fac8a0ec7237ed3c554122fd844d72d42","vout":1,"value":"830000000","height":5020466,"confirmations":2586,"scriptPubKey":"76a914b8ca22cb46e8e4ab9bbdbd9991e5c543bd88e8ef88ac"}]
type UTXO struct {
	Id            uint64         `json:"id",db:"id,omitempty"`
	Txid          chainhash.Hash `json:"txid"`
	Vout          uint32         `json:"vout"`
	Value         *big.Int       `json:"value"`
	Height        uint64         `json:"height"`
	Confirmations uint64         `json:"confirmations"`
	ScriptPubKey  string         `json:"scriptPubKey"`
	LockTime      int64          `json:"lockTime,omitempty"`
}

type UTXOs []*UTXO

func (u *UTXO) UnmarshalJSON(data []byte) error {
	type Alias UTXO
	a := &struct {
		Value string `json:"value"`
		*Alias
	}{
		Alias: (*Alias)(u),
	}

	if err := json.Unmarshal(data, &a); err != nil {
		return err
	}

	value := big.NewInt(0)
	if a.Value != "" {
		_, ok := value.SetString(a.Value, 10)
		if !ok {
			return fmt.Errorf("invalid value for big.Int")
		}
	}
	u.Value = value

	return nil
}

func (bb *BlockBookClient) GetAllUTXOs(address dbtcutil.Address) (UTXOs, error) {
	url := fmt.Sprintf("%s/api/v2/utxo/%s?confirmed=true", bb.baseURL, address.String())
	resp, err := bb.c.Get(url)
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

	b := make(UTXOs, 0)
	err = json.Unmarshal(body, &b)
	if err != nil {
		return nil, err
	}

	return b, nil
}

type BlockBookParams struct {
	Tick           string `json:"tick"`
	ReceiveAddress string `json:"receive_address"`
}

type BlockBookResult struct {
	Tick        string   `json:"tick"`
	Amt         *big.Int `json:"amt"`
	Inscription string   `json:"inscription"`
}

func (bb *BlockBookClient) Balance(address dbtcutil.Address) (*big.Int, error) {
	UTXOs, err := bb.GetAllUTXOs(address)
	if err != nil {
		return nil, err
	}

	balance := big.NewInt(0)
	for _, utxo := range UTXOs {
		balance.Add(balance, utxo.Value)
	}

	return balance, nil
}

// TxRawResult models the data from the getrawtransaction command.
type TxRawResult struct {
	Txid          string `json:"txid"`
	Version       uint32 `json:"version"`
	BlockHash     string `json:"blockhash,omitempty"`
	Confirmations uint64 `json:"confirmations,omitempty"`
	Blocktime     int64  `json:"blocktime,omitempty"`
}

func (bb *BlockBookClient) GetTx(txHash *chainhash.Hash) (*TxRawResult, error) {
	url := fmt.Sprintf("%s/api/v2/tx/%s?confirmed=true", bb.baseURL, txHash.String())
	resp, err := bb.c.Get(url)
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

	var tx TxRawResult
	err = json.Unmarshal(body, &tx)
	if err != nil {
		return nil, err
	}

	return &tx, nil
}
