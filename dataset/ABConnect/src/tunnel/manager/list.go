package manager

import (
	"context"
	"errors"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/contract/newasset"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins/newton"
)

type BalanceOf func(account common.Address) (*big.Int, error)

func (m *Manager) ListAll() (err error) {
	baseChain := m.Blockchain.BaseChain
	if baseChain == blockchain.UnknownChain {
		return errors.New("basechain error")
	}
	if baseChain != blockchain.Ethereum && baseChain != blockchain.NewChain {
		return errors.New("not support base chain")
	}

	sess, err := m.openDatabase()
	if err != nil {
		return Error(err)
	}
	defer sess.Close()

	var assetsList []database.Asset
	s := sess.SQL().SelectFrom("assets").Where(
		"blockchain_id", m.blockchainId)
	err = s.All(&assetsList)
	if err == db.ErrNoMoreRows {
		return Error(errors.New("run `pair add` to add a pair"))
	} else if err != nil {
		return Error(err)
	}

	tokenList := make(map[common.Address]struct{})
	for _, l := range assetsList {
		if l.Asset == "" {
			tokenList[common.Address{}] = struct{}{}
		} else {
			if !common.IsHexAddress(l.Asset) {
				return ErrorCode(errInvalidAddress)
			}
			tokenList[common.HexToAddress(l.Asset)] = struct{}{}
		}
	}

	rpcurl := m.Blockchain.RpcURL
	client, err := ethclient.Dial(rpcurl)
	if err != nil {
		return Error(err)
	}

	var accounts []database.Account
	err = sess.SQL().Select("internal_address").From("accounts").Where(
		"internal_blockchain_id", m.blockchainId).All(&accounts)
	if err != nil {
		return Error(err)
	}

	for token := range tokenList {
		var (
			balanceOf BalanceOf
			name      string
			symbol    string
			decimals  uint8
		)
		if token == (common.Address{}) {
			balanceOf = func(account common.Address) (*big.Int, error) {
				return client.BalanceAt(context.Background(), account, nil)
			}
			if baseChain == blockchain.Ethereum {
				name = "Ethereum"
				symbol = "ETH"
				decimals = 18
			} else {
				name = newton.Name
				symbol = newton.Symbol
				decimals = 18
			}
			fmt.Printf("Handling %v...\n", name)
		} else {
			baseToken, err := newasset.NewBaseToken(token, client)
			if err != nil {
				return Error(err)
			}
			balanceOf = func(account common.Address) (*big.Int, error) {
				return baseToken.BalanceOf(nil, account)
			}
			name, err = baseToken.Name(nil)
			if err != nil {
				return Error(err)
			}
			symbol, err = baseToken.Symbol(nil)
			if err != nil {
				return Error(err)
			}
			decimals, err = baseToken.Decimals(nil)
			if err != nil {
				return Error(err)
			}
			fmt.Printf("Handling %v(%v)...\n", name, token.String())
		}

		for _, a := range accounts {
			if !common.IsHexAddress(a.InternalAddress) {
				return ErrorCode(errInvalidAddress)
			}
			iAddress := common.HexToAddress(a.InternalAddress)

			balance, err := balanceOf(iAddress)
			if err != nil {
				return Error(err)
			}
			fmt.Println(iAddress.String(), utils.GetAmountTextFromISAACWithDecimals(balance, decimals), symbol)
		}
	}

	return nil
}
