package monitor

import (
	"context"
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
	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/contract/newasset"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
)

func (m *Monitor) Add(txHash common.Hash, asset, iAddress, sender common.Address, amountOfAsset string) error {

	if iAddress == (common.Address{}) {
		return fmt.Errorf("address is empty")
	}

	if m.asset2Id == nil {
		if err := m.loadAssets(); err != nil {
			return err
		}
	}

	isToken := true
	if asset == (common.Address{}) {
		// ok, is native
		isToken = false
	}
	a := m.asset2Id[asset]
	if a == nil {
		if asset == (common.Address{}) {
			return fmt.Errorf("native asset not exist")
		} else {
			return fmt.Errorf("asset %s not exist", asset.String())
		}
	}

	// amount
	amount, err := utils.GetAmountISAACFromTextWithDecimals(amountOfAsset, a.Decimals)
	if err != nil {
		return err
	}
	if amount.Cmp(big.NewInt(0)) <= 0 {
		return fmt.Errorf("amount is zero")
	}

	sess, err := m.openDatabase()
	if err != nil {
		return Error(err)
	}
	defer sess.Close()

	var account database.Account
	err = sess.SQL().SelectFrom("accounts").Where(
		"internal_blockchain_id", m.blockchainId).And(
		"internal_address", iAddress.String()).One(&account)
	if errors.Is(err, db.ErrNoMoreRows) {
		return fmt.Errorf("account not found")
	} else if err != nil {
		return Error(err)
	}

	if !database.Verify(&account, m.Blockchain.ChainAPISignKeyId) {
		return fmt.Errorf("account verification failed")
	}

	ctx := context.Background()
	client, err := ethclient.Dial(m.cc.RpcURL)
	if err != nil {
		return Error(err)
	}

	txr, err := client.TransactionReceipt(ctx, txHash)
	if err != nil {
		return Error(err)
	}

	if txr.Status != types.ReceiptStatusSuccessful {
		return fmt.Errorf("tx receipt status is failed")
	}

	// check balance
	var txIndex uint
	if isToken {
		// ok, check toke event
		contractAbi, err := abi.JSON(strings.NewReader(newasset.BaseTokenMetaData.ABI))
		if err != nil {
			return Error(err)
		}
		eventValid := false
		for i, l := range txr.Logs {
			if len(l.Topics) < 1 {
				return fmt.Errorf("log topics len error")
			}

			if l.Address != asset {
				continue
			}

			if l.Topics[0] == TopicOfTransfer {
				transferEventFrom := common.HexToAddress(l.Topics[1].Hex())
				transferEventTo := common.HexToAddress(l.Topics[2].Hex())

				unpacked, err := contractAbi.Unpack("Transfer", l.Data)
				if err != nil {
					return Error(err)
				}
				transferEventValue := unpacked[0].(*big.Int)

				if transferEventFrom != sender {
					log.WithFields(logrus.Fields{
						"pairId":    a.ID,
						"hash":      txHash.String(),
						"recipient": iAddress.String(),
						"eventFrom": transferEventFrom.String(),
						"sender":    sender.String(),
					}).Warnln("found event but log from address not match sender")
					continue
				}
				if transferEventTo != iAddress {
					log.WithFields(logrus.Fields{
						"pairId":    a.ID,
						"hash":      txHash.String(),
						"recipient": iAddress.String(),
						"eventTo":   transferEventTo.String(),
					}).Warnln("found event but log eventTo address not match recipient")

					continue
				}
				if transferEventValue.Cmp(amount) != 0 {
					log.WithFields(logrus.Fields{
						"pairId":     a.ID,
						"hash":       txHash.String(),
						"recipient":  iAddress.String(),
						"amount":     amount.String(),
						"eventValue": transferEventValue.String(),
					}).Warnf("found event but log eventValue not match amount")

					continue
				}
				eventValid = true
				txIndex = uint(i)
				break
			} else {
				continue
			}
		}
		if !eventValid {
			return fmt.Errorf("event not valid")
		}

		// check token balance
		erc20, err := newasset.NewBaseToken(asset, client)
		if err != nil {
			return Error(err)
		}
		balance, err := erc20.BalanceOf(nil, iAddress)
		if err != nil {
			return Error(err)
		}
		if balance.Cmp(amount) < 0 {
			return fmt.Errorf("token balance is %s less than the amount %s", balance.String(), amount.String())
		}
	} else {
		// check balance
		balance, err := client.BalanceAt(context.Background(), iAddress, nil)
		if err != nil {
			return Error(err)
		}
		if balance.Cmp(amount) < 0 {
			return fmt.Errorf("balance is %s less than the amount %s",
				balance.String(),
				amount.String())
		}
	}

	header, err := client.HeaderByNumber(ctx, txr.BlockNumber)
	if err != nil {
		return Error(err)
	}
	blockTime := time.Unix(int64(header.Time), 0).UTC()

	// ok, check pass
	fmt.Println("txHash:", txHash.Hex())

	fmt.Println("The info is as follows:")
	fmt.Printf("\tBlockchain(#%d): %s (%s)\n", a.BlockchainId, m.Blockchain.Network, m.Blockchain.ChainId)
	fmt.Printf("\tAsset(#%d): %s (%s)\n", a.ID, a.Name, a.Symbol)
	if asset == (common.Address{}) {
		fmt.Printf("\tAsset Address: -\n")
	} else {
		fmt.Printf("\tAsset Address: %s\n", a.Asset.String())
	}
	fmt.Printf("\tTxHash: %s (%d)\n", txHash.String(), txIndex)
	fmt.Println("\tBlockNumber: ", txr.BlockNumber.String())
	fmt.Println("\tBlockTimestamp: ", blockTime.String())
	fmt.Println("\tInternalAddress: ", iAddress.String())
	fmt.Println("\tSender: ", sender.String())
	fmt.Printf("\tAmount: %s %s\n", utils.GetAmountTextFromISAACWithDecimals(amount, a.Decimals), a.Symbol)

	if !utils.Confirm() {
		return fmt.Errorf("add canceled")
	}

	status := uint(utils.BridgeDeposit)
	assetStr := a.Asset.String()
	if !isToken {
		assetStr = ""
	}
	err = m.saveTxOfSuccess(assetStr, iAddress, sender,
		txHash, txIndex, amount, status, header)
	if err != nil {
		return Error(err)
	}

	return nil
}
