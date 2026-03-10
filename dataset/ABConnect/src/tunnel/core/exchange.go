package core

import (
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	cache "github.com/patrickmn/go-cache"
	"github.com/sirupsen/logrus"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins/newton"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/swap"
)

func (c *Core) runExchangeTasks(sess db.Session, autoConfirm bool) (err error) {

	/*
			 * 1. select h.*, b.* from history h left join blockchains b on h.blockchain_id = b.id;
			 * 2. select h.*, a.id as asset_id, a.asset, a.name, a.symbol, a.decimals, a.attribute, a.network, a.chain from history h left join (select aa.*, ab.network, ab.chain from assets aa left join blockchains ab on ab.id = aa.blockchain_id) a on h.blockchain_id = a.blockchain_id and h.asset = a.asset
			 * 3. accounts: internal_blockchain_id + internal_address => dest_address + dest_blockchain_id
			 * 4. history: history.blockchain_id + history.asset => asset.id
			 * 5. pairs_list: asset_a_id + dest_blockchain_id => asset_b_id
		     * SELECT * FROM pairs LEFT JOIN assets AS assets_a ON pairs.asset_a_id = assets_a.id LEFT JOIN assets AS assets_b ON pairs.asset_b_id = assets_b.id;

	*/

	/*
		1. select * from history where status = 2;
		2. select * from accounts where internal_blockchain_id = h.blockchain_id and internal_address = h.address; ==> a.blockchain_id and a.address
		3. select * from assets where blockchain_id = h.blockchain_id and asset = h.asset;
		4. select * from pairs where asset_a_id = as.id or asset_b_id = as.id;
		5. select * from assets where blockchain_id = a.blockchain_id and id in [select_4];
		6. 3-6 using map

	*/

	size := 256 // just in case
	var historyList []*database.History
	err = sess.SQL().SelectFrom(
		database.TableOfHistory).Where(db.Or(
		db.Cond{"status": utils.BridgeDetectedDeposit},
		db.Cond{"status": utils.BridgeDeposit},
		db.Cond{"status": utils.BridgeDepositConfirmed},
		db.Cond{"status": utils.BridgeInsufficientBalance},
		db.Cond{"status": utils.BridgeInsufficientPermissions},
	)).Limit(size).All(&historyList)
	if errors.Is(err, db.ErrNoMoreRows) {
		return nil
	} else if err != nil {
		return Error(err)
	}

	if len(historyList) == 0 {
		return nil
	}

	{
		// for BridgeInsufficientBalance
		newHistoryList := make([]*database.History, 0, len(historyList))
		for _, h := range historyList {
			if h.Status == utils.BridgeInsufficientBalance || h.Status == utils.BridgeInsufficientPermissions {
				if c.notify != nil {
					if c.notifyCache == nil {
						c.notifyCache = cache.New(time.Minute*30, time.Minute*60)
					}
					if _, ok := c.notifyCache.Get(h.TxHash); ok {
						// avoid frequent notifications
						continue
					}
				}
			}
			newHistoryList = append(newHistoryList, h)
		}
		historyList = newHistoryList

		// ok, recheck
		if len(historyList) == 0 {
			return nil
		}
	}

	blockchainMap := make(map[uint64]database.Blockchain)
	var blockchainList []database.Blockchain
	err = sess.SQL().SelectFrom("blockchains").All(&blockchainList)
	if errors.Is(err, db.ErrNoMoreRows) {
		return fmt.Errorf("no blockchain")
	} else if err != nil {
		return Error(err)
	}
	for _, b := range blockchainList {
		blockchainMap[b.Id] = b
	}

	mainAddressMap := make(map[string]string)
	var configList []database.Config
	err = sess.SQL().SelectFrom("config").All(&configList)
	if errors.Is(err, db.ErrNoMoreRows) {
		return fmt.Errorf("no config")
	} else if err != nil {
		return Error(err)
	}
	for _, cfg := range configList {
		if !strings.HasSuffix(cfg.Variable, utils.WithdrawMainAddress) {
			continue
		}

		if !database.Verify(&cfg, c.ToolsSignKeyId) {
			return fmt.Errorf("config verify failed: %s", cfg.Variable)
		}

		mainAddressMap[cfg.Variable] = cfg.Value
	}

	// pairsMap := make(map[uint]*database.PairList)
	for _, h := range historyList {
		if h == nil {
			continue
		}
		// ignore sender is main withdraw address
		bc, existBc := blockchainMap[h.BlockchainId]
		if !existBc {
			log.WithFields(logrus.Fields{
				"history_id":    h.Id,
				"blockchain_id": h.BlockchainId,
			}).Errorln("no such blockchain")
			return fmt.Errorf("no such asset")
		}

		mainAddressName := fmt.Sprintf("%v-%v-%v", bc.Network, bc.ChainId, utils.WithdrawMainAddress)
		mainAddress, existMainAddress := mainAddressMap[mainAddressName]
		if !existMainAddress {
			log.WithFields(logrus.Fields{
				"history_id":    h.Id,
				"blockchain_id": h.BlockchainId,
			}).Warnln("no main address set")
		}
		if mainAddress == h.Sender {
			log.WithFields(logrus.Fields{
				"id": h.Id,
			}).Warnln("internal transfer")

			_, err = sess.SQL().Update("history").Set(
				"status", utils.BridgeInternalTx).Where(
				"id", h.Id).Exec()
			if err != nil {
				return err
			}

			continue
		}

		asset, err := c.getAsset(h.BlockchainId, h.Asset)
		if err != nil {
			return err
		}
		if asset == nil {
			log.WithFields(logrus.Fields{
				"history_id":    h.Id,
				"blockchain_id": h.BlockchainId,
				"asset":         h.Asset,
			}).Errorln("no such asset")
			return fmt.Errorf("no such asset")
		}

		// 2. select * from accounts where internal_blockchain_id = h.blockchain_id and internal_address = h.address; ==> a.blockchain_id and a.address
		// try to get to address
		var account database.Account
		err = sess.SQL().SelectFrom(
			"accounts").Where(
			"internal_blockchain_id", h.BlockchainId).And(
			"internal_address", h.Address).One(&account)
		if err != nil {
			return Error(err)
		}
		if !database.Verify(&account, c.APISignKeyId) {
			return fmt.Errorf("account signature verification failed")
		}

		targetBlockchainId := account.BlockchainId
		if targetBlockchainId == 0 {
			return fmt.Errorf("no such account")
		}
		// account.Address
		targetAddress := config.StringAddress(account.Address)

		targetBc, existTargetBc := blockchainMap[targetBlockchainId]
		if !existTargetBc {
			log.WithFields(logrus.Fields{
				"history_id":    h.Id,
				"blockchain_id": targetBlockchainId,
			}).Errorln("no such target blockchain")
			return fmt.Errorf("no such target blockchain")
		}

		// get pair
		pair, targetAsset, err := c.getPairAndDestAsset(asset.ID, targetBlockchainId)
		if err != nil {
			return err
		}

		// ok, check deposit/src
		var direction config.Direction
		if pair.AssetAId == asset.ID && pair.AssetBId == targetAsset.ID {
			direction = config.DirectionA2B
		} else if pair.AssetBId == asset.ID && pair.AssetAId == targetAsset.ID {
			direction = config.DirectionB2A
		} else {
			return fmt.Errorf("direction error")
		}

		// check disable pair direction
		if c.disabledPairs != nil && len(c.disabledPairs) > 0 {
			if c.disabledPairs[pair.ID] != nil {
				if c.disabledPairs[pair.ID][asset.ID] {
					// ok, disabled pair direction
					log.WithFields(logrus.Fields{
						"id":          h.Id,
						"pairId":      pair.ID,
						"asset":       fmt.Sprintf("%s-%s(%s)", bc.Network, asset.Name, asset.Symbol),
						"targetAsset": fmt.Sprintf("%s-%s(%s)", targetBc.Network, targetAsset.Name, targetAsset.Symbol),
					}).Errorln("pair disabled direction")

					_, err = sess.SQL().Update("history").Set(
						"status", utils.BridgeDirectionDisabled).Set(
						"recipient", targetAddress.String()).Set(
						"target_blockchain_id", targetBlockchainId).Set(
						"target_asset", targetAsset.Asset).Where(
						"id", h.Id).Exec()
					if err != nil {
						return Error(err)
					}
				}
			}
		}

		var (
			ok bool

			depositAmount  *big.Int
			adjustedAmount *big.Int

			// iAddress            config.Address
			txHash = h.TxHash

			name   = asset.Name
			symbol = asset.Symbol

			depositDecimals  = asset.Decimals
			withdrawDecimals = targetAsset.Decimals
		)

		depositAmount, ok = big.NewInt(0).SetString(h.Amount, 10)
		if !ok {
			return Error(ErrorCode(errStringToBigInt))
		}

		// check min deposit amount
		minDeposit := big.NewInt(0)
		if direction == config.DirectionA2B {
			if _, ok := minDeposit.SetString(pair.AssetAMinDepositAmount, 10); !ok {
				return ErrorCode(errStringToBigInt)
			}
		} else {
			if _, ok := minDeposit.SetString(pair.AssetBMinDepositAmount, 10); !ok {
				return ErrorCode(errStringToBigInt)
			}
		}
		if depositAmount.Cmp(minDeposit) < 0 {
			log.WithFields(logrus.Fields{
				"id":            h.Id,
				"depositAmount": depositAmount.String(),
				"deposit":       utils.GetAmountTextFromISAACWithDecimals(depositAmount, depositDecimals),
			}).Errorln("value less then min amount")

			_, err = sess.SQL().Update("history").Set(
				"status", utils.BridgeDepositError).Set(
				"recipient", targetAddress.String()).Set(
				"target_blockchain_id", targetBlockchainId).Set(
				"target_asset", targetAsset.Asset).Where(
				"id", h.Id).Exec()
			if err != nil {
				return Error(err)
			}

			continue
		}

		// decimals
		if depositDecimals == withdrawDecimals {
			adjustedAmount = big.NewInt(0).Set(depositAmount)
		} else {
			// withdrawValueActual = depositValueActual / 10^depositDecimals * 10^withdrawDecimals
			adjustedAmount = calculateWithdrawValue(depositAmount, depositDecimals, withdrawDecimals)
		}

		withdrawFee := big.NewInt(0).Set(adjustedAmount)
		if direction == config.DirectionA2B {
			// ok, withdraw on B
			withdrawFee.Mul(withdrawFee, big.NewInt(0).SetUint64(uint64(pair.AssetBWithdrawFeePercent)))
			withdrawFee.Div(withdrawFee, big.NewInt(utils.FeeBase))
			withdrawFeeMin, ok := big.NewInt(0).SetString(pair.AssetBWithdrawFeeMin, 10)
			if !ok {
				return ErrorCode(errStringToBigInt)
			}
			if withdrawFee.Cmp(withdrawFeeMin) < 0 {
				withdrawFee = withdrawFee.Set(withdrawFeeMin)
			}
		} else {
			// ok, withdraw on A
			withdrawFee.Mul(withdrawFee, big.NewInt(0).SetUint64(uint64(pair.AssetAWithdrawFeePercent)))
			withdrawFee.Div(withdrawFee, big.NewInt(utils.FeeBase))
			withdrawFeeMin, ok := big.NewInt(0).SetString(pair.AssetAWithdrawFeeMin, 10)
			if !ok {
				return ErrorCode(errStringToBigInt)
			}
			if withdrawFee.Cmp(withdrawFeeMin) < 0 {
				withdrawFee = withdrawFee.Set(withdrawFeeMin)
			}
		}
		finalAmount := big.NewInt(0).Sub(adjustedAmount, withdrawFee)
		if finalAmount.Cmp(big.NewInt(0)) <= 0 {
			log.WithFields(logrus.Fields{
				"id":                     h.Id,
				"withdrawAdjustedAmount": utils.GetAmountTextFromISAACWithDecimals(adjustedAmount, withdrawDecimals),
				"withdrawFinalA":         utils.GetAmountTextFromISAACWithDecimals(finalAmount, withdrawDecimals),
				"withdrawFee":            utils.GetAmountTextFromISAACWithDecimals(withdrawFee, withdrawDecimals),
			}).Errorln("amount error")

			_, err := sess.SQL().Update("history").Set(
				"status", utils.BridgeExchangeError).Set(
				"adjusted_amount", adjustedAmount.String()).Set(
				"final_amount", finalAmount.String()).Set(
				"fee", withdrawFee.String()).Set(
				"recipient", targetAddress.String()).Set(
				"target_blockchain_id", targetBlockchainId).Set(
				"target_asset", targetAsset.Asset).Where(
				"id", h.Id).Exec()
			if err != nil {
				return Error(err)
			}

			continue
		}

		// BridgeInsufficientBalance
		if h.Status == utils.BridgeInsufficientBalance || h.Status == utils.BridgeInsufficientPermissions {
			if c.notify != nil {
				if c.notifyCache == nil {
					c.notifyCache = cache.New(time.Minute*30, time.Minute*60)
				}
				if _, ok := c.notifyCache.Get(txHash); ok {
					// avoid frequent notifications
					continue
				}

				title := utils.BridgeText[h.Status]
				message := fmt.Sprintf("Blockchain: %s-%s\n", targetBc.Network, targetBc.ChainId)
				message += fmt.Sprintf("Asset: %s(%s)\n", targetAsset.Name, targetAsset.Symbol)
				targetMainAddressName := fmt.Sprintf("%v-%v-%v", targetBc.Network, targetBc.ChainId, utils.WithdrawMainAddress)
				targetMainAddress := mainAddressMap[targetMainAddressName]
				message += fmt.Sprintf("WithdrawMainAddress: %s\n", targetMainAddress)

				targetMainAddressBalance, err := c.getBalance(targetBlockchainId, targetAsset.Asset, targetMainAddress)
				if err != nil {
					message += fmt.Sprintf("Balance: ERROR\n")
				} else {
					message += fmt.Sprintf("Balance: %s %s\n", utils.GetAmountTextFromISAACWithDecimals(targetMainAddressBalance, targetAsset.Decimals), targetAsset.Symbol)
				}

				_ = c.notify.SendMessage(title, message)

				c.notifyCache.Set(txHash, struct{}{}, cache.DefaultExpiration)
			}

			continue
		}

		// handle swap
		var (
			swapAmountUsed = big.NewInt(0)
			swapAmount     = big.NewInt(0)

			nativeAsset *Asset
		)
		if account.EnableSwap && targetAsset.Asset != "" {
			// if target.asset is native, nothing to do
			// only for token
			// native coin MUST in the table assets

			if c.sc != nil && len(c.sc.pairs) > 0 {
				_, ok := c.sc.pairs[pair.ID]
				if ok && c.sc.pairs[pair.ID][asset.ID] {
					// ok, swap

					// get price of source asset
					// 1 USD => source asset amount
					// finalAmount -= source_asset_amount_of_1USD

					// TODO: current force for USDT => NEW
					// if slices.Contains(swap.SymbolListOfUSD, asset.Symbol) {
					if asset.Symbol == "USDT" {
						nativeAsset, err = c.getAsset(targetBlockchainId, "")
						if err != nil {
							return Error(err)
						}
						if nativeAsset.Symbol == newton.Symbol {

							// ok, update finalAmount
							valueInUSD := c.sc.ValueInUSD

							factor := new(big.Int).Exp(big.NewInt(10), big.NewInt(0).SetUint64(uint64(withdrawDecimals)), nil)
							swapAmountUsed = big.NewInt(0).Mul(big.NewInt(0).SetUint64(valueInUSD), factor)

							finalAmount.Sub(finalAmount, swapAmountUsed)

							// ok, native asset
							// get price of target asset
							// 1 USD => target asset amount
							// only NEW?

							// TODO: current only for NEW
							swapAmount, err = swap.GetSwapAmount(c.sc.CMCAPIKey, valueInUSD)
							if err != nil {
								return Error(err)
							}
							fmt.Println("swapAmount: ", swapAmount.String())

							// TODO: force cap
							if swapAmount.Cmp(swap.CapAmountOfNEWValue1USD) > 0 {
								return fmt.Errorf("swap amount of NEW so max")
							}

							log.WithFields(logrus.Fields{
								"id":             h.Id,
								"asset":          asset.Symbol,
								"finalAmount":    utils.GetAmountTextFromISAACWithDecimals(finalAmount, withdrawDecimals),
								"swapAmountUsed": utils.GetAmountTextFromISAACWithDecimals(swapAmountUsed, withdrawDecimals),
								"swapAmount":     utils.GetAmountTextFromISAACWithDecimals(swapAmount, nativeAsset.Decimals),
							}).Infof("swap to native asset")

						}
					}
				}
			}
		}

		if finalAmount.Cmp(adjustedAmount) > 0 {
			return Error(fmt.Errorf("final amount big than adjusted amount"))
		}
		if swapAmountUsed.Cmp(finalAmount) > 0 {
			return Error(fmt.Errorf("swap amount used big than final amount"))
		}

		// check auto confirm amount
		if h.Status == utils.BridgeDeposit {
			title := fmt.Sprintf("Monitor %s Tx Confirm", asset.Name)

			if autoConfirm {
				// check pair AutoConfirmAmount

				autoConfirmAmount := big.NewInt(0)
				if direction == config.DirectionA2B {
					autoConfirmAmount, ok = big.NewInt(0).SetString(pair.AssetAAutoConfirmDepositAmount, 10)
					if !ok {
						return ErrorCode(errStringToBigInt)
					}
				} else {
					autoConfirmAmount, ok = big.NewInt(0).SetString(pair.AssetBAutoConfirmDepositAmount, 10)
					if !ok {
						return Error(ErrorCode(errStringToBigInt))
					}
				}

				if depositAmount.Cmp(autoConfirmAmount) > 0 {
					log.WithFields(logrus.Fields{
						"id":                h.Id,
						"depositAmount":     utils.GetAmountTextFromISAACWithDecimals(depositAmount, depositDecimals),
						"autoConfirmAmount": utils.GetAmountTextFromISAACWithDecimals(autoConfirmAmount, depositDecimals),
						"tx":                txHash,
					}).Warnln("value big then AutoConfirmAmount and needs to be confirmed")

					// send message
					go func() {
						if c.notify != nil {
							if c.notifyCache == nil {
								c.notifyCache = cache.New(time.Minute*30, time.Minute*60)
							}
							if _, ok := c.notifyCache.Get(txHash); ok {
								// avoid frequent notifications
								return
							}

							message := fmt.Sprintf("The tx %s about %s needs to be confirmed, "+
								"AutoConfirmAmount is %s %s, "+
								"and the deposit amount is %s %s.",
								txHash, name,
								utils.GetAmountTextFromISAACWithDecimals(autoConfirmAmount, depositDecimals), symbol,
								utils.GetAmountTextFromISAACWithDecimals(depositAmount, depositDecimals), symbol)

							// ignore error
							_ = c.notify.SendMessage(title, message)

							c.notifyCache.Set(txHash, struct{}{}, cache.DefaultExpiration)
						}
					}()

					if h.FinalAmount == "" {
						if !database.Verify(h, c.chainConfigMap[bc.Id].MonitorSignKeyId) {
							return fmt.Errorf("history invalid")
						}

						err = sess.Tx(func(tx db.Session) error {
							_, err = tx.SQL().Update("history").Set(
								"adjusted_amount", adjustedAmount.String()).Set(
								"final_amount", finalAmount.String()).Set(
								"fee", withdrawFee.String()).Set(
								"recipient", targetAddress.String()).Set(
								"target_blockchain_id", targetBlockchainId).Set(
								"target_asset", targetAsset.Asset).Where("id", h.Id).Exec()
							if err != nil {
								return err
							}
							if swapAmountUsed != nil && swapAmountUsed.Cmp(big.NewInt(0)) > 0 {
								_, err = tx.SQL().Update("history").Set(
									"swap_amount_used", swapAmountUsed.String()).Set(
									"swap_amount", swapAmount.String()).Where("id", h.Id).Exec()
								if err != nil {
									return err
								}
							}
							err = database.UpdateSign(tx, database.TableOfHistory, h.Id, c.CoreSignKeyId)
							if err != nil {
								return err
							}

							return nil
						})
						if err != nil {
							return err
						}

						log.WithFields(logrus.Fields{
							"id": h.Id,
						}).Debugf("update history target info with AutoConfirm enabled but amount too big")
					}

					continue
				} else {
					log.WithFields(logrus.Fields{
						"id":                h.Id,
						"depositAmount":     utils.GetAmountTextFromISAACWithDecimals(depositAmount, depositDecimals),
						"autoConfirmAmount": utils.GetAmountTextFromISAACWithDecimals(autoConfirmAmount, depositDecimals),
						"tx":                txHash,
					}).Info("tx deposit auto confirmed")
				}
			} else {
				// continue and  notify
				log.WithFields(logrus.Fields{
					"id":            h.Id,
					"asset":         asset.Symbol,
					"depositAmount": utils.GetAmountTextFromISAACWithDecimals(depositAmount, depositDecimals),
					"tx":            txHash,
				}).Warnln("tx needs to be confirmed because AutoConfirm is false")

				// send message
				go func() {
					if c.notify != nil {
						if c.notifyCache == nil {
							c.notifyCache = cache.New(time.Minute*30, time.Minute*60)
						}
						if _, ok := c.notifyCache.Get(txHash); ok {
							// avoid frequent notifications
							return
						}

						message := fmt.Sprintf("The tx %s about %s needs to be confirmed "+
							"because AutoConfirm is false, "+
							"and the tx deposit amount is %s %s.",
							txHash, name,
							utils.GetAmountTextFromISAACWithDecimals(depositAmount, depositDecimals), symbol)

						// ignore error
						_ = c.notify.SendMessage(title, message)

						c.notifyCache.Set(txHash, struct{}{}, cache.DefaultExpiration)
					}
				}()

				if h.FinalAmount == "" {
					if !database.Verify(h, c.chainConfigMap[bc.Id].MonitorSignKeyId) {
						return fmt.Errorf("history invalid")
					}

					err = sess.Tx(func(tx db.Session) error {
						_, err = tx.SQL().Update("history").Set(
							"adjusted_amount", adjustedAmount.String()).Set(
							"final_amount", finalAmount.String()).Set(
							"fee", withdrawFee.String()).Set(
							"recipient", targetAddress.String()).Set(
							"target_blockchain_id", targetBlockchainId).Set(
							"target_asset", targetAsset.Asset).Where("id", h.Id).Exec()
						if err != nil {
							return err
						}
						if swapAmountUsed != nil && swapAmountUsed.Cmp(big.NewInt(0)) > 0 {
							_, err = tx.SQL().Update("history").Set(
								"swap_amount_used", swapAmountUsed.String()).Set(
								"swap_amount", swapAmount.String()).Where("id", h.Id).Exec()
							if err != nil {
								return err
							}
						}
						err = database.UpdateSign(tx, database.TableOfHistory, h.Id, c.CoreSignKeyId)
						if err != nil {
							return err
						}

						return nil
					})
					if err != nil {
						return err
					}

					log.WithFields(logrus.Fields{
						"id": h.Id,
					}).Debugf("update history target info with AutoConfirm disabled")
				}

				continue
			}
		} else if h.Status == utils.BridgeDetectedDeposit {
			if h.FinalAmount == "" {
				_, err = sess.SQL().Update("history").Set(
					"adjusted_amount", adjustedAmount.String()).Set(
					"final_amount", finalAmount.String()).Set(
					"fee", withdrawFee.String()).Set(
					"recipient", targetAddress.String()).Set(
					"target_blockchain_id", targetBlockchainId).Set(
					"target_asset", targetAsset.Asset).Where("id", h.Id).Exec()
				if err != nil {
					return err
				}
				if swapAmountUsed != nil && swapAmountUsed.Cmp(big.NewInt(0)) > 0 {
					_, err = sess.SQL().Update("history").Set(
						"swap_amount_used", swapAmountUsed.String()).Set(
						"swap_amount", swapAmount.String()).Where("id", h.Id).Exec()
					if err != nil {
						return err
					}
				}
			}

			continue
		}

		// verify
		if h.Status == utils.BridgeDeposit {
			// only chain monitor
			if !database.Verify(h, c.chainConfigMap[bc.Id].MonitorSignKeyId) && !database.Verify(h, c.CoreSignKeyId) {
				log.WithFields(logrus.Fields{
					"history_id": h.Id,
				}).Errorln("signature verification failed")
				return fmt.Errorf("signature verification failed")
			}
		} else if h.Status == utils.BridgeDepositConfirmed {
			// only used by tools of confirm or manager api approve tx
			if !database.Verify(h, c.ToolsSignKeyId) && !database.Verify(h, c.ManagerAPISignKeyId) {
				log.WithFields(logrus.Fields{
					"history_id": h.Id,
				}).Errorln("signature verification failed")
				return fmt.Errorf("signature verification failed")
			}
		} else {
			log.WithFields(logrus.Fields{
				"history_id": h.Id,
				"status":     utils.BridgeText[h.Status],
			}).Errorln("not support status for verify")
			return fmt.Errorf("not support status for verify")
		}

		// ok, check pass

		// ok, handle withdraw
		// task is just save to db
		// build tx base info: from, to, value, data(type/tick)

		err = sess.Tx(func(tx db.Session) error {
			_, err := tx.SQL().Update("history").Set(
				"status", utils.BridgePendingWithdraw).Set(
				"adjusted_amount", adjustedAmount.String()).Set(
				"final_amount", finalAmount.String()).Set(
				"fee", withdrawFee.String()).Set(
				"recipient", targetAddress.String()).Set(
				"target_blockchain_id", targetBlockchainId).Set(
				"target_asset", targetAsset.Asset).Where("id", h.Id).Exec()
			if err != nil {
				return err
			}

			err = database.SubmitTasks(tx, []*utils.TaskData{{
				ScheduleAt: time.Now(),
				// From:       withdrawMainAddress,
				To:    targetAddress,
				Value: finalAmount,
				// Data:     dataStr,

				TableNo: utils.TableNoNewBridgeHistory,
				TableId: h.Id,

				BlockchainId: targetBlockchainId,
				Asset:        targetAsset.Asset,
				AssetId:      targetAsset.ID,

				ActionType: utils.TasksActionTypeOfNewBridge,
			}}, c.CoreSignKeyId)
			if err != nil {
				return Error(err)
			}

			if swapAmountUsed != nil && swapAmountUsed.Cmp(big.NewInt(0)) > 0 {
				_, err = tx.SQL().Update("history").Set(
					"swap_amount_used", swapAmountUsed.String()).Set(
					"swap_amount", swapAmount.String()).Where("id", h.Id).Exec()
				if err != nil {
					return err
				}

				err = database.SubmitTasks(tx, []*utils.TaskData{{
					ScheduleAt: time.Now(),
					// From:       withdrawMainAddress,
					To:    targetAddress,
					Value: swapAmount,

					TableNo: utils.TableNoNewBridgeHistory,
					TableId: h.Id,

					BlockchainId: nativeAsset.BlockchainId,
					Asset:        nativeAsset.Asset,
					AssetId:      nativeAsset.ID,

					ActionType: utils.TasksActionTypeOfSwap,
				}}, c.CoreSignKeyId)
				if err != nil {
					return Error(err)
				}
			}

			// ok, sign
			err = database.UpdateSign(tx, database.TableOfHistory, h.Id, c.CoreSignKeyId)
			if err != nil {
				return Error(err)
			}

			return nil
		})
		if err != nil {
			return Error(err)
		}

		log.WithFields(logrus.Fields{
			"id":          h.Id,
			"recipient":   targetAddress.String(),
			"valueActual": utils.GetAmountTextFromISAACWithDecimals(adjustedAmount, withdrawDecimals),
			"value":       utils.GetAmountTextFromISAACWithDecimals(finalAmount, withdrawDecimals),
			"withdrawFee": utils.GetAmountTextFromISAACWithDecimals(withdrawFee, withdrawDecimals),
		}).Infoln("submit withdraw task")
	}

	return nil
}

