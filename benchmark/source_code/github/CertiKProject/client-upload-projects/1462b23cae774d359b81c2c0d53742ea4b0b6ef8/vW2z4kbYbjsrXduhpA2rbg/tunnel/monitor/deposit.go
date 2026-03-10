package monitor

import (
	"bytes"
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/sirupsen/logrus"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/contract/newasset"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
)

func (m *Monitor) RunDepositMonitor(start *big.Int) {
	stop := make(chan struct{})

	if m.blockchainId == 0 {
		log.Errorln("Blockchain Id zero")
		stop <- struct{}{}
		return
	}

	// loading assets list
	if err := m.loadAssets(); err != nil {
		log.Errorln(err)
		stop <- struct{}{}
		return
	}
	for address, asset := range m.asset2Id {
		fmt.Println(asset.ID, address.String(), asset)
	}
	m.asset2Id = nil

	fmt.Println("RunDepositMonitor")
	if start == nil {
		var err error
		start, err = m.loadBlockHeight()
		if err != nil {
			log.Errorln(err)
			return
		}
	}
	m.runChainMonitor(start)

	select {
	case <-stop:
	}
}

func (m *Monitor) runChainMonitor(startBlockNumber *big.Int) {

	log.Printf("Running %v-%v Deposits Monitor...", m.Blockchain.Network, m.Blockchain.ChainId)
	client, err := ethclient.Dial(m.cc.RpcURL)
	if err != nil {
		log.Errorln(err)
		return
	}

	n := int64(m.Blockchain.DelayBlockNumber)
	rateLimitPerMinute := m.Blockchain.RateLimitPerMinute
	var averageIntervalPerRequest time.Duration
	if rateLimitPerMinute > 0 {
		averageIntervalPerRequest = time.Minute / time.Duration(rateLimitPerMinute)
		log.Infof("Monitor rate limit per minute is %v and averate interval per request is %v", rateLimitPerMinute, averageIntervalPerRequest.String())
	}

	ctx := context.Background()

	latestBlockNumber := big.NewInt(0)

	updateLatestBlockNumberFromNewChain := func() error {
		header, err := client.HeaderByNumber(ctx, nil)
		if err != nil {
			return err
		}
		if latestBlockNumber.Cmp(header.Number) < 0 {
			latestBlockNumber.Set(header.Number)
		}
		log.Infof("Latest block number is %d", latestBlockNumber.Uint64())

		return nil
	}

	if err = updateLatestBlockNumberFromNewChain(); err != nil {
		log.Errorln(err)
		return
	}

	currentBlockNumber := big.NewInt(0)
	if startBlockNumber == nil {
		if latestBlockNumber.Cmp(big.NewInt(n)) <= 0 {
			// just in case
			time.Sleep(time.Second * time.Duration(n))
			if err = updateLatestBlockNumberFromNewChain(); err != nil {
				log.Errorln(err)
				return
			}
		}
		currentBlockNumber.Sub(latestBlockNumber, big.NewInt(n))
	} else {
		currentBlockNumber.Set(startBlockNumber)
	}
	log.Infof("Monitor from block number %d and block deploy number is %d", currentBlockNumber.Uint64(), n)

	getBlocks := func() error {
		m.asset2Id = nil // force, reload, just in case asset updated
		header, err := client.HeaderByNumber(ctx, nil)
		if err != nil {
			return err
		}
		latestBlockNumber = header.Number
		startTime := time.Now()
		for big.NewInt(0).Add(currentBlockNumber, big.NewInt(n)).Cmp(latestBlockNumber) <= 0 {
			log.Infof("Try to handle block %s and the latest block number is %s", currentBlockNumber.String(), latestBlockNumber.String())

			if averageIntervalPerRequest > 0 {
				endTime := time.Now()
				if endTime.Sub(startTime) < averageIntervalPerRequest {
					time.Sleep(averageIntervalPerRequest - (endTime.Sub(startTime)))
				}
				startTime = time.Now()
			}
			block, err := client.BlockByNumber(ctx, currentBlockNumber)
			if err != nil {
				return err
			}

			if n != 0 {
				// no need save for detected deposit
				err = m.saveBlockHeight(currentBlockNumber)
				if err != nil {
					return err
				}
			}
			currentBlockNumber.Add(currentBlockNumber, big.NewInt(1))

			log.Infof("Handle block %d with txs is %d", block.NumberU64(), block.Transactions().Len())

			txs := block.Transactions()
			txLen := txs.Len()
			if txLen == 0 {
				continue
			}

			for i := 0; i < txLen; i++ {
				tx := txs[i]
				var from common.Address
				from, err = client.TransactionSender(ctx, tx, block.Hash(), uint(i))
				if err != nil {
					log.Warnln(err)
					continue
				}
				if from == (common.Address{}) {
					log.Warnf("Ignore tx %s from zero", tx.Hash().String())
					continue
				}

				// ignore from of manager address
				if from.String() == m.cc.WithdrawMainAddress.String() {
					log.Infof("Ignore tx %s from WithdrawMainAddress", tx.Hash().String())
					continue
				}

				status := utils.BridgeDeposit
				if n == 0 {
					status = utils.BridgeDetectedDeposit
				}

				if err := m.handleTx(tx, from, block.Header(), uint(status)); err != nil {
					log.WithFields(logrus.Fields{"hash": tx.Hash().String()}).Errorln(err)
					continue
				}
			}
		}

		return nil
	}

	interval, err := getBlockInterval(client)
	if err != nil {
		log.Errorln("get block interval error: ", err)
		return
	}
	if interval == 0 {
		log.Errorln("get block interval is zero")
		return
	}
	log.Infof("Current block interval is %s", interval.String())
	go func() {
		ticker := time.NewTicker(interval)
		for {
			select {
			case <-ticker.C:
				if err = getBlocks(); err != nil {
					log.Errorln(err)
					continue
				}
			}
		}

	}()

	select {}
}

