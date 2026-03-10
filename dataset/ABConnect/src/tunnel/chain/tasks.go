package chain

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
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/sirupsen/logrus"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/contract/newasset"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/swap"
)

type checkTaskStatusFunc func()

// RunTasks run to execute tasks with a non-zero value
func (x *Chain) RunTasks() error {
	if x.walletType == WalletKMS {
		if x.baseChain == blockchain.Dogecoin {
			go x.startCheckTasks(x.checkDogecoinTaskStatus) // loop to update task tx status
			go x.startDogecoinTransfer()                    // loop to exec transactions and update tx_hash
		} else {
			go x.startCheckTasks(x.checkTaskStatus) // loop to update task tx status
			go x.startTransfer()
		}
	} else if x.walletType == WalletRPC {
		return fmt.Errorf("WalletRPC: TODO")
	}

	select {}
}

func (x *Chain) startCheckTasks(checkTaskStatus checkTaskStatusFunc) {

	checkTaskStatus()

	ticker := time.NewTicker(time.Second * 10)
	for {
		select {
		// case <-txCh:
		// 	s.waitAndUpdateTasksWithTx()
		case <-ticker.C:
			checkTaskStatus()
		}
	}
}

type TaskTransaction struct {
	ID    uint64
	From  config.Address
	To    config.Address
	Value *big.Int
	Data  []byte

	GasPrice *big.Int
	GasLimit uint64

	TableNo uint
	TableId uint64

	ActionType uint
}

type TaskTransactions []*TaskTransaction

