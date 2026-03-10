package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/big"

	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/swap"

	"github.com/upper/db/v4/adapter/mysql"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
)

// Direction A2B or B2A
type Direction int

const (
	DirectionA2B Direction = 1
	DirectionB2A Direction = 2
)

type ChainConfig struct {
	ChainAPIHost string `json:"ChainAPIHost"` // Host of coin API
	RpcURL       string `json:"RpcURL"`       // Node

	// Blockchain
	Slug         string                `json:"Slug"` // PRIMARY KEY, slug to replace blockchain id
	Network      string                `json:"Network"`
	ChainId      string                `json:"ChainId,omitempty"`
	BaseChain    blockchain.BlockChain `json:"BaseChain,omitempty"`
	BlockchainId uint64                `json:"BlockchainId,omitempty"`

	// database
	DB *ConnectionURL `json:"Db,omitempty" "mapstructure":"db"`

	WithdrawMainAddress Address `json:",omitempty"`
	ColdAddress         Address `json:",omitempty"`

	DelayBlockNumber   uint64 `json:"DelayBlockNumber,omitempty"`
	RateLimitPerMinute uint64 `json:"RateLimitPerMinute,omitempty"`

	// kms
	ChainKeyId            string `json:"ChainKeyId"` // use to encrypt/decrypt
	ChainAPISignKeyId     string `json:"ChainAPISignKeyId"`
	ChainTaskSignKeyId    string `json:"ChainTaskSignKeyId"`
	ChainManagerSignKeyId string `json:"ChainManagerSignKeyId"` // merge
	MonitorSignKeyId      string `json:"MonitorSignKeyId"`      // for both monitor and monitor detected

	/* The follow is base on blockchain.
	TODO: this is not recommended, replace this config with something like types.Transaction
	*/

	// Ethereum
	MaxGasPrice *big.Int    `json:"MaxGasPrice,omitempty"`
	GasPrice    *GasStation `json:"GasPrice,omitempty"`

	// Dogecoin
	Username     string `json:"Username,omitempty"` // Node RPCURL
	Password     string `json:"Password,omitempty"` // Node RPCURL
	IndexerURL   string `json:"IndexerURL,omitempty"`
	BlockbookURL string `json:"BlockbookURL,omitempty"`
}

func (x *ChainConfig) UnmarshalJSON(data []byte) error {
	type Alias ChainConfig
	a := &struct {
		BaseChain   string `json:"BaseChain,omitempty"`
		MaxGasPrice string `json:"MaxGasPrice,omitempty"`
		*Alias
	}{
		Alias: (*Alias)(x),
	}

	if err := json.Unmarshal(data, &a); err != nil {
		return err
	}

	if a.MaxGasPrice != "" {
		maxGasPrice, ok := big.NewInt(0).SetString(a.MaxGasPrice, 10)
		if !ok {
			return errors.New("MaxGasPrice set but error")
		}
		x.MaxGasPrice = maxGasPrice
	}

	x.BaseChain = blockchain.Parse(a.BaseChain)
	if a.BaseChain != "" && x.BaseChain == blockchain.UnknownChain {
		return fmt.Errorf("BaseChain UnknownChain")
	}

	return nil
}

func (x *ChainConfig) MarshalJSON() ([]byte, error) {
	type Alias ChainConfig
	a := struct {
		*Alias
		MaxGasPrice string `json:"MaxGasPrice"`
		BaseChain   string `json:"BaseChain"`
	}{
		Alias:     (*Alias)(x),
		BaseChain: x.BaseChain.String(),
	}
	if x.MaxGasPrice != nil {
		a.MaxGasPrice = x.MaxGasPrice.String()
	}

	return json.Marshal(&a)
}

type ConnectionURL struct {
	mysql.ConnectionURL
	Adapter string `json:"adapter"`
}

type GasStation struct {
	APIUrl        string
	Filed         string
	FiledType     string /* only string or int */
	WeiMultiplier uint64
}

type Pushover struct {
	Token string `json:"Token"`
	Key   string `json:"Key"`
}

type SMTPConfig struct {
	Host            string `json:"Host"`
	Port            int    `json:"Port"`
	Username        string `json:"Username"`
	Password        string `json:"Password"`
	From            string `json:"From"`
	FromDisplayName string `json:"FromDisplayName"`
	To              string `json:"To"`
}

type Bridge struct {
	// common config
	LogLevel     string         `json:"LogLevel,omitempty"`
	EnableSMTP   bool           `json:"EnableSMTP,omitempty"`
	SMTP         *SMTPConfig    `json:"SMTP,omitempty"`
	EnableNotify bool           `json:"EnableNotify,omitempty"`
	Pushover     *Pushover      `json:"Pushover,omitempty"`
	DB           *ConnectionURL `json:"Db" "mapstructure":"db"` // database

	// chain config
	Blockchain *ChainConfig `json:"Blockchain,omitempty"`

	// core config
	DisabledPairs string     `json:"DisabledPairs,omitempty"`
	Router        *APIConfig `json:"Tunnel,omitempty"`

	// kms
	APISignKeyId        string `json:"APISignKeyId,omitempty"`
	ManagerAPISignKeyId string `json:"ManagerAPISignKeyId,omitempty"`
	CoreSignKeyId       string `json:"CoreSignKeyId,omitempty"`
	ToolsSignKeyId      string `json:"ToolsSignKeyId,omitempty"`

	// core and api
	Swap *swap.Config `json:"Swap,omitempty"`
}
