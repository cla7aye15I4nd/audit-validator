package manager

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/sirupsen/logrus"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/contract/newasset"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

func (m *Manager) RunCold(args []string) (err error) {
	if len(args) < 1 {
		return errors.New("not amount or asset set")
	}
	amountStr := args[0]
	if amountStr == "" {
		return errors.New("amount is empty")
	}

	var asset string
	if len(args) >= 2 {
		asset = args[1]
	}

	baseChain := m.Blockchain.BaseChain
	if baseChain != blockchain.Ethereum && baseChain != blockchain.NewChain {
		return errors.New("base chain not support")
	}

	sess, err := m.openDatabase()
	if err != nil {
		return Error(err)
	}
	defer sess.Close()

	var bc database.Blockchain
	err = sess.SQL().Select("id", "network", "chain_id", "base_chain").From(
		"blockchains").Where(
		"network", m.Blockchain.Network).And(
		"chain_id", m.Blockchain.ChainId).One(&bc)
	if errors.Is(err, db.ErrNoMoreRows) {
		return errors.New("no such blockchain")
	} else if err != nil {
		return err
	} else if bc.Id == 0 {
		return errors.New("blockchain id is zero")
	}
	bcId := bc.Id

	var (
		rpcurl string

		withdrawMainAddress common.Address
		coldAddress         common.Address

		gs          *config.GasStation
		maxGasPrice *big.Int
	)

	rpcurl = m.Blockchain.RpcURL
	gs = m.Blockchain.GasPrice
	maxGasPrice = m.Blockchain.MaxGasPrice

	if m.Blockchain.WithdrawMainAddress == nil {
		return Error(errors.New("withdraw main address nil"))
	}
	withdrawMainAddress = m.Blockchain.WithdrawMainAddress.(common.Address)
	if withdrawMainAddress == (common.Address{}) {
		return Error(errors.New("withdraw main address zero"))
	}

	if m.Blockchain.ColdAddress != nil {
		coldAddress = m.Blockchain.ColdAddress.(common.Address)
	}
	if coldAddress == (common.Address{}) {
		return Error(errors.New("cold main address zero, no need to transfer"))
	}
	if coldAddress.String() == withdrawMainAddress.String() {
		return Error(errors.New("coldMainAddress same with withdrawMainAddress, no need to transfer"))
	}

	client, err := ethclient.Dial(rpcurl)
	if err != nil {
		return Error(err)
	}

	/*
	 1. check asset
	 1. send asset from MainAddress to ColdAddress
	*/

	var gasPrice *big.Int
	if gs != nil {
		gasPrice, err = utils.GetGasPrice(gs)
		if err != nil {
			log.Errorln(Error(err))
			return
		}
	} else {
		gasPrice, err = client.SuggestGasPrice(context.Background())
		if err != nil {
			log.Errorln(Error(err))
			return
		}
	}
	if maxGasPrice != nil && maxGasPrice.Cmp(big.NewInt(0)) >= 0 && maxGasPrice.Cmp(gasPrice) < 0 {
		log.WithFields(logrus.Fields{
			"SuggestGasPrice": gasPrice.String(),
			"MaxGasPrice":     maxGasPrice.String(),
		}).Warnln("Try set gas price to max")
		gasPrice.Set(maxGasPrice)
	}

	assetsMap, err := getAssetMap(sess, bcId, client)
	if err != nil {
		return Error(err)
	}

	// get pair
	a, ok := assetsMap[asset]
	if !ok {
		log.WithFields(logrus.Fields{
			"asset": asset,
		}).Errorln("no such asset")
		return nil
	}

	amount, err := utils.GetAmountISAACFromTextWithDecimals(amountStr, a.Decimals)
	if err != nil {
		log.WithFields(logrus.Fields{
			"asset": asset,
		}).Errorln("amount is invalid")

		return err
	}

	if amount.Cmp(big.NewInt(0)) <= 0 {
		log.WithFields(logrus.Fields{
			"asset": asset,
		}).Warnln("deposit amount zero")
		return nil
	}

	// ok

	now := time.Now()
	tableId := uint64(now.UnixNano())

	if a.Address != (common.Address{}) {
		// token

		// nativeAsset, ok := assetsMap[""]
		// if !ok {
		// 	log.Errorln("please set native asset, it's work for token")
		// 	return Error(fmt.Errorf("no native asset"))
		// }

		parsed, err := abi.JSON(strings.NewReader(newasset.BaseTokenMetaData.ABI))
		if err != nil {
			return Error(err)
		}
		data, err := parsed.Pack("transfer", coldAddress, amount)
		if err != nil {
			log.WithFields(logrus.Fields{
				"asset": asset,
			}).Errorln(Error(err))
			return Error(err)
		}

		log.WithFields(logrus.Fields{
			"asset":        asset,
			"token":        a.Address.String(),
			"token_symbol": a.Symbol,
			"from":         withdrawMainAddress.String(),
			"to":           coldAddress.String(),
			"amount":       utils.GetAmountTextFromISAACWithDecimals(amount, a.Decimals),
		}).Infoln("manager: trying to submit merge token to cold address task")
		if !utils.Confirm() {
			return fmt.Errorf("cancled")
		}

		// token: send from MainWithdrawAddress to ColdMainAddress or burn
		err = database.SubmitTasks(sess, []*utils.TaskData{{
			ScheduleAt: now,
			From:       withdrawMainAddress,
			To:         a.Address, // token, a.Asset
			Value:      big.NewInt(0),
			Data:       hex.EncodeToString(data),

			BlockchainId: bcId,
			Asset:        asset,
			AssetId:      a.AssetId,

			TableNo:    utils.TableNoManager,
			TableId:    tableId,
			ActionType: utils.TasksActionTypeOfCold,
		}}, m.Blockchain.ChainManagerSignKeyId)
		if err != nil {
			return Error(err)
		}

		log.WithFields(logrus.Fields{
			"asset":        asset,
			"token":        a.Address.String(),
			"token_symbol": a.Symbol,
			"from":         withdrawMainAddress.String(),
			"to":           coldAddress.String(),
			"amount":       utils.GetAmountTextFromISAACWithDecimals(amount, a.Decimals),
		}).Infoln("manager: submitted token merge task")

		return nil
	}

	// coin

	amount2Send := big.NewInt(0).Set(amount)
	wmaBalance, err := client.BalanceAt(context.Background(), withdrawMainAddress, nil)
	if err != nil {
		return Error(err)
	}
	if wmaBalance.Cmp(amount2Send) <= 0 {
		log.WithFields(logrus.Fields{
			"address": coldAddress.String(),
			"asset":   a.Name,
			"balance": utils.GetAmountTextFromISAACWithDecimals(wmaBalance, a.Decimals),
			"amount":  utils.GetAmountTextFromISAACWithDecimals(amount2Send, a.Decimals),
		}).Errorln("balance less than amount")
		return Error(fmt.Errorf("balance less than amount"))
	}

	// send amount from withdrawMainAddress to ColdWallet
	// ok, transfer NEW/ETH

	log.WithFields(logrus.Fields{
		"asset":  a.Name,
		"symbol": a.Symbol,
		"from":   withdrawMainAddress.String(),
		"to":     coldAddress.String(),
		"value":  utils.GetAmountTextFromISAAC(amount2Send),
	}).Infoln("manager: trying to submit merge base coin to cold address task")
	if !utils.Confirm() {
		return fmt.Errorf("cancled")
	}

	err = database.SubmitTasks(sess, []*utils.TaskData{{
		ScheduleAt: now,
		From:       withdrawMainAddress,
		To:         coldAddress,
		Value:      big.NewInt(0).Set(amount2Send),

		BlockchainId: bcId,
		Asset:        asset,
		AssetId:      a.AssetId,

		TableNo:    utils.TableNoManager,
		TableId:    tableId,
		ActionType: utils.TasksActionTypeOfCold,
	}}, m.Blockchain.ChainManagerSignKeyId)
	if err != nil {
		return Error(err)
	}

	log.WithFields(logrus.Fields{
		"asset":  a.Name,
		"symbol": a.Symbol,
		"from":   withdrawMainAddress.String(),
		"to":     coldAddress.String(),
		"value":  utils.GetAmountTextFromISAAC(amount2Send),
	}).Infoln("manager: submitted merge base coin to cold address task")

	return nil
}
