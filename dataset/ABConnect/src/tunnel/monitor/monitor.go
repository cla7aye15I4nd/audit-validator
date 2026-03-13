package monitor

import (
	"context"
	"errors"
	"fmt"
	"os"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/patrickmn/go-cache"
	"github.com/sirupsen/logrus"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/notify"
	"gitlab.weinvent.org/yangchenzhong/tunnel/notify/pushover"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

var log *logrus.Logger

func init() {
	log = logrus.New()
	log.SetOutput(os.Stdout)
}

type Monitor struct {
	*config.Bridge
	cc *config.ChainConfig

	// manager database
	adapterName string
	settings    db.ConnectionURL

	asset2Id     map[common.Address]*Asset // ETH: assetAddress ==> Id
	blockchainId uint64

	ignoreBasicCoinDeposit bool

	notify                 notify.Notify
	notifyTilePrefix       string
	autoConfirmNotifyCache *cache.Cache
}

func New(cb *config.Bridge) (*Monitor, error) {

	if cb == nil {
		return nil, Error(errors.New("config is nil"))
	}

	var n notify.Notify
	if cb.EnableNotify {
		n = pushover.New(cb.Pushover.Token, cb.Pushover.Key)
	}

	// inviteRecents, _ := lru.NewARC(2048)
	m := &Monitor{
		Bridge: cb,
		cc:     cb.Blockchain,

		adapterName: cb.DB.Adapter,
		settings:    cb.DB.ConnectionURL,

		notify: n,
	}

	// _, err := m.openDatabase()
	// if err != nil {
	// 	return nil, Error(err)
	// }

	return m, nil
}

func (m *Monitor) InitBlockchain() error {
	if m.cc == nil || m.cc.Network == "" {
		return fmt.Errorf("Blockchain.Network is empty")
	}

	client, err := ethclient.Dial(m.cc.RpcURL)
	if err != nil {
		return err
	}
	chainId, err := client.ChainID(context.Background())
	if err != nil {
		return err
	}
	if m.cc.ChainId != "" && m.cc.ChainId != chainId.String() {
		return fmt.Errorf("Blockchain.ChainId is %s but get chainId %s by Blockchain.RPCURL",
			m.cc.ChainId, chainId.String())
	}
	m.cc.ChainId = chainId.String()

	sess, err := m.openDatabase()
	if err != nil {
		return err
	}

	var bc struct {
		ID uint64 `db:"id"`
	}
	err = sess.SQL().Select("id").From("blockchains").Where(
		db.And(db.Cond{"network": m.cc.Network, "chain_id": m.cc.ChainId})).One(&bc)
	if errors.Is(err, db.ErrNoMoreRows) {
		return fmt.Errorf("no such blockchain")
	} else if err != nil {
		return err
	}

	if bc.ID == 0 {
		return fmt.Errorf("blockchain is zero")
	}

	m.blockchainId = bc.ID

	fmt.Printf("Blockchain: %d(%s-%s)\n", m.blockchainId, m.cc.Network, m.cc.ChainId)

	if m.cc.WithdrawMainAddress == nil || m.cc.WithdrawMainAddress.String() == "" {
		return fmt.Errorf("withdrawMainAddress is empty")
	}
	fmt.Println("WithdrawMainAddress: ", m.cc.WithdrawMainAddress)

	return nil
}