func (x *Chain) startTransfer() {
	log.Infof("Tasks exec speed: 1 tasks per %s", x.durationOfExecTask.String())

	parsed, err := abi.JSON(strings.NewReader(newasset.BaseTokenMetaData.ABI))
	if err != nil {
		log.Errorln("ABI error: ", err)
		return
	}

	var coldMainAddress common.Address
	if x.config.ColdAddress != nil {
		coldMainAddress = x.config.ColdAddress.(common.Address)
	}
	if coldMainAddress == (common.Address{}) {
		coldMainAddress = x.config.WithdrawMainAddress.(common.Address)
		log.Warnln("User WithdrawMainAddress as ColdMainAddress: ", coldMainAddress.String())
	}
	if coldMainAddress == (common.Address{}) {
		log.Errorln(Error(errors.New("cold main address zero")))
		return
	}

	client, err := ethclient.Dial(x.config.RpcURL)
	if err != nil {
		log.Errorln(Error(err))
		return
	}
	defer client.Close()

	for {
		func() {
			sdb, err := database.OpenDatabase(x.adapterName, x.settings)
			if err != nil {
				return
			}
			defer sdb.Close()
			sdbTasks, err := database.OpenDatabase(x.DB.Adapter, x.DB.ConnectionURL)
			if err != nil {
				return
			}
			defer sdbTasks.Close()

			res := sdbTasks.SQL().SelectFrom("tasks").Where(
				"blockchain_id", x.bcId).And(
				"status", utils.TasksStatusOfSubmitted).And(
				"schedule_at < ", time.Now().UTC().Format("2006-01-02 15:04:05")).Limit(1024)

			var tasks []database.Task
			err = res.All(&tasks)
			if err != nil {
				log.Errorln(Error(err))
				return
			}

			if len(tasks) == 0 {
				// fmt.Println("no task to exec, sleep 5s")
				time.Sleep(time.Second * 5) // > blockPeriod
				return
			}

			log.Infoln("tasks: ", len(tasks))

			taskBatch := make(map[common.Address]TaskTransactions)
			// check tx
			for _, task := range tasks {
				log.WithFields(logrus.Fields{
					"id":          task.Id,
					"from":        task.From,
					"to":          task.To,
					"value":       task.Value,
					"schedule_at": task.ScheduleAt.String(),
					"status":      task.Status,
				}).Infoln("load tx to check")

				var from common.Address
				if task.From == "" {
					from = common.HexToAddress(x.config.WithdrawMainAddress.String())
				} else if !common.IsHexAddress(task.From) {
					log.WithField("id", task.Id).Errorln(ErrorCode(errInvalidAddress))
					continue
				} else {
					from = common.HexToAddress(task.From) // address valid hex-encoded
				}
				if from == (common.Address{}) {
					log.WithField("id", task.Id).Errorln("from address zero")
					continue
				}

				if !common.IsHexAddress(task.To) {
					log.WithField("id", task.Id).Errorln(ErrorCode(errInvalidAddress))
					continue
				}
				to := common.HexToAddress(task.To)
				if to == (common.Address{}) {
					log.WithField("id", task.Id).Errorln("to address zero")
					continue
				}

				value := big.NewInt(0)
				if task.Value != "" {
					var ok bool
					_, ok = value.SetString(task.Value, 10)
					if !ok {
						log.WithField("id", task.Id).Errorln("convert value string to big int error", task.Value)
						continue
					}
				}

				var (
					data            []byte
					transferTo      common.Address
					transferToValue *big.Int
					assetAttribute  uint64
				)
				if task.Asset != "" && task.Data == "" {
					// token transfer
					// build Data
					var asset database.Asset
					err = sdbTasks.SQL().SelectFrom("assets").Where(
						"id", task.AssetId).And(
						"blockchain_id", x.bcId).And(
						"asset", task.Asset).One(&asset)
					if errors.Is(err, db.ErrNoMoreRows) {
						log.WithFields(logrus.Fields{
							"id":           task.Id,
							"blockchainId": task.BlockchainId,
							"assetId":      task.AssetId,
							"asset":        task.Asset,
						}).Warnln("no such asset")
						continue
					} else if err != nil {
						log.WithFields(logrus.Fields{
							"id":           task.Id,
							"blockchainId": task.BlockchainId,
							"assetId":      task.AssetId,
							"asset":        task.Asset,
						}).Errorln("get asset error: ", err)
						continue
					}

					if asset.Attribute&utils.AttributeMintable == utils.AttributeMintable {
						data, err = parsed.Pack("mint", to, value)
						if err != nil {
							log.WithField("id", task.Id).Errorln("parsed mint data error: ", err)
							continue
						}
					} else {
						data, err = parsed.Pack("transfer", to, value)
						if err != nil {
							log.WithField("id", task.Id).Errorln("parsed transfer data error: ", err)
							continue
						}
					}

					if !common.IsHexAddress(task.Asset) {
						log.WithFields(logrus.Fields{
							"id":           task.Id,
							"blockchainId": task.BlockchainId,
							"assetId":      task.AssetId,
							"asset":        task.Asset,
						}).Errorln("task asset not address")
						continue
					}

					transferTo = to
					transferToValue = big.NewInt(0).Set(value)
					to = common.HexToAddress(task.Asset)
					value = big.NewInt(0)
					assetAttribute = asset.Attribute
				} else if task.Data != "" {
					data, err = hex.DecodeString(task.Data)
					if err != nil {
						log.WithField("id", task.Id).Errorln("decode data error: ", err)
						continue
					}
					if task.Asset != "" {
						// get transferTo
						var asset database.Asset
						err = sdbTasks.SQL().SelectFrom("assets").Where(
							"id", task.AssetId).And(
							"blockchain_id", x.bcId).And(
							"asset", task.Asset).One(&asset)
						if errors.Is(err, db.ErrNoMoreRows) {
							log.WithFields(logrus.Fields{
								"id":           task.Id,
								"blockchainId": task.BlockchainId,
								"assetId":      task.AssetId,
								"asset":        task.Asset,
							}).Warnln("no such asset but have data")
							continue
						} else if err != nil {
							log.WithFields(logrus.Fields{
								"id":           task.Id,
								"blockchainId": task.BlockchainId,
								"assetId":      task.AssetId,
								"asset":        task.Asset,
							}).Errorln("get asset error: ", err)
							continue
						}

						taskData, err := hex.DecodeString(task.Data)
						if err != nil {
							log.WithField("id", task.Id).Errorln("decode data error: ", err)
							continue
						}

						method, err := parsed.MethodById(taskData[:4])
						if err != nil {
							log.WithField("id", task.Id).Errorln("MethodByIda error: ", err)
							continue
						}
						args, err := method.Inputs.Unpack(taskData[4:])
						if err != nil {
							log.WithField("id", task.Id).Errorln("unpack error: ", len(args))
							continue
						}
						if method.Name == "burn" {
							if len(args) != 1 {
								log.WithField("id", task.Id).Errorln("unpack burn args len error: ", len(args))
								continue
							}
							transferToValue = args[0].(*big.Int) // burn(uint256 amount)
							assetAttribute = asset.Attribute
						} else {
							if len(args) != 2 {
								log.WithField("id", task.Id).Errorln("unpack args len error: ", len(args))
								continue
							}
							transferTo = args[0].(common.Address) // mint(address,uint256) or transfer(address,uint256)
							transferToValue = args[1].(*big.Int)
							assetAttribute = asset.Attribute
						}
					}
				}

				var tx *TaskTransaction

				// only care about Bridge
				if task.ActionType == utils.TasksActionTypeOfNewBridge {
					// WithdrawMainAddress ==> tokenAddress/userAddress
					if from.String() != x.config.WithdrawMainAddress.String() {
						log.WithField("id", task.Id).Errorln("asset can only be sent from WithdrawMainAddress")
						continue
					}

					// check balance
					if task.Asset == "" {
						// native coin
						fromBalance, err := client.BalanceAt(context.Background(), from, nil)
						if err != nil {
							log.WithFields(logrus.Fields{
								"id":   task.Id,
								"from": from.String(),
							}).Errorln("get balance error:", err)
							continue
						}
						if fromBalance.Cmp(value) < 0 {
							log.WithFields(logrus.Fields{
								"id":      task.Id,
								"from":    from.String(),
								"balance": fromBalance.String(),
								"amount":  value.String(),
							}).Warnln("native asset insufficient balance")

							if task.TableNo == utils.TableNoNewBridgeHistory {
								// update history
								err = x.UpdateHistoryInsufficientBalance(sdbTasks, task.TableId)
								if err != nil {
									log.WithFields(logrus.Fields{
										"id": task.Id,
									}).Error("UpdateHistoryInsufficientBalance error: ", err)
									continue
								}
							}

							continue
						}
					} else {
						// token

						contractAddress := common.HexToAddress(task.Asset)
						if contractAddress == (common.Address{}) {
							log.WithField("id", task.Id).Errorln("tasks asset zero")
							continue
						}

						abToken, err := newasset.NewBaseToken(contractAddress, client)
						if err != nil {
							log.WithField("id", task.Id).Errorln(err)
							continue
						}

						if assetAttribute&utils.AttributeMintable == utils.AttributeMintable {
							// mint(to,value)
							// check from address mintable balance

							// check from native coin balance
							// get gaslimit

							suggestGasPrice, err := client.SuggestGasPrice(context.Background())
							if err != nil {
								log.WithFields(logrus.Fields{
									"id":   task.Id,
									"from": from.String(),
								}).Errorln("get gas price error:", err)
								continue
							}
							if x.config.MaxGasPrice != nil && x.config.MaxGasPrice.Cmp(big.NewInt(0)) >= 0 && x.config.MaxGasPrice.Cmp(suggestGasPrice) < 0 {
								log.WithFields(logrus.Fields{
									"SuggestGasPrice": suggestGasPrice.String(),
									"MaxGasPrice":     x.config.MaxGasPrice.String(),
								}).Warnln("Try set gas price to max")
								suggestGasPrice.Set(x.config.MaxGasPrice)
							}
							gas := big.NewInt(0).Mul(suggestGasPrice, big.NewInt(0).SetUint64(utils.GasLimitTokenTransfer))
							fromBalance, err := client.BalanceAt(context.Background(), from, nil)
							if err != nil {
								log.WithFields(logrus.Fields{
									"id":   task.Id,
									"from": from.String(),
								}).Errorln("get balance error:", err)
								continue
							}
							if fromBalance.Cmp(gas) < 0 {
								log.WithFields(logrus.Fields{
									"id":      task.Id,
									"from":    from.String(),
									"balance": fromBalance.String(),
									"gas":     gas.String(),
								}).Warnln("token asset insufficient balance for gas")

								if task.TableNo == utils.TableNoNewBridgeHistory {
									// update history
									err = x.UpdateHistoryInsufficientBalance(sdbTasks, task.TableId)
									if err != nil {
										log.WithFields(logrus.Fields{
											"id": task.Id,
										}).Error("UpdateHistoryInsufficientBalance error: ", err)
										continue
									}
								}

								continue
							}

							data, err = parsed.Pack("mint", transferTo, transferToValue)
							if err != nil {
								log.WithField("id", task.Id).Errorln("parsed mint data error: ", err)
								continue
							}
							_, err = client.EstimateGas(context.Background(), ethereum.CallMsg{
								From:     from,
								To:       &contractAddress,
								GasPrice: suggestGasPrice,
								Value:    big.NewInt(0),
								Data:     data,
							})
							if err != nil {
								log.WithFields(logrus.Fields{
									"id":      task.Id,
									"from":    from.String(),
									"balance": fromBalance.String(),
									"gas":     gas.String(),
								}).Warnln("asset mint failed insufficient permissions:", err)

								if task.TableNo == utils.TableNoNewBridgeHistory {
									// update history
									err = x.UpdateHistoryInsufficientPermissions(sdbTasks, task.TableId)
									if err != nil {
										log.WithFields(logrus.Fields{
											"id": task.Id,
										}).Error("UpdateHistoryInsufficientPermissions error: ", err)
										continue
									}
								}

								continue
							}
						} else {
							// transfer(to,value)
							// check from address balance

							fromBalance, err := abToken.BalanceOf(nil, from)
							if err != nil {
								log.WithFields(logrus.Fields{
									"id":   task.Id,
									"from": from.String(),
								}).Errorln("get balance error:", err)
								continue
							}

							if fromBalance.Cmp(transferToValue) < 0 {
								log.WithFields(logrus.Fields{
									"id":      task.Id,
									"from":    from.String(),
									"balance": fromBalance.String(),
									"amount":  transferToValue.String(),
								}).Warnln("native asset insufficient balance")

								if task.TableNo == utils.TableNoNewBridgeHistory {
									// update history
									err = x.UpdateHistoryInsufficientBalance(sdbTasks, task.TableId)
									if err != nil {
										log.WithFields(logrus.Fields{
											"id": task.Id,
										}).Error("UpdateHistoryInsufficientBalance error: ", err)
										continue
									}
								}

								continue
							}
						}
					}

					if !database.Verify(&task, x.cb.CoreSignKeyId) {
						log.WithField("id", task.Id).Errorln("signature verification failed")
						continue
					}
				} else if task.ActionType == utils.TasksActionTypeOfCold {
					// WithdrawMainAddress ==> tokenAddress/ColdAddress
					if from.String() != x.config.WithdrawMainAddress.String() {
						log.WithFields(logrus.Fields{
							"id":                  task.Id,
							"from":                from.String(),
							"WithdrawMainAddress": x.config.WithdrawMainAddress.String(),
						}).Errorln("token can only be sent from WithdrawMainAddress")
						continue
					}
					if to.String() != coldMainAddress.String() && transferTo.String() != coldMainAddress.String() {
						log.WithFields(logrus.Fields{
							"id":              task.Id,
							"to":              to.String(),
							"transferTo":      transferTo.String(),
							"coldMainAddress": coldMainAddress.String(),
						}).Errorln("token can only be sent to ColdMainAddress")
						continue
					}

					tx = &TaskTransaction{
						ID:    task.Id,
						From:  from,
						To:    to,
						Value: value,
						Data:  data,
						// GasLimit: task.GasLimit,
						// GasPrice: gasPrice,
					}
					if !database.Verify(&task, x.config.ChainManagerSignKeyId) {
						log.WithField("id", task.Id).Errorln("signature verification failed")
						continue
					}
				} else if task.ActionType == utils.TasksActionTypeOfManagerMerge {
					if task.Asset != "" && assetAttribute&utils.AttributeBurnable == utils.AttributeBurnable {
						// ok, burn, only for token
						if transferTo.String() != (common.Address{}).String() {
							log.WithField("id", task.Id).Errorln("token can only be burn to zero address")
							continue
						}
					} else {
						// internalAddress ==> tokenAddress/ColdAddress
						if to.String() != x.config.WithdrawMainAddress.String() && transferTo.String() != x.config.WithdrawMainAddress.String() {
							log.WithField("id", task.Id).Errorln("token can only be sent to WithdrawMainAddress")
							continue
						}
					}
					exist, err := x.isInternalAddress(sdb, from)
					if err != nil {
						log.WithField("id", task.Id).Errorln("check internal address error: ", from.String())
						continue
					}
					if !exist {
						log.WithField("id", task.Id).Errorln("from address not internal address: ", from.String())
						continue
					}
					tx = &TaskTransaction{
						ID:    task.Id,
						From:  from,
						To:    to,
						Value: value,
						Data:  data,
						// GasLimit: task.GasLimit,
						// GasPrice: gasPrice,
					}
					if !database.Verify(&task, x.config.ChainManagerSignKeyId) {
						log.WithField("id", task.Id).Errorln("signature verification failed")
						continue
					}
				} else if task.ActionType == utils.TasksActionTypeOfFee {
					// no burn only transfer
					// internalAddress ==> tokenAddress/ColdAddress
					feeAddress, err := database.LoadFeeAddress(sdbTasks, x.config.Network, x.config.ChainId, x.cb.ToolsSignKeyId)
					if err != nil {
						log.WithField("id", task.Id).Errorln("get fee address error: ", err)
						continue
					}
					if to.String() != feeAddress && transferTo.String() != feeAddress {
						log.WithField("id", task.Id).Errorln("token can only be sent to FeeAddress")
						continue
					}

					exist, err := x.isInternalAddress(sdb, from)
					if err != nil {
						log.WithField("id", task.Id).Errorln("check internal address error: ", from.String())
						continue
					}
					if !exist {
						log.WithField("id", task.Id).Errorln("from address not internal address: ", from.String())
						continue
					}
					tx = &TaskTransaction{
						ID:    task.Id,
						From:  from,
						To:    to,
						Value: value,
						Data:  data,
						// GasLimit: task.GasLimit,
						// GasPrice: gasPrice,
					}
					if !database.Verify(&task, x.config.ChainManagerSignKeyId) {
						log.WithField("id", task.Id).Errorln("signature verification failed")
						continue
					}
				} else if task.ActionType == utils.TasksActionTypeOfManagerCharge {
					// WithdrawMainAddress ==> internalAddress
					if from.String() != x.config.WithdrawMainAddress.String() {
						log.WithField("id", task.Id).Errorln("token can only be sent from WithdrawMainAddress")
						continue
					}
					exist, err := x.isInternalAddress(sdb, to)
					if err != nil {
						log.WithField("id", task.Id).Errorln("check internal address error: ", to.String())
						continue
					}
					if !exist {
						log.WithField("id", task.Id).Errorln("to address not internal address: ", to.String())
						continue
					}
					if !database.Verify(&task, x.config.ChainManagerSignKeyId) {
						log.WithField("id", task.Id).Errorln("signature verification failed")
						continue
					}
				} else if task.ActionType == utils.TasksActionTypeOfSwap {
					// WithdrawMainAddress ==> userAddress
					if from.String() != x.config.WithdrawMainAddress.String() {
						log.WithField("id", task.Id).Errorln("token can only be sent from WithdrawMainAddress")
						continue
					}
					if len(data) != 0 {
						log.WithField("id", task.Id).Errorln("no data need for Swap")
						continue
					}
					// force
					if value.Cmp(swap.CapAmountOfNEWValue1USD) > 0 {
						log.WithFields(logrus.Fields{
							"id":    task.Id,
							"value": value.String(),
							"cap":   swap.CapAmountOfNEWValue1USD.String(),
						}).Errorln("swap amount of NEW so max")
						continue
					}
					if !database.Verify(&task, x.cb.CoreSignKeyId) {
						log.WithField("id", task.Id).Errorln("signature verification failed")
						continue
					}
				} else {
					log.WithFields(logrus.Fields{"id": task.Id, "actionType": task.ActionType}).Warnln("not support task action type")
					continue
				}

				// ok, check pass
				if tx == nil {
					tx = &TaskTransaction{
						ID:    task.Id,
						From:  from,
						To:    to,
						Value: value,
						Data:  data,
						// GasLimit: gasLimit,
						// GasPrice: gasPrice,
					}
				}

				{
					fields := logrus.Fields{
						"id":    tx.ID,
						"from":  tx.From.String(),
						"to":    tx.To.String(),
						"value": tx.Value.String(),
					}
					if len(tx.Data) > 0 {
						fields["data"] = hex.EncodeToString(tx.Data)
					}
					log.WithFields(fields).Infoln("add tx to pending send list")
				}

				tx.TableNo = task.TableNo
				tx.TableId = task.TableId
				tx.ActionType = task.ActionType
				taskBatch[from] = append(taskBatch[from], tx)
			}

			if len(taskBatch) > 0 {
				x.execTaskBatch(taskBatch)
			}
		}()

		time.Sleep(time.Second * 3) // > blockPeriod
	}
}

