package chain

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"time"

	dbtcutil "github.com/dogecoinw/doged/btcutil"
	dchaincfg "github.com/dogecoinw/doged/chaincfg"
	dchainhash "github.com/dogecoinw/doged/chaincfg/chainhash"
	drpcclient "github.com/dogecoinw/doged/rpcclient"
	dtxscript "github.com/dogecoinw/doged/txscript"
	"github.com/sirupsen/logrus"
	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
)

func (x *Chain) checkDogecoinTaskStatus() {
	blockBookClient := NewBlockBookClient(x.DogecoinConfig.BlockbookURL)

	sdbTasks, err := database.OpenDatabase(x.DB.Adapter, x.DB.ConnectionURL)
	if err != nil {
		log.Errorln(Error(err))
		return
	}
	defer sdbTasks.Close()

	res := sdbTasks.SQL().Select(
		"id", "tx_hash", "fee_tx_hash", "from", "value", "table_no", "table_id", "action_type").From(
		"tasks_doge").Where(
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
		txHash, err := dchainhash.NewHashFromStr(t.TxHash)
		if err != nil {
			log.Errorln("invalid hash: ", err)
			continue
		}

		txr, err := blockBookClient.GetTx(txHash)
		if err != nil {
			log.WithField("hash", txHash.String()).Errorln(err)
			continue
		}

		if txr == nil {
			log.WithField("hash", txHash.String()).Errorln("receipt nil")
			continue
		}

		// TODO:
		if txr.Confirmations < 2 {
			log.WithFields(logrus.Fields{
				"id":            t.Id,
				"hash":          txHash.String(),
				"confirmations": txr.Confirmations,
			}).Debugln("wait tx to be more confirmations")
			continue
		}

		log.WithFields(logrus.Fields{
			"id":   t.Id,
			"hash": txHash.String(),
			// "status": txr.Confirmations,
			"confirmations": txr.Confirmations,
		}).Infoln("check tx")

		if t.Value == "" {
			t.Value = "0"
		}

		// TODO:
		updateDogecoinTxExecuted(sdbTasks, t, txr)
	}

	return
}

