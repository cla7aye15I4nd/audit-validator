package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"

	dbtcutil "github.com/dogecoinw/doged/btcutil"
	dchaincfg "github.com/dogecoinw/doged/chaincfg"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

const defaultConfigFile = "./config.toml"
const defaultLogFile = "./error.log"
const defaultRPCURL = "https://rpc1.newchain.newtonproject.org"
const defaultHost = "127.0.0.1:3306"

func defaultConfig(cli *CLI) {
	// viper.BindPFlag("rpcURL", cli.rootCmd.PersistentFlags().Lookup("rpcURL"))
	viper.BindPFlag("log", cli.rootCmd.PersistentFlags().Lookup("log"))
	// viper.SetDefault("rpcURL", defaultRPCURL)
	viper.SetDefault("log", defaultLogFile)
}

func setupConfig(cli *CLI) error {

	// var ret bool
	var err error

	defaultConfig(cli)

	viper.SetConfigName(defaultConfigFile)
	viper.AddConfigPath(".")
	cfgFile := cli.config
	if cfgFile != "" {
		if _, err = os.Stat(cfgFile); err == nil {
			viper.SetConfigFile(cfgFile)
			err = viper.ReadInConfig()
		} else {
			// The default configuration is enabled.
			// fmt.Println(err)
			err = nil
		}
	} else {
		// The default configuration is enabled.
		err = nil
	}

	// cli.rpcURL = viper.GetString("rpcURL")
	cli.logfile = viper.GetString("log")

	return err
}

func loadBridge() (*config.Bridge, error) {

	all := viper.AllSettings()
	allJson, err := json.Marshal(&all)
	if err != nil {
		return nil, err
	}

	var cb config.Bridge
	err = json.Unmarshal(allJson, &cb)
	if err != nil {
		return nil, err
	}

	return &cb, nil
}

func applyDB(cb *config.Bridge) error {
	if cb == nil || cb.Blockchain == nil {
		return errors.New("bridge config is nil")
	}

	// Main
	sess, err := database.OpenDatabase(cb.DB.Adapter, cb.DB.ConnectionURL)
	if err != nil {
		return err
	}
	defer sess.Close()

	name := fmt.Sprintf("%s-%s-%s", cb.Blockchain.Network, cb.Blockchain.ChainId, utils.WithdrawMainAddress)
	nameCold := fmt.Sprintf("%s-%s-%s", cb.Blockchain.Network, cb.Blockchain.ChainId, utils.ColdAddress)
	nameLike := fmt.Sprintf("%s-%s-%%", cb.Blockchain.Network, cb.Blockchain.ChainId)

	baseChain := cb.Blockchain.BaseChain

	var configList []*database.Config
	err = sess.SQL().SelectFrom(
		database.TableOfConfig).Where(
		"variable like ?", nameLike).All(&configList)
	if errors.Is(err, db.ErrNoMoreRows) {
		return errors.New("please `init` main withdraw address")
	} else if err != nil {
		return err
	}

	for _, l := range configList {
		if l.Variable != name && l.Variable != nameCold {
			continue
		}

		var address config.Address
		if baseChain == blockchain.Dogecoin {
			address, err = dbtcutil.DecodeAddress(l.Value, &dchaincfg.MainNetParams)
			if err != nil {
				return err
			}
		} else if baseChain == blockchain.Ethereum || baseChain == blockchain.NewChain {
			if !common.IsHexAddress(l.Value) {
				return fmt.Errorf("invalid hex address: %v", l.Value)
			}
			address = common.HexToAddress(l.Value)
		} else {
			return fmt.Errorf("not support basechain")
		}

		if !database.Verify(l, cb.ToolsSignKeyId) {
			return errors.New("invalid config")
		}

		if l.Variable == name {
			cb.Blockchain.WithdrawMainAddress = address
		} else if l.Variable == nameCold {
			cb.Blockchain.ColdAddress = address
		}
	}
	if cb.Blockchain.WithdrawMainAddress == nil {
		return errors.New("please add withdraw address")
	}
	if cb.Blockchain.ColdAddress == nil {
		cb.Blockchain.ColdAddress = cb.Blockchain.WithdrawMainAddress
		log.Warnln("No ColdAddress set, use WithdrawMainAddress as ColdAddress")
	}
	log.WithFields(logrus.Fields{
		"WithdrawMainAddress": cb.Blockchain.WithdrawMainAddress.String(),
		"ColdAddress":         cb.Blockchain.ColdAddress.String(),
	}).Infoln("loaded main address")

	return nil
}