func (x *Chain) isInternalAddress(sess db.Session, iAddress common.Address) (bool, error) {
	err := sess.SQL().Select("id").From("addresses").Where(
		"address", iAddress.String()).One(&struct {
		Id uint64 `db:"id"`
	}{})
	if err == db.ErrNoMoreRows {
		return false, nil
	} else if err != nil {
		return false, err
	}

	return true, nil
}

func (x *Chain) execTaskBatch(taskBatch map[common.Address]TaskTransactions) {
	client, err := ethclient.Dial(x.config.RpcURL)
	if err != nil {
		log.Errorln(Error(err))
		return
	}
	defer client.Close()

	chainID := big.NewInt(0).Set(x.chainID)

	var suggestGasPrice *big.Int
	if x.config.GasPrice != nil {
		suggestGasPrice, err = utils.GetGasPrice(x.config.GasPrice)
		if err != nil {
			log.Errorln(Error(err))
			return
		}
	} else {
		suggestGasPrice, err = client.SuggestGasPrice(context.Background())
		if err != nil {
			log.Errorln(Error(err))
			return
		}
	}
	if x.config.MaxGasPrice != nil && x.config.MaxGasPrice.Cmp(big.NewInt(0)) >= 0 && x.config.MaxGasPrice.Cmp(suggestGasPrice) < 0 {
		log.WithFields(logrus.Fields{
			"SuggestGasPrice": suggestGasPrice.String(),
			"MaxGasPrice":     x.config.MaxGasPrice.String(),
		}).Warnln("Try set gas price to max")
		suggestGasPrice.Set(x.config.MaxGasPrice)
	}
	gasLimitMax := utils.GasLimitTokenTransfer // force gasLimit

	sdbTasks, err := database.OpenDatabase(x.DB.Adapter, x.DB.ConnectionURL)
	if err != nil {
		log.Errorln(err)
		return
	}
	defer sdbTasks.Close()

	for address, txs := range taskBatch {
		func() {
			ctx := context.Background()
			nonce, err := client.PendingNonceAt(ctx, address)
			if err != nil {
				log.Errorln(Error(err))
				return
			}

			balance, err := client.PendingBalanceAt(ctx, address)
			if err != nil {
				log.Errorln(Error(err))
				return
			}
			totalAmount := big.NewInt(0)

			sendTxList := make(TaskTransactions, 0)
			for _, tx := range txs {
				totalAmount.Add(totalAmount, tx.Value)

				// handle gas
				gasLimit := tx.GasLimit
				if gasLimit < utils.GasLimitTransfer {
					txTo := tx.To.(common.Address)
					gasLimit, err = client.EstimateGas(context.Background(), ethereum.CallMsg{
						From:  address,
						To:    &txTo,
						Value: tx.Value,
						Data:  tx.Data,
					})
					if err != nil {
						log.WithField("id", tx.ID).Errorln(Error(err), tx.ID)
						continue
					}
					if gasLimit > gasLimitMax {
						// ok, error
						log.WithFields(logrus.Fields{
							"gasLimit":    gasLimit,
							"gasLimitMax": gasLimitMax,
							"id":          tx.ID,
						}).Warnln("gas limit exceeds the maximum")

						gasLimit = gasLimitMax

						// continue
					}
				}
				gasPrice := tx.GasPrice
				if gasPrice == nil || gasPrice.Cmp(big.NewInt(0)) <= 0 {
					gasPrice = big.NewInt(0).Set(suggestGasPrice)
				}

				gas := big.NewInt(0).Mul(gasPrice, big.NewInt(0).SetUint64(gasLimit))

				totalAmount.Add(totalAmount, gas)

				tx.GasLimit = gasLimit
				tx.GasPrice = gasPrice

				sendTxList = append(sendTxList, tx)
			}
			if totalAmount.Cmp(balance) > 0 {
				log.WithFields(logrus.Fields{
					"balance":     balance.String(),
					"totalAmount": totalAmount.String(),
					"address":     address.String(),
				}).Errorln("the total amount of pending send txs big than the pending balance")

				err = sdbTasks.Tx(func(dbtx db.Session) error {
					for _, tx := range txs {
						if tx.TableNo == utils.TableNoNewBridgeHistory &&
							tx.ActionType == utils.TasksActionTypeOfNewBridge {
							err = x.UpdateHistoryInsufficientBalance(dbtx, tx.TableId)
							if err != nil {
								return Error(err)
							}
						}
					}
					return nil
				})
				if err != nil {
					log.Error("update history status error: ", Error(err))
					return
				}

				return
			}

			pkey, err := x.getKey(ctx, address)
			if err != nil {
				log.Error("getKey: ", Error(err))
				return
			}
			defer zeroKey(pkey)

			for _, tx := range sendTxList {
				txTo := tx.To.(common.Address)
				nTx := types.NewTx(&types.LegacyTx{
					Nonce:    nonce,
					GasPrice: tx.GasPrice,
					Gas:      tx.GasLimit,
					To:       &txTo,
					Value:    tx.Value,
					Data:     tx.Data,
				})
				signTx, err := types.SignTx(nTx, types.NewEIP155Signer(chainID), pkey)
				if err != nil {
					log.Errorln(Error(err), tx.ID)
					continue
				}

				log.WithFields(logrus.Fields{
					"id":    tx.ID,
					"hash":  signTx.Hash().String(),
					"nonce": nonce,
					"from":  address.String(),
					"to":    tx.To.String(),
					"value": tx.Value.String(),
				}).Infoln("send tx: ", tx.ID)

				err = sdbTasks.Tx(func(dbtx db.Session) error {
					err = dbtx.Collection("tasks").Find(
						"id", tx.ID).Update(db.Cond{
						"tx_hash": signTx.Hash().String(),
						// "gas_price": signTx.GasPrice().Uint64(),
						"status": utils.TasksStatusOfBroadcast, // broadcast
					})
					if err != nil {
						return Error(err)
					}
					err = database.UpdateSign(dbtx, database.TableOfTasks, tx.ID, x.config.ChainTaskSignKeyId)
					if err != nil {
						return Error(err)
					}

					if tx.TableNo == utils.TableNoNewBridgeHistory {
						if tx.ActionType == utils.TasksActionTypeOfNewBridge {
							err = dbtx.Collection("history").Find(
								"id", tx.TableId).Update(db.Cond{
								"target_tx_hash":  signTx.Hash().String(),
								"target_tx_index": 0,
								"status":          utils.BridgeWithdraw})
							if err != nil {
								return Error(err)
							}
							err = database.UpdateSign(dbtx, database.TableOfHistory, tx.TableId, x.config.ChainTaskSignKeyId)
							if err != nil {
								return Error(err)
							}
							if err != nil {
								return Error(err)
							}
						} else if tx.ActionType == utils.TasksActionTypeOfSwap {
							err = dbtx.Collection("history").Find(
								"id", tx.TableId).Update(db.Cond{
								"swap_tx_hash":  signTx.Hash().String(),
								"swap_tx_index": 0,
							})
							if err != nil {
								return Error(err)
							}
							err = database.UpdateSign(dbtx, database.TableOfHistory, tx.TableId, x.config.ChainTaskSignKeyId)
							if err != nil {
								return Error(err)
							}
							if err != nil {
								return Error(err)
							}
						}

					} else if tx.TableNo == utils.TableNoManager {
						if tx.ActionType == utils.TasksActionTypeOfManagerMerge {
							err = dbtx.Collection("history").Find(
								"id", tx.TableId).Update(db.Cond{
								"merge_tx_hash": signTx.Hash().String(),
								"merge_status":  utils.HistoryMergeStatusBroadcast})
							if err != nil {
								return Error(err)
							}
						} else if tx.ActionType == utils.TasksActionTypeOfFee {
							err = dbtx.Collection("history").Find(
								"id", tx.TableId).Update(db.Cond{
								"fee_tx_hash": signTx.Hash().String(),
								"fee_status":  utils.HistoryFeeStatusBroadcast})
							if err != nil {
								return Error(err)
							}
						}
					}

					err = client.SendTransaction(context.Background(), signTx)
					if err != nil {
						return Error(err)
					}

					return nil
				})
				if err != nil {
					log.Errorln(err, tx.ID)
					continue
				}

				nonce++

				// force sleep
				time.Sleep(x.durationOfExecTask)
			}
		}()

	}
}