func updateDogecoinTxExecuted(sdbTasks db.Session, task database.Task, txr *TxRawResult) (err error) {
	if txr == nil {
		log.Errorln("receipt nil")
		return
	}

	status := utils.TasksStatusOfExecuted
	if txr.Confirmations < 2 { // TODO: maybe
		log.WithFields(logrus.Fields{
			"tx_hash": txr.Txid,
			"id":      task.Id,
		}).Warnln("tx confirmed but failed")
	}

	err = sdbTasks.Tx(func(dbtx db.Session) error {
		err = dbtx.Collection("tasks_doge").Find("id", task.Id).Update(
			db.Cond{"status": status})
		if err != nil {
			return Error(err)
		}

		if task.ActionType == utils.TasksActionTypeOfNewBridge && task.TableNo == utils.TableNoNewBridgeHistory {
			err = dbtx.Collection("history").Find(
				"id", task.TableId).Update(db.Cond{
				"target_tx_hash":  task.TxHash,
				"target_tx_index": task.TxIndex,
				"status":          utils.BridgeWithdraw})
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

func (x *Chain) startDogecoinTransfer() {
	log.Infof("Tasks exec speed: 1 tasks per %s", x.durationOfExecTask.String())

	var (
		ok                  bool
		withdrawMainAddress dbtcutil.Address
		coldAddress         dbtcutil.Address
	)

	if x.DogecoinConfig.WithdrawMainAddress == nil {
		log.Errorln("Tasks get withdrawMainAddress nil")
		return
	}
	withdrawMainAddress, ok = x.DogecoinConfig.WithdrawMainAddress.(dbtcutil.Address)
	if !ok {
		log.Errorln("Tasks get withdrawMainAddress error: ", x.DogecoinConfig.WithdrawMainAddress)
		return
	}
	if x.DogecoinConfig.ColdAddress == nil {
		coldAddress = withdrawMainAddress
		log.Infoln("Tasks use withdrawMainAddress as coldAddress ", coldAddress.String())
	} else {
		coldAddress = x.DogecoinConfig.ColdAddress.(dbtcutil.Address)
	}
	if coldAddress == nil {
		log.Errorln("Tasks get withdrawMainAddress error: ", x.DogecoinConfig.ColdAddress)
		return
	}

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

			res := sdbTasks.SQL().Select(
				"id", "from", "to", "value", "tick",
				"created_at", "schedule_at", "canceled_at", "status", "table_no", "table_id", "action_type").From("tasks_doge").Where(
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

			// tick => from ==> tx
			taskBatch := make(map[dbtcutil.Address]map[string]TaskTransactions)
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

				from, err := dbtcutil.DecodeAddress(task.From, &dchaincfg.MainNetParams)
				if err != nil {
					log.WithField("id", task.Id).Errorln(ErrorCode(errInvalidAddress))
					continue
				}
				if from == nil {
					log.WithField("id", task.Id).Errorln("from address zero")
					continue
				}

				to, err := dbtcutil.DecodeAddress(task.To, &dchaincfg.MainNetParams)
				if err != nil {
					log.WithField("id", task.Id).Errorln(ErrorCode(errInvalidAddress))
					continue
				}
				if to == nil {
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
				if task.Asset == "" {
					log.WithField("id", task.Id).Errorln("dogecoin no tick")
					continue
				}
				tick := task.Asset

				var tx *TaskTransaction
				if task.ActionType == utils.TasksActionTypeOfNewBridge {
					// WithdrawMainAddress ==> tokenAddress/userAddress
					if from.String() != withdrawMainAddress.String() {
						log.WithFields(logrus.Fields{"id": task.Id,
							"from":                from.String(),
							"withdrawMainAddress": withdrawMainAddress.String(),
							"actionType":          utils.TasksActionTypeText[task.ActionType]}).Errorln("token can only be sent from WithdrawMainAddress")
						continue
					}
				} else if task.ActionType == utils.TasksActionTypeOfManagerMerge {
					// InternalAddress ==> ColdWallet
					// Fee is WithdrawMainAddress
					if to.String() != coldAddress.String() {
						log.WithFields(logrus.Fields{"id": task.Id,
							"to":          to.String(),
							"coldAddress": coldAddress.String(),
							"actionType":  utils.TasksActionTypeText[task.ActionType]}).Errorln("token can only be sent to ColdAddress")
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
					}
				}

				if taskBatch[from] == nil {
					taskBatch[from] = make(map[string]TaskTransactions, 0)
				}
				if taskBatch[from][tick] == nil {
					taskBatch[from][tick] = make(TaskTransactions, 0)
				}
				taskBatch[from][tick] = append(taskBatch[from][tick], tx)
			}

			if len(taskBatch) > 0 {
				x.execDogecoinTaskBatch(taskBatch, withdrawMainAddress)
			}
		}()

		time.Sleep(time.Second * 3) // > blockPeriod
	}
}

func (x *Chain) execDogecoinTaskBatch(taskBatch map[dbtcutil.Address]map[string]TaskTransactions,
	feeAddress dbtcutil.Address) {
	nodeClientConnConfig := drpcclient.ConnConfig{
		Host:         x.DogecoinConfig.RpcURL,
		Endpoint:     "ws",
		User:         x.DogecoinConfig.Username,
		Pass:         x.DogecoinConfig.Password,
		HTTPPostMode: true, // Bitcoin core only supports HTTP POST mode
		DisableTLS:   true, // Bitcoin core does not provide TLS by default
	}
	rpcClient, err := drpcclient.New(&nodeClientConnConfig, nil)
	if err != nil {
		log.Errorln(Error(err))
		return
	}

	indexerClient := NewDRC20Client(x.DogecoinConfig.IndexerURL)

	// blockbookClient := NewBlockBookClient(x.DogecoinConfig.BlockbookURL)

	sdbTasks, err := database.OpenDatabase(x.DB.Adapter, x.DB.ConnectionURL)
	if err != nil {
		log.Errorln(err)
		return
	}
	defer sdbTasks.Close()

	wallets := make(map[string]*dogecoinWallet)
	defer func() {
		for _, w := range wallets {
			if w != nil && w.privateKey != nil {
				w.privateKey.Zero()
			}
		}
	}()

	for address, txsBatch := range taskBatch {

		for tick, txs := range txsBatch {

			func() {
				fmt.Println(address, tick, len(txs))

				// ctx := context.Background()

				drc20Balance, err := indexerClient.Balance(tick, address)
				if err != nil {
					log.Errorln(Error(err))
					return
				}
				log.WithFields(logrus.Fields{
					"address": address.String(),
					"tick":    tick,
					"balance": drc20Balance.String(),
				}).Warnln("balance show")

				totalAmount := big.NewInt(0)

				sendTxList := make(TaskTransactions, 0)
				for _, tx := range txs {
					totalAmount.Add(totalAmount, tx.Value)

					sendTxList = append(sendTxList, tx)
				}
				if totalAmount.Cmp(drc20Balance) > 0 {
					log.WithFields(logrus.Fields{
						"balance":     drc20Balance.String(),
						"totalAmount": totalAmount.String(),
						"tick":        tick,
						"address":     address.String(),
					}).Errorln("the total amount of pending send txs big than the pending balance")
					return
				}

				var (
					w, feeWallet *dogecoinWallet
				)

				if wallets[address.String()] == nil {
					w, err = x.getWallet(address)
					if err != nil {
						log.Errorln("getWallet error: ", err)
						return
					}
				}

				if wallets[feeAddress.String()] == nil {
					feeWallet, err = x.getWallet(feeAddress)
					if err != nil {
						log.Errorln("getWallet error: ", err)
						return
					}
				}

				for _, tx := range sendTxList {
					var doge20TransferTx = DRC20Tx{
						P:    "drc-20",
						Op:   "transfer",
						Tick: tick,
						Amt:  tx.Value.String(),
					}
					dd, err := json.Marshal(doge20TransferTx)
					if err != nil {
						log.WithFields(logrus.Fields{
							"id": tx.ID}).Errorln("doge20TransferTx error: ", err)
						return
					}
					if tx.To == nil {
						log.WithFields(logrus.Fields{
							"id": tx.ID}).Errorln("tx to is nil")
						return
					}
					signTxs, stxo, err := inscribe(address, tx.To.(dbtcutil.Address), dd, w, feeWallet)
					if err != nil {
						log.WithFields(logrus.Fields{
							"id": tx.ID}).Errorln("inscribe error:", err)
						return
					}
					if len(signTxs) < 2 {
						log.WithFields(logrus.Fields{
							"id":    tx.ID,
							"from":  address.String(),
							"to":    tx.To.String(),
							"value": tx.Value.String(),
						}).Errorln("txs len error", len(signTxs))
						return
					}
					log.WithFields(logrus.Fields{
						"id":      tx.ID,
						"feeHash": signTxs[0].TxHash().String(),
						"hash":    signTxs[1].TxHash().String(),
						"from":    address.String(),
						"to":      tx.To.String(),
						"value":   tx.Value.String(),
						"tick":    tick,
						"utxo":    stxo[0].Txid.String(),
					}).Infoln("send tx: ", tx.ID)

					// insert into stxo
					// insert into tasks

					err = sdbTasks.Tx(func(dbtx db.Session) error {
						err = dbtx.Collection("tasks_doge").Find(
							"id", tx.ID).Update(db.Cond{
							"fee_tx_hash": signTxs[0].TxHash().String(),
							"tx_hash":     signTxs[1].TxHash().String(),
							"status":      utils.TasksStatusOfBroadcast, // broadcast
						})
						if err != nil {
							return Error(err)
						}

						for _, utxo := range stxo {

							script, err := hex.DecodeString(utxo.ScriptPubKey)
							if err != nil {
								return Error(err)
							}
							_, iAddress, _, err := dtxscript.ExtractPkScriptAddrs(script, &dchaincfg.MainNetParams)
							if err != nil {
								return Error(err)
							}
							if len(iAddress) != 1 {
								return fmt.Errorf("ExtractPkScriptAddrs error")
							}

							_, err = dbtx.Collection("doge_stxo").Insert(database.DogeSTXO{
								Hash:            utxo.Txid.String(),
								Pos:             utxo.Vout,
								InternalAddress: iAddress[0].String(),
								Value:           utxo.Value.String(),
								Height:          utxo.Height,
								SpentHash:       signTxs[0].TxHash().String(),
								SpentPos:        1,
								TableId:         tx.ID,
								Status:          utils.TasksStatusOfBroadcast,
							})
							if err != nil {
								return Error(err)
							}
						}

						{
							buf := bytes.NewBuffer(make([]byte, 0, signTxs[0].SerializeSize()))
							if err := signTxs[0].Serialize(buf); err != nil {
								return err
							}
							fmt.Println(hex.EncodeToString(buf.Bytes()))

							buf2 := bytes.NewBuffer(make([]byte, 0, signTxs[1].SerializeSize()))
							if err := signTxs[1].Serialize(buf2); err != nil {
								return err
							}
							fmt.Println(hex.EncodeToString(buf2.Bytes()))
						}

						_, err = rpcClient.SendRawTransaction(signTxs[0], false)
						if err != nil {
							return Error(err)
						}

						_, err = rpcClient.SendRawTransaction(signTxs[1], false)
						if err != nil {
							return Error(err)
						}

						return nil
					})
					if err != nil {
						log.Errorln(err, tx.ID)
						continue
					}
				}
				// 	// force sleep
				// 	time.Sleep(x.durationOfExecTask)
			}()
		}
	}
}