func (m *Monitor) handleTx(tx *types.Transaction, txFrom common.Address, blockHeader *types.Header, status uint) error {
	hash := tx.Hash()
	from := txFrom

	if tx.To() == nil {
		log.Debugf("Ignore tx %s with contract create", hash.String())
		return nil
	}

	to := *tx.To()
	if to == (common.Address{}) {
		log.Debugf("Ignore tx %s with zero to address", hash.String())
		return nil
	}

	// get basic info
	var user common.Address

	if m.asset2Id == nil {
		if err := m.loadAssets(); err != nil {
			return err
		}
	}

	nativeAsset := m.asset2Id[common.Address{}]
	nativeId := uint64(0)
	if nativeAsset != nil {
		nativeId = nativeAsset.ID
	}
	amount := big.NewInt(0)
	asset, isToken := m.asset2Id[to]
	assetId := uint64(0)
	if asset != nil {
		assetId = asset.ID
	}
	if nativeId == 0 && assetId == 0 {
		log.Debugf("Ignore tx %s with unknown token and native coin ignore", hash.String())
		return nil
	}

	contractAbi, err := abi.JSON(strings.NewReader(newasset.BaseTokenABI))
	if err != nil {
		return Error(err)
	}

	if isToken {
		// token address
		// only support NRC20 token, transfer and transferFrom

		if len(tx.Data()) < 4 {
			log.Debugf("Ignore tx %s with token data len error", hash.String())
			return nil
		}
		data := tx.Data()
		sigdata, argdata := data[:4], data[4:]

		if bytes.Compare(sigdata, TransferSigData) == 0 {

			method, err := contractAbi.MethodById(TransferSigData)
			if err != nil {
				return Error(err)
			}
			if method == nil {
				return Error(errors.New("method nil"))
			}
			if len(argdata)%32 != 0 {
				return Error(fmt.Errorf("abi: improperly formatted output: %s - Bytes: [%+v]", hex.EncodeToString(data), data))
			}

			unpacked, err := method.Inputs.Unpack(argdata)
			if err != nil {
				return Error(err)
			}
			if len(unpacked) < 2 {
				return Error(fmt.Errorf("abi: argdata unpack len error"))
			}
			user = unpacked[0].(common.Address)
			amount = unpacked[1].(*big.Int)
		} else if bytes.Compare(sigdata, TransferFromSigData) == 0 {
			method, err := contractAbi.MethodById(TransferFromSigData)
			if err != nil {
				return Error(err)
			}
			if method == nil {
				return Error(errors.New("method nil"))
			}
			if len(argdata)%32 != 0 {
				return Error(fmt.Errorf("abi: improperly formatted output: %s - Bytes: [%+v]", hex.EncodeToString(data), data))
			}

			unpacked, err := method.Inputs.Unpack(argdata)
			if err != nil {
				return Error(err)
			}
			if len(unpacked) < 3 {
				return Error(fmt.Errorf("abi: argdata unpack len error"))
			}

			from = unpacked[0].(common.Address)
			user = unpacked[1].(common.Address)
			amount = unpacked[2].(*big.Int)
		} else {
			log.Debugf("Ignore tx %s with unknown method", hash.String())
			return nil
		}

	} else {
		assetId = nativeId
		asset = nativeAsset
		user = to

		// handle value
		value := tx.Value()
		if value.Cmp(big.NewInt(0)) <= 0 {
			log.Debugf("Ignore tx %s with zero value or unknown contract call", hash.String())
			return nil
		}
		amount = value
	}

	sess, err := m.openDatabase()
	if err != nil {
		return Error(err)
	}
	defer sess.Close()

	var account database.Account
	err = sess.SQL().Select("address").From("accounts").Where(
		"internal_blockchain_id", m.blockchainId).And(
		"internal_address", user.String()).One(&account)
	if errors.Is(err, db.ErrNoMoreRows) {
		log.Debugf("Ignore tx %s with unknown recipient address", hash.String())
		return nil
	} else if err != nil {
		log.Errorf("Ignore tx %s with unknown recipient address error: %v", hash.String(), err)
		return Error(err)
	}

	// ok, check the transaction
	ctx := context.Background()
	client, err := ethclient.Dial(m.cc.RpcURL)
	if err != nil {
		return Error(err)
	}
	txr, err := client.TransactionReceipt(ctx, tx.Hash())
	if err != nil {
		return Error(err)
	}

	if txr.Status != types.ReceiptStatusSuccessful {
		log.Infof("Ignore tx %s with receipt status failed", hash.String())
		return nil
	}

	// check balance
	if isToken {
		// token
		// check event log
		for _, l := range txr.Logs {
			if len(l.Topics) < 1 {
				log.WithFields(logrus.Fields{
					"assetId":   assetId,
					"hash":      hash.String(),
					"recipient": user.String(),
					"amount":    amount.String(),
				}).Warnf("found newbridge %s Deposit tx but log topics len error")

				status = utils.BridgeDepositError
				break
			}

			if l.Topics[0] == TopicOfTransfer {
				unpacked, err := contractAbi.Unpack("Transfer", l.Data)
				if err != nil {
					return Error(err)
				}
				transferEventValue := unpacked[0].(*big.Int)
				// transferEventFrom := common.HexToAddress(l.Topics[1].Hex())
				transferEventTo := common.HexToAddress(l.Topics[2].Hex())

				if transferEventTo != user {
					log.WithFields(logrus.Fields{
						"pairId":    assetId,
						"hash":      hash.String(),
						"recipient": user.String(),
						"amount":    amount.String(),
					}).Warnln("found newbridge Deposit tx but log recipient address not match")

					status = utils.BridgeDepositError
					break
				}
				if transferEventValue.Cmp(amount) != 0 {
					log.WithFields(logrus.Fields{
						"assetId":   assetId,
						"hash":      hash.String(),
						"recipient": user.String(),
						"amount":    amount.String(),
					}).Warnf("found newbridge Deposit tx but log recipient amount not match")

					status = utils.BridgeDepositError
					break
				}
			} else {
				log.WithFields(logrus.Fields{
					"assetId":   assetId,
					"hash":      hash.String(),
					"recipient": user.String(),
					"amount":    amount.String(),
					"topic":     l.Topics[0].Hex(),
				}).Warnf("found newbridge Deposit tx but topic unknown")

				status = utils.BridgeDepositError
				break
			}
		}

		// check token balance
		erc20, err := newasset.NewBaseToken(to, client)
		if err != nil {
			return Error(err)
		}
		balance, err := erc20.BalanceOf(nil, user)
		if err != nil {
			return Error(err)
		}
		if balance.Cmp(amount) < 0 {
			log.WithFields(logrus.Fields{
				"assetId":   assetId,
				"hash":      hash.String(),
				"recipient": user.String(),
				"amount":    amount.String(),
			}).Warnf("found newbridge Deposit tx but token balance error")

			status = utils.BridgeDepositError
		}
	} else {
		// check balance
		balance, err := client.BalanceAt(context.Background(), user, nil)
		if err != nil {
			return Error(err)
		}
		if balance.Cmp(amount) < 0 {
			log.WithFields(logrus.Fields{
				"assetId":   assetId,
				"hash":      hash.String(),
				"recipient": user.String(),
				"amount":    amount.String(),
			}).Warnf("found newbridge Deposit tx but balance error")

			status = utils.BridgeDepositError
		}
	}

	log.WithFields(logrus.Fields{
		"assetId":   assetId,
		"asset":     asset.Name,
		"hash":      hash.String(),
		"recipient": user.String(),
		"amount":    amount.String(),
	}).Infof("found deposit tx")

	// save to db deposits
	// hex address with 0x
	assetStr := asset.Asset.String()
	if !isToken {
		assetStr = ""
	}
	err = m.saveTxOfSuccess(assetStr, user, from,
		hash, 0, amount, status, blockHeader)
	if err != nil {
		return Error(err)
	}

	return nil
}

