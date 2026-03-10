package core

import (
	"errors"
	"os"

	"github.com/ethereum/go-ethereum/common"
	cache "github.com/patrickmn/go-cache"
	"github.com/sirupsen/logrus"
	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/notify"
	"gitlab.weinvent.org/yangchenzhong/tunnel/notify/pushover"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

var log *logrus.Logger

func init() {
	log = logrus.New()
	log.SetOutput(os.Stdout)
}

type Core struct {
	*config.Bridge

	// manager database
	adapterName string
	settings    db.ConnectionURL

	asset2Id     map[common.Address]*Asset // ETH: assetAddress ==> Id
	blockchainId uint64

	ignoreBasicCoinDeposit bool

	notify           notify.Notify
	notifyTilePrefix string
	notifyCache      *cache.Cache

	sc *SwapConfig

	disabledPairs map[uint64]map[uint64]bool //  pairId => assetFromId => disabled

	chainConfigMap map[uint64]*config.ChainConfig // bcId => ChainConfig
}

func New(cb *config.Bridge) (*Core, error) {

	if cb == nil {
		return nil, Error(errors.New("config is nil"))
	}

	// inviteRecents, _ := lru.NewARC(2048)
	c := &Core{
		Bridge: cb,

		adapterName: cb.DB.Adapter,
		settings:    cb.DB.ConnectionURL,
	}

	return c, nil
}

func (c *Core) SetLevel(l logrus.Level) {
	log.SetLevel(l)
}

func (c *Core) Init() error {
	if c.EnableNotify {
		c.notify = pushover.New(c.Pushover.Token, c.Pushover.Key)
	}

	if err := c.SetSwap(c.Swap); err != nil {
		return err
	}

	if c.DisabledPairs != "" {
		if err := c.SetDisabledPairs(c.DisabledPairs); err != nil {
			return err
		}
	}

	if c.LogLevel != "" {
		logLevel, err := logrus.ParseLevel(c.LogLevel)
		if err != nil {
			return err
		}
		c.SetLevel(logLevel)
	}

	if err := c.InitBlockchains(c.Router.Blockchains); err != nil {
		return err
	}

	return nil
}

func (c *Core) InitBlockchains(bcConfigs []*config.ChainConfig) error {
	if len(bcConfigs) == 0 {
		return Error(errors.New("blockchains config is empty"))
	}

	// ok, check from db
	sess, err := c.openDatabase()
	if err != nil {
		return Error(err)
	}
	defer sess.Close()

	var bcList []*database.Blockchain
	err = sess.SQL().SelectFrom("blockchains").All(&bcList)
	if err != nil {
		return Error(err)
	}

	if bcList == nil || len(bcList) == 0 {
		return Error(errors.New("no blockchains found"))
	}

	if c.chainConfigMap == nil {
		c.chainConfigMap = make(map[uint64]*config.ChainConfig)
	}

	for _, bcConfig := range bcConfigs {
		if bcConfig == nil {
			return Error(errors.New("config is nil"))
		}

		for _, bc := range bcList {
			if bc.Network == bcConfig.Network && bc.ChainId == bcConfig.ChainId {
				bcConfig.BlockchainId = bc.Id
				c.chainConfigMap[bc.Id] = bcConfig
			}
		}

		if c.chainConfigMap[bcConfig.BlockchainId] == nil {
			return Error(errors.New("blockchain config not found"))
		}
	}

	return nil
}
