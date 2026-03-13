package manager

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum"
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

type RunTransfer func() (err error)

func (m *Manager) Run(duration time.Duration, runTransfer RunTransfer) (err error) {

	run := func() error {
		var err error

		err = runTransfer()
		if err != nil {
			return Error(err)
		}

		return nil
	}

	if duration == 0 {
		err = runTransfer()
		if err != nil {
			return Error(err)
		}

		return nil
	}

	log.Infoln("Run duration is: ", duration.String())
	ticker := time.NewTicker(duration)
	err = run()
	if err != nil {
		log.Errorln(err)
	}
	for {
		select {
		case <-ticker.C:
			log.Infof("RunWithdrawMonitor run")
			err := run()
			if err != nil {
				log.Errorln(err)
				continue
			}
		}
	}
}

func (m *Manager) RunEthTransfer() (err error) {
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
		// direction              config.Direction
		// tokenAddressColumn     string
		// tokenValueActualColumn string

		withdrawMainAddress common.Address

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

	feeAddressStr, err := database.LoadFeeAddress(sess, m.Blockchain.Network, m.Blockchain.ChainId, m.ToolsSignKeyId)
	if err != nil {
		return Error(fmt.Errorf("loading fee: %w", err))
	}
	useFeeAddress := false
	var feeAddress common.Address
	if feeAddressStr != "" {
		useFeeAddress = true
		feeAddress = common.HexToAddress(feeAddressStr)
	}
	if useFeeAddress && feeAddress == (common.Address{}) {
		return Error(errors.New("fee address set but is zero"))
	}

	client, err := ethclient.Dial(rpcurl)
	if err != nil {
		return Error(err)
	}

	// handle asset collection only after core/exchange
	var historyList []*database.History
	err = sess.SQL().SelectFrom(
		"history").Where(
		"blockchain_id", bcId).And(
		"status >= ? AND status <= ?", utils.BridgePendingWithdraw, utils.BridgeMergedConfirmed).And(
		"merge_status", utils.HistoryMergeStatusDefault).All(&historyList)
	if err != nil {
		return Error(err)
	}

	if len(historyList) == 0 {
		log.Infoln("no need to merge tokens")
		return nil
	}

	/*
	 1. select from bridge history list
	 2. address ==> tokens
	 3. send ETH/NEW to address
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

	gasToken := big.NewInt(0).Mul(gasPrice, big.NewInt(0).SetUint64(utils.GasLimitTokenTransfer))
	parsed, err := abi.JSON(strings.NewReader(newasset.BaseTokenABI))
	if err != nil {
		return Error(err)
	}

	// // map: address ==> asset ==> amount
	// historyMap := make(map[common.Address]map[string]*big.Int)
	// // map: address ==> asset ==> historyIds
	// historyIDs := make(map[common.Address]map[string][]uint64)

	assetsMap, err := getAssetMap(sess, bcId, client)
	if err != nil {
		return Error(err)
	}

	for _, l := range historyList {
		var (
			ok bool

			iAddress    common.Address
			valueActual = big.NewInt(0)
		)

		if !common.IsHexAddress(l.Address) {
			log.WithFields(logrus.Fields{"id": l.Id}).Errorln(ErrorCode(errInvalidAddress))
			return ErrorCode(errInvalidAddress)
		}
		iAddress = common.HexToAddress(l.Address)
		if l.Amount != "" {
			if _, ok := valueActual.SetString(l.Amount, 10); !ok {
				log.WithFields(logrus.Fields{"id": l.Id}).Errorln(ErrorCode(errStringToBigInt))
				return ErrorCode(errStringToBigInt)
			}
		}

		if valueActual.Cmp(big.NewInt(0)) <= 0 {
			log.WithFields(logrus.Fields{
				"id": l.Id,
			}).Warnln("deposit amount zero")

			continue
		}

		asset := l.Asset

		amount := big.NewInt(0).Set(valueActual)
		feeAmount := big.NewInt(0)
		if useFeeAddress {
			if l.Fee != "" {
				fee, ok := big.NewInt(0).SetString(l.Fee, 10)
				if !ok {
					log.WithFields(logrus.Fields{"id": l.Id}).Errorln(ErrorCode(errInvalidAddress))
					return ErrorCode(errInvalidAddress)
				}
				feeAmount = fee
			}
			// ignore decimal
			amount.Sub(amount, feeAmount)
		}

		if amount.Cmp(big.NewInt(0)) <= 0 {
			log.WithFields(logrus.Fields{
				"address": iAddress.String(),
				"asset":   asset,
			}).Warnln("deposit amount zero")
			return nil
		}

		// get pair
		t, ok := assetsMap[asset]
		if !ok {
			log.WithFields(logrus.Fields{
				"asset": asset,
			}).Warnln("no such asset")
			return nil
		}

		// ok, handle db

		tableId := l.Id

		err := sess.Tx(func(dbTx db.Session) error {
			// update status
			_, err = dbTx.SQL().Update("history").Set(
				"merge_status", utils.HistoryMergeStatusSubmitted).Where(
				"id", tableId).Exec()
			if err != nil {
				return Error(err)
			}

			now := time.Now()
			if t.Address != (common.Address{}) {
				// token
				nativeAsset, ok := assetsMap[""]
				if !ok {
					log.Errorln("please set native asset, it's work for token")
					return Error(fmt.Errorf("no native asset"))
				}

				var data []byte
				if t.Attribute&utils.AttributeBurnable == utils.AttributeBurnable {
					data, err = parsed.Pack("burn", amount)
				} else {
					data, err = parsed.Pack("transfer", withdrawMainAddress, amount)
				}
				if err != nil {
					log.WithFields(logrus.Fields{
						"address": iAddress.String(),
						"asset":   asset,
					}).Errorln(Error(err))
					return Error(err)
				}

				// no need charge if gasprice is zero
				if gasPrice.Cmp(big.NewInt(0)) > 0 {
					// send amount from MainWithdrawAddress to iAddress
					err = database.SubmitTasks(dbTx, []*utils.TaskData{{
						ScheduleAt: now,
						To:         iAddress,
						Value:      big.NewInt(0).Set(gasToken),

						BlockchainId: bcId,
						Asset:        "",
						AssetId:      nativeAsset.AssetId,

						TableNo: utils.TableNoManager,
						TableId: tableId,

						ActionType: utils.TasksActionTypeOfManagerCharge,
					}}, m.Blockchain.ChainManagerSignKeyId)
					if err != nil {
						return Error(err)
					}

					log.WithFields(logrus.Fields{
						"address": iAddress.String(),
						"asset":   asset,
						"from":    withdrawMainAddress.String(),
						"to":      iAddress.String(),
						"value":   utils.GetAmountTextFromISAAC(gasToken),
					}).Infoln("manager: submit charge task")
				}

				// token: send from iAddress to MainWithdrawAddress or burn
				err = database.SubmitTasks(dbTx, []*utils.TaskData{{
					ScheduleAt: now.Add(time.Minute),
					From:       iAddress,
					To:         t.Address, // token, a.Asset
					Value:      big.NewInt(0),
					Data:       hex.EncodeToString(data),

					BlockchainId: bcId,
					Asset:        asset,
					AssetId:      t.AssetId,

					TableNo:    utils.TableNoManager,
					TableId:    tableId,
					ActionType: utils.TasksActionTypeOfManagerMerge,
				}}, m.Blockchain.ChainManagerSignKeyId)
				if err != nil {
					return Error(err)
				}

				log.WithFields(logrus.Fields{
					"address":      iAddress.String(),
					"asset":        asset,
					"token":        t.Address.String(),
					"token_symbol": t.Symbol,
					"from":         iAddress.String(),
					"to":           withdrawMainAddress.String(),
					"amount":       utils.GetAmountTextFromISAACWithDecimals(amount, t.Decimals),
				}).Infoln("manager: submit token merge task")

				if useFeeAddress && feeAmount.Cmp(big.NewInt(0)) > 0 {
					// no burn only transfer for fee
					feeData, err := parsed.Pack("transfer", feeAddress, feeAmount)
					if err != nil {
						log.WithFields(logrus.Fields{
							"address": iAddress.String(),
							"asset":   asset,
						}).Errorln(Error(err))
						return Error(err)
					}

					// no need charge
					// token: send from iAddress to MainWithdrawAddress or burn
					err = database.SubmitTasks(dbTx, []*utils.TaskData{{
						ScheduleAt: now.Add(time.Minute),
						From:       iAddress,
						To:         t.Address, // token, a.Asset
						Value:      big.NewInt(0),
						Data:       hex.EncodeToString(feeData),

						BlockchainId: bcId,
						Asset:        asset,
						AssetId:      t.AssetId,

						TableNo:    utils.TableNoManager,
						TableId:    tableId,
						ActionType: utils.TasksActionTypeOfFee,
					}}, m.Blockchain.ChainManagerSignKeyId)
					if err != nil {
						return Error(err)
					}

					log.WithFields(logrus.Fields{
						"address":      iAddress.String(),
						"asset":        asset,
						"token":        t.Address.String(),
						"token_symbol": t.Symbol,
						"from":         iAddress.String(),
						"to":           withdrawMainAddress.String(),
						"amount":       utils.GetAmountTextFromISAACWithDecimals(amount, t.Decimals),
					}).Infoln("manager: submit token fee task")
				}

				return nil
			} else {
				// coin
				// try to get gas limit, 21000
				gasLimit, err := client.EstimateGas(context.Background(), ethereum.CallMsg{
					From:     iAddress,
					To:       &withdrawMainAddress,
					GasPrice: big.NewInt(0),             // MUST use zero
					Value:    big.NewInt(0).Set(amount), // use amount
				})
				if err != nil {
					log.WithFields(logrus.Fields{
						"iAddress":    iAddress.String(),
						"MainAddress": withdrawMainAddress.String(),
					}).Warnln("EstimateGas from iAddress to MainAddress error: ", err)
					return Error(err)
				}

				gasCoin := big.NewInt(0).Mul(gasPrice, big.NewInt(0).SetUint64(gasLimit))
				amount2Send := big.NewInt(0).Sub(amount, gasCoin)
				if amount2Send.Cmp(big.NewInt(0)) <= 0 {
					log.WithFields(logrus.Fields{
						"address": iAddress.String(),
						"asset":   asset,
					}).Warnln("amount to send zero")
					return nil
				}

				// send amount from iAddress to WithdrawMainAddress
				// ok, transfer NEW/ETH
				err = database.SubmitTasks(dbTx, []*utils.TaskData{{
					ScheduleAt: now,
					From:       iAddress,
					To:         withdrawMainAddress,
					Value:      big.NewInt(0).Set(amount2Send),

					BlockchainId: bcId,
					Asset:        asset,
					AssetId:      t.AssetId,

					TableNo:    utils.TableNoManager,
					TableId:    tableId,
					ActionType: utils.TasksActionTypeOfManagerMerge,
				}}, m.Blockchain.ChainManagerSignKeyId)
				if err != nil {
					return Error(err)
				}

				log.WithFields(logrus.Fields{
					"address":   iAddress.String(),
					"asset":     asset,
					"from":      iAddress.String(),
					"to":        withdrawMainAddress.String(),
					"value":     utils.GetAmountTextFromISAAC(amount2Send),
					"gas_limit": gasLimit,
					"gas_price": utils.GetAmountTextFromISAAC(gasPrice),
				}).Infoln("manager: submit base coin merge task")

				if useFeeAddress && feeAmount.Cmp(big.NewInt(0)) > 0 {
					feeGasLimit, err := client.EstimateGas(context.Background(), ethereum.CallMsg{
						From:     iAddress,
						To:       &feeAddress,
						GasPrice: big.NewInt(0),                // MUST use zero
						Value:    big.NewInt(0).Set(feeAmount), // use amount
					})
					if err != nil {
						log.WithFields(logrus.Fields{
							"iAddress":   iAddress.String(),
							"FeeAddress": feeAmount.String(),
						}).Warnln("EstimateGas from iAddress to FeeAddress error: ", err)
						return Error(err)
					}

					feeGasCoin := big.NewInt(0).Mul(gasPrice, big.NewInt(0).SetUint64(feeGasLimit))
					feeAmount2Send := big.NewInt(0).Sub(feeAmount, feeGasCoin)
					if feeAmount2Send.Cmp(big.NewInt(0)) <= 0 {
						log.WithFields(logrus.Fields{
							"address": iAddress.String(),
							"asset":   asset,
						}).Warnln("fee amount to send zero")
						return nil
					}
					err = database.SubmitTasks(dbTx, []*utils.TaskData{{
						ScheduleAt: now,
						From:       iAddress,
						To:         feeAddress,
						Value:      big.NewInt(0).Set(feeAmount2Send),

						BlockchainId: bcId,
						Asset:        asset,
						AssetId:      t.AssetId,

						TableNo:    utils.TableNoManager,
						TableId:    tableId,
						ActionType: utils.TasksActionTypeOfFee,
					}}, m.Blockchain.ChainManagerSignKeyId)
					if err != nil {
						return Error(err)
					}

					log.WithFields(logrus.Fields{
						"address":   iAddress.String(),
						"asset":     asset,
						"from":      iAddress.String(),
						"to":        feeAddress.String(),
						"value":     utils.GetAmountTextFromISAAC(feeAmount2Send),
						"gas_limit": feeGasLimit,
						"gas_price": utils.GetAmountTextFromISAAC(gasPrice),
					}).Infoln("manager: submit base coin fee task")
				}

				return nil
			}
		})
		if err != nil {
			log.Errorln(err)
			// ignore, just continue
			continue
		}
	}

	return nil
}

func getAssetMap(sess db.Session, bcId uint64, client *ethclient.Client) (map[string]*Token, error) {
	assetsMap := make(map[string]*Token)

	// ok, try to get pair
	var assetList []database.Asset
	err := sess.SQL().SelectFrom("assets").Where("blockchain_id", bcId).All(&assetList)
	if errors.Is(err, db.ErrNoMoreRows) {

		return nil, Error(fmt.Errorf("no asset for this blockchain id: %v", bcId))
	} else if err != nil {
		log.WithFields(logrus.Fields{
			"blockchain_id": bcId}).Errorln("get assets by blockchainId error: ", err)
		return nil, Error(err)
	}

	for _, a := range assetList {
		var (
			token     common.Address
			balanceOf BalanceOf
			name      string
			symbol    string
			decimals  uint8
			attribute uint64
		)
		if a.Asset == "" {
			// native coin
			token = common.Address{}
		} else {
			if !common.IsHexAddress(a.Asset) {
				log.WithFields(logrus.Fields{
					"asset": a.Asset,
				}).Errorln(ErrorCode(errInvalidAddress))

				return nil, ErrorCode(errInvalidAddress)
			}
			token = common.HexToAddress(a.Asset)
		}

		attribute = a.Attribute
		name = a.Name
		symbol = a.Symbol
		decimals = a.Decimals

		if token == (common.Address{}) {
			balanceOf = func(account common.Address) (*big.Int, error) {
				return client.BalanceAt(context.Background(), account, nil)
			}
		} else {
			baseToken, err := newasset.NewBaseToken(token, client)
			if err != nil {
				log.WithFields(logrus.Fields{
					"asset": a.Asset,
				}).Errorln(Error(err))

				return nil, Error(err)
			}
			balanceOf = func(account common.Address) (*big.Int, error) {
				return baseToken.BalanceOf(nil, account)
			}
		}

		t := &Token{
			AssetId:   a.ID,
			Address:   token,
			Name:      name,
			Symbol:    symbol,
			Decimals:  decimals,
			Attribute: int(attribute),
			BalanceOf: balanceOf,
		}

		assetsMap[a.Asset] = t
	}

	return assetsMap, nil
}