func (x *Chain) checkTaskStatus() {
	client, err := ethclient.Dial(x.config.RpcURL)
	if err != nil {
		log.Errorln(Error(err))
		return
	}
	defer client.Close()

	sdbTasks, err := database.OpenDatabase(x.DB.Adapter, x.DB.ConnectionURL)
	if err != nil {
		log.Errorln(Error(err))
		return
	}
	defer sdbTasks.Close()

	res := sdbTasks.SQL().Select(
		"id", "tx_hash", "from", "value", "table_no", "table_id", "action_type").From(
		"tasks").Where("blockchain_id", x.bcId).And(
		"status", utils.TasksStatusOfBroadcast)

	var tasks []database.Task
	err = res.All(&tasks)
	if err != nil {
		log.Errorln(Error(err))
		return
	}

	if len(tasks) == 0 {
		// fmt.Println("no tx to check, sleep 10s")
		return
	}

	for _, t := range tasks {
		hash := common.HexToHash(t.TxHash)
		if hash == (common.Hash{}) {
			log.Errorln("invalid hash")
			continue
		}

		txr, err := client.TransactionReceipt(context.Background(), hash)
		if err != nil {
			log.WithField("hash", hash.String()).Errorln(err)
			continue
		}

		if txr == nil {
			log.WithField("hash", hash.String()).Errorln("receipt nil")
			continue
		}

		log.WithFields(logrus.Fields{
			"id":     t.Id,
			"hash":   hash.String(),
			"status": txr.Status,
		}).Infoln("check tx")

		if t.Value == "" {
			t.Value = "0"
		}
		if err := x.updateTxExecuted(sdbTasks, t, txr, client); err != nil {
			log.Errorln(err)
			// nothing to do
		}
	}

	return

}