func (c *Core) RunExchangeTasks() error {

	var (
		notifyMessage string
	)

	c.notifyTilePrefix = "Tunnel Core"
	notifyMessage = "Tunnel Core exchange started"

	if c.notify != nil {
		if err := c.notify.SendMessage(c.notifyTilePrefix, notifyMessage); err != nil {
			log.Warnln("Notify send message error: ", err)
		}
	} else {
		log.Warnln("Notify is disable")
	}

	run := func() error {
		var err error

		sess, err := c.openDatabase()
		if err != nil {
			return Error(err)
		}
		defer sess.Close()

		autoConfirm := true
		// load auto confirm
		var v struct {
			Value string `db:"value"`
		}
		err = sess.SQL().Select("value").From(database.TableOfConfig).Where(
			"variable", utils.AutoConfirm.Text()).One(&v)
		if err == db.ErrNoMoreRows {
		} else if err != nil {
			return Error(err)
		}
		if v.Value == utils.AutoConfirmDefault {
			autoConfirm = true
		} else if v.Value == utils.AutoConfirmDisable {
			autoConfirm = false
		}

		err = c.runExchangeTasks(sess, autoConfirm)
		if err != nil {
			return Error(err)
		}

		return nil
	}

	// time.Sleep(time.Second * 2) // just sleep
	ticker := time.NewTicker(time.Second * 10)
	err := run()
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

func calculateWithdrawValue(depositValue *big.Int, depositDecimals, withdrawDecimals uint8) *big.Int {
	withdrawValue := new(big.Int).Set(depositValue)

	powerOfTen := big.NewInt(10)
	if withdrawDecimals > depositDecimals {
		exponent := new(big.Int).SetUint64(uint64(withdrawDecimals - depositDecimals))
		factor := new(big.Int).Exp(powerOfTen, exponent, nil)
		withdrawValue.Mul(withdrawValue, factor)
	} else if depositDecimals > withdrawDecimals {
		exponent := new(big.Int).SetUint64(uint64(depositDecimals - withdrawDecimals))
		factor := new(big.Int).Exp(powerOfTen, exponent, nil)
		withdrawValue.Div(withdrawValue, factor)
	}

	return withdrawValue
}
