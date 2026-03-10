package core

import (
	"context"
	"errors"
	"math/big"

	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/proto/chainapi"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func (c *Core) openDatabase() (db.Session, error) {
	return database.OpenDatabase(c.adapterName, c.settings)
}

func (c *Core) getBalance(blockchainId uint64, asset, address string) (*big.Int, error) {
	bcCfg, ok := c.chainConfigMap[blockchainId]
	if !ok {
		return nil, Error(errors.New("blockchain config not found"))
	}

	conn, err := grpc.NewClient(bcCfg.ChainAPIHost, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, Error(err)
	}

	client := chainapi.NewChainAPIClient(conn)
	reply, err := client.GetBalance(context.Background(), &chainapi.BalanceRequest{
		Address: address,
		Asset:   asset,
	})
	if err != nil {
		return nil, Error(err)
	}

	balance, ok := big.NewInt(0).SetString(reply.Balance, 10)
	if !ok {
		return nil, Error(errors.New("GetBalance returned invalid response"))
	}

	return balance, nil
}