func (x *Chain) updateTxExecuted(sdbTasks db.Session, task database.Task, txr *types.Receipt, client *ethclient.Client) (err error) {
	if txr == nil {
		log.Errorln("receipt nil")
		return
	}

	status := utils.TasksStatusOfExecuted
	if txr.Status == 0 {
		status = utils.TasksStatusOfExecutedFailed
		log.WithFields(logrus.Fields{
			"tx_hash": txr.TxHash.String(),
			"id":      task.Id,
		}).Warnln("tx confirmed but failed")
	}

	tx, _, err := client.TransactionByHash(context.Background(), txr.TxHash)
	if err != nil {
		log.WithFields(logrus.Fields{
			"tx_hash": txr.TxHash.String(),
			"id":      task.Id,
		}).Warnln("get tx error")
		return err
	}
	fee := big.NewInt(0).Mul(tx.GasPrice(), big.NewInt(0).SetUint64(txr.GasUsed))

	// get block timestamp
	header, err := client.HeaderByNumber(context.Background(), txr.BlockNumber)
	if err != nil {
		log.WithFields(logrus.Fields{
			"tx_hash":      txr.TxHash.String(),
			"block_number": txr.BlockNumber.Uint64(),
			"id":           task.Id,
		}).Warnln("get header error")
		return err
	}

	err = sdbTasks.Tx(func(dbtx db.Session) error {
		err = dbtx.Collection("tasks").Find("id", task.Id).Update(
			db.Cond{
				"status":       status,
				"block_number": txr.BlockNumber.String(),
				"fee":          fee.String(),
			})
		if err != nil {
			return Error(err)
		}

		if task.ActionType == utils.TasksActionTypeOfNewBridge {
			if task.TableNo == utils.TableNoNewBridgeHistory {
				_, err = dbtx.SQL().Update("history").Set(
					"target_block_number", txr.BlockNumber.String()).Set(
					"target_block_timestamp", time.Unix(int64(header.Time), 0).UTC().Format(utils.TimeFormat)).Set(
					"target_tx_hash", task.TxHash).Set(
					"status", utils.BridgeWithdrawConfirmed).Where(
					"id", task.TableId).And(
					"target_blockchain_id", x.bcId).Exec()
				if err != nil {
					return Error(err)
				}
			}
		} else if task.ActionType == utils.TasksActionTypeOfSwap && task.TableNo == utils.TableNoNewBridgeHistory {
			_, err = dbtx.SQL().Update("history").Set(
				"swap_block_number", txr.BlockNumber.String()).Set(
				"swap_block_timestamp", time.Unix(int64(header.Time), 0).UTC().Format(utils.TimeFormat)).Set(
				"swap_tx_hash", task.TxHash).Where(
				"id", task.TableId).And(
				"target_blockchain_id", x.bcId).Exec()
			if err != nil {
				return Error(err)
			}
		} else if task.ActionType == utils.TasksActionTypeOfManagerMerge && task.TableNo == utils.TableNoManager {
			_, err = dbtx.SQL().Update("history").Set(
				"merge_status", utils.HistoryMergeStatusConfirmed).Where(
				"id", task.TableId).And(
				"blockchain_id", x.bcId).And(
				"merge_tx_hash", task.TxHash).Exec()
			if err != nil {
				return Error(err)
			}
		} else if task.ActionType == utils.TasksActionTypeOfFee && task.TableNo == utils.TableNoManager {
			_, err = dbtx.SQL().Update("history").Set(
				"fee_status", utils.HistoryMergeStatusConfirmed).Where(
				"id", task.TableId).And(
				"blockchain_id", x.bcId).And(
				"fee_tx_hash", task.TxHash).Exec()
			if err != nil {
				return Error(err)
			}
		}

		return nil
	})
	if err != nil {
		return Error(err)
	}

	return
}