// applyChainDB get WithdrawMainAddress from ChainDB
func applyChainDB(cb *config.Bridge) error {
	if cb == nil || cb.Blockchain == nil {
		return fmt.Errorf("blockchain is nil")
	}
	name := fmt.Sprintf("%s-%s-%s", cb.Blockchain.Network, cb.Blockchain.ChainId, utils.WithdrawMainAddress)
	sess, err := database.OpenDatabase(cb.Blockchain.DB.Adapter, cb.Blockchain.DB.ConnectionURL)
	if err != nil {
		return err
	}
	defer sess.Close()

	var account database.Addresses
	err = sess.SQL().SelectFrom(
		"addresses").Where(
		"name", name).Limit(1).One(&account)
	if errors.Is(err, db.ErrNoMoreRows) {
		return errors.New("please `init` main withdraw address")
	} else if err != nil {
		return err
	}

	baseChain := cb.Blockchain.BaseChain
	if baseChain == blockchain.Dogecoin {
		address, err := dbtcutil.DecodeAddress(account.Address, &dchaincfg.MainNetParams)
		if err != nil {
			return err
		}
		if cb.Blockchain.WithdrawMainAddress != nil && cb.Blockchain.WithdrawMainAddress.String() != address.String() {
			return fmt.Errorf("load addrss from DB is %s but chain DB is %s", cb.Blockchain.WithdrawMainAddress.String(), address.String())
		}
		cb.Blockchain.WithdrawMainAddress = address
	} else if baseChain == blockchain.Ethereum || baseChain == blockchain.NewChain {
		if !common.IsHexAddress(account.Address) {
			return fmt.Errorf("invalid hex address: %v", account.Address)
		}
		address := common.HexToAddress(account.Address)
		if cb.Blockchain.WithdrawMainAddress != nil && cb.Blockchain.WithdrawMainAddress.String() != address.String() {
			return fmt.Errorf("load addrss from DB is %s but chain DB is %s", cb.Blockchain.WithdrawMainAddress.String(), address.String())
		}
		cb.Blockchain.WithdrawMainAddress = address
	} else {
		return fmt.Errorf("not support chain")
	}

	return nil
}

// handleBlockchain check or set blockchain info
func handleBlockchain(cb *config.Bridge) error {
	return handleBlockchainWithOption(cb, false)
}

// handleBlockchainWithOption check or set blockchain info
func handleBlockchainWithOption(cb *config.Bridge, skipOnChainVerify bool) error {
	if cb.Blockchain == nil {
		return fmt.Errorf("blockchain not set")
	}
	network := cb.Blockchain.Network
	chainId := cb.Blockchain.ChainId
	baseChain := cb.Blockchain.BaseChain
	if baseChain == blockchain.UnknownChain {
		return fmt.Errorf("base chain unknown")
	}

	// check chainId with RPC
	if !skipOnChainVerify {
		if baseChain == blockchain.Ethereum || baseChain == blockchain.NewChain {
			client, err := ethclient.Dial(cb.Blockchain.RpcURL)
			if err != nil {
				return err
			}
			chainIdBig, err := client.ChainID(context.Background())
			if err != nil {
				return err
			}
			if chainIdBig.String() != chainId {
				return fmt.Errorf("ChainID not match: config is %s but RPC is %s", chainId, chainIdBig.String())
			}
		} else if baseChain == blockchain.Dogecoin {
		} else {
			return fmt.Errorf("base chain not support")
		}
	}

	// check signature algorithm
	if baseChain == blockchain.NewChain {
		if !isP256() {
			return fmt.Errorf("BaseChain from config is %v but code version is %s", baseChain.String(), ChainVersion())
		}
	} else {
		if isP256() {
			return fmt.Errorf("BaseChain from config is %v but code version is %s", baseChain.String(), ChainVersion())
		}
	}

	// check blockchain info with database
	sess, err := database.OpenDatabase(cb.DB.Adapter, cb.DB.ConnectionURL)
	if err != nil {
		return err
	}
	defer sess.Close()

	var bc database.Blockchain
	err = sess.SQL().SelectFrom(
		"blockchains").Where(
		"network", network).And(
		"chain_id", chainId).One(&bc)
	if errors.Is(err, db.ErrNoMoreRows) {
		return errors.New("no such blockchain")
	} else if err != nil {
		return err
	}

	if bc.Id == 0 {
		return errors.New("blockchain id is zero")
	}
	if cb.Blockchain.BlockchainId != 0 && bc.Id != cb.Blockchain.BlockchainId {
		return fmt.Errorf("blockchain is set in config is %d but not match with db %d", cb.Blockchain.BlockchainId, bc.Id)
	}
	cb.Blockchain.BlockchainId = bc.Id

	dbBC := blockchain.Parse(bc.BaseChain)
	if dbBC == blockchain.UnknownChain {
		return fmt.Errorf("base chain form db unknown")
	}
	if dbBC != baseChain {
		return fmt.Errorf("base chain form config is %s not match with db %s", baseChain.String(), dbBC.String())
	}

	return nil
}