func (m *Monitor) saveTxOfSuccess(asset string, address, from common.Address, txID common.Hash,
	txIndex uint, amount *big.Int, status uint, blockHeader *types.Header) (err error) {

	if blockHeader == nil {
		return errors.New("header nil")
	}
	blockNumber := blockHeader.Number.Uint64()
	blockTime := time.Unix(int64(blockHeader.Time), 0).UTC().Format(utils.TimeFormat)

	sess, err := database.OpenDatabase(m.adapterName, m.settings)
	if err != nil {
		return err
	}
	defer sess.Close()

	err = sess.Tx(func(tx db.Session) error {
		var history database.History
		err = tx.SQL().SelectFrom("history").Where(
			"tx_hash", txID.Hex()).And(
			"tx_index", txIndex).One(&history)
		if errors.Is(err, db.ErrNoMoreRows) {
			// ok
		} else if err != nil {
			return Error(err)
		} else {
			if history.Status != utils.BridgeDetectedDeposit || status == utils.BridgeDetectedDeposit {
				log.WithFields(logrus.Fields{
					"asset":     asset,
					"hash":      txID.String(),
					"recipient": address.String(),
					"amount":    amount.String(),
				}).Errorf("ignore tunnel %s(%v) deposit tx for duplicate", m.Blockchain.Network, m.Blockchain.ChainId)
				return ErrorCode(errDuplicateSerialNo)
			}

			// ok, we had saved the pending tx, check it again
			if history.Id == 0 {
				log.WithFields(logrus.Fields{
					"asset":     asset,
					"hash":      txID.String(),
					"vout":      txIndex,
					"recipient": address.String(),
					"amount":    amount.String(),
				}).Errorf("ignore tunnel %s(%v) native coin deposit tx for id is zero", m.Blockchain.Network, m.Blockchain.ChainId)
				return ErrorCode(errDuplicateSerialNo)
			}

			if history.Asset != asset || history.Address != address.String() || history.Amount != amount.String() {
				log.WithFields(logrus.Fields{
					"hash":      txID.String(),
					"vout":      txIndex,
					"recipient": address.String(),
					"amount":    amount.String(),
				}).Errorf("ignore tunnel %s(%v) native coin deposit tx for not match", m.Blockchain.Network, m.Blockchain.ChainId)
				return ErrorCode(errDuplicateSerialNo)
			}

			_, err := tx.SQL().Update("history").Set(
				"status", status).Set(
				"block_number", blockNumber).Set(
				"block_timestamp", blockTime).Where("id", history.Id).Exec()
			if err != nil {
				return Error(err)
			}

			if status == utils.BridgeDeposit {
				err = database.UpdateSign(tx, database.TableOfHistory, history.Id, m.Blockchain.MonitorSignKeyId)
				if err != nil {
					return Error(err)
				}
			}

			return nil
		}

		result, err := tx.SQL().InsertInto(database.TableOfHistory).Columns("hash",
			"address", "blockchain_id", "asset", "block_number", "block_timestamp", "tx_hash", "tx_index",
			"sender", "amount", "status").Values(
			utils.GetHistoryHash(m.Blockchain.Network, m.Blockchain.ChainId, txID.String(), txIndex),
			address.String(), m.blockchainId, asset, blockNumber, blockTime, txID.String(), txIndex,
			from.String(), amount.String(), status).Exec()

		if err != nil {
			return Error(err)
		}

		if status == utils.BridgeDeposit {
			lastId, err := result.LastInsertId()
			if err != nil {
				return Error(err)
			}

			err = database.UpdateSign(tx, database.TableOfHistory, uint64(lastId), m.Blockchain.MonitorSignKeyId)
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

func (m *Monitor) SetLevel(l logrus.Level) {
	log.SetLevel(l)
}