func (x *Chain) UpdateHistoryInsufficientBalance(sdbTasks db.Session, tableId uint64) (err error) {
	return x.updateHistoryStatus(sdbTasks, tableId, utils.BridgeInsufficientBalance)
}

func (x *Chain) UpdateHistoryInsufficientPermissions(sdbTasks db.Session, tableId uint64) (err error) {
	return x.updateHistoryStatus(sdbTasks, tableId, utils.BridgeInsufficientPermissions)
}

func (x *Chain) updateHistoryStatus(sdbTasks db.Session, tableId uint64, status int) (err error) {
	err = sdbTasks.Tx(func(dbtx db.Session) error {
		var history database.History
		err = dbtx.Collection(database.TableOfHistory).Find(
			"id", tableId).One(&history)
		if err != nil {
			return Error(err)
		}
		if history.Status == utils.BridgePendingWithdraw {
			err = dbtx.Collection(database.TableOfHistory).Find(
				"id", tableId).Update(db.Cond{
				"status": status})
			if err != nil {
				return Error(err)
			}
			err = database.UpdateSign(dbtx, database.TableOfHistory, tableId, x.config.ChainTaskSignKeyId)
			if err != nil {
				return Error(err)
			}

		}
		return nil
	})
	if err != nil {
		return Error(err)
	}

	return nil
}
