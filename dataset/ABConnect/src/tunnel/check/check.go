package check

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"

	"github.com/patrickmn/go-cache"
	"github.com/sirupsen/logrus"
	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/notify"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

var (
	log *logrus.Logger
)

func init() {
	log = logrus.New()
	log.SetOutput(os.Stdout)
}

type Check struct {
	*config.Bridge

	// manager database
	adapterName string
	settings    db.ConnectionURL

	// asset2Id     map[common.Address]*Asset // ETH: assetAddress ==> Id
	blockchainId uint64

	ignoreBasicCoinDeposit bool

	notify           notify.Notify
	notifyTilePrefix string
	notifyCache      *cache.Cache

	// sc *SwapConfig

	disabledPairs map[uint64]map[uint64]bool //  pairId => assetFromId => disabled

	chainConfigMap map[uint64]*config.ChainConfig // bcId => ChainConfig

	blockchains map[string]*config.ChainConfig // Slug ==> Blockchain
	slugs       map[uint64]string              // BlockchainId ==> Slug
}

func New(cb *config.Bridge) (*Check, error) {

	if cb == nil {
		return nil, errors.New("config is nil")
	}

	// inviteRecents, _ := lru.NewARC(2048)
	c := &Check{
		Bridge: cb,
	}

	return c, nil
}

func (c *Check) RunInstant() error {
	// main address balance
	// latest block

	if err := c.Balance(); err != nil {
		return err
	}

	return nil
}

func (c *Check) RunTimed(duration time.Duration) {
	if err := c.RunInstant(); err != nil {
		log.Error(err)
		return
	}

	if duration == 0 {
		duration = time.Minute * 5
	}
	log.Infoln("Run duration is:", duration.String())

	ticker := time.NewTicker(duration)
	go func() {
		for {
			<-ticker.C
			go func() {
				if err := c.RunInstant(); err != nil {
					log.Error(err)
					return
				}
			}()
		}
	}()

	// Daily run
	// Wait until next UTC+0
	now := time.Now().UTC()
	nextDay := time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, time.UTC)
	timeUntilNextDay := time.Until(nextDay)

	log.Infof("Daily task run now and next is run after%s", timeUntilNextDay.String())
	go c.Daily()
	time.AfterFunc(timeUntilNextDay, func() {
		// First run at UTC+0 00:00
		log.Infof("Daily task run at UTC+0")
		go c.Daily()

		// Start a 24h ticker after first run
		dailyTicker := time.NewTicker(24 * time.Hour)
		for {
			<-dailyTicker.C
			log.Infof("Daily task run at UTC+0")
			c.Daily()
		}
	})

	select {}
}

func (c *Check) InitBlockchains(sess db.Session) error {
	if c.blockchains == nil {
		c.blockchains = make(map[string]*config.ChainConfig)
	}
	if c.slugs == nil {
		c.slugs = make(map[uint64]string)
	}

	for i, bc := range c.Router.Blockchains {
		if bc == nil {
			return fmt.Errorf("blockchain %d is zero", i+1)
		}

		if bc.Network == "" || bc.ChainId == "" {
			return fmt.Errorf("blockchain %d config empty", i+1)
		}

		// check from db
		var dbBC database.Blockchain
		err := sess.SQL().SelectFrom("blockchains").Where(
			"network", bc.Network).And(
			"chain_id", bc.ChainId).One(&dbBC)
		if errors.Is(err, db.ErrNoMoreRows) {
			return fmt.Errorf("blockchain %d not support: (%s:%s)", i+1, bc.Network, bc.ChainId)
		} else if err != nil {
			return fmt.Errorf("blockchain %d error: %v", i+1, err)
		}

		if bc.BlockchainId != 0 && dbBC.Id != bc.BlockchainId {
			return fmt.Errorf("blockchain %d id error, from config is %d but the database is %d", i+1, bc.BlockchainId, dbBC.Id)
		}
		bc.BlockchainId = dbBC.Id

		dbBaseChain := blockchain.Parse(dbBC.BaseChain)
		if dbBaseChain == blockchain.UnknownChain {
			return fmt.Errorf("blockchain from db is unknown")
		}

		if bc.BaseChain == blockchain.UnknownChain {
			bc.BaseChain = dbBaseChain
		} else if bc.BaseChain != dbBaseChain {
			return fmt.Errorf("basechain %d error, from config is %s but the database is %s", i+1, bc.BaseChain.String(), dbBaseChain.String())
		}

		bc.Slug = strings.ToLower(bc.Slug)

		if bc.BlockchainId == 0 || bc.Network == "" || bc.ChainId == "" || bc.Slug == "" {
			return fmt.Errorf("blockchain %d empty: %v", i+1, bc)
		}

		// get inner blockchain type
		chainInfo, err := GetChainInfo(bc.ChainAPIHost)
		if err != nil {
			return err
		}
		if chainInfo == nil {
			return fmt.Errorf("get chainInfo nil")
		}

		signature := chainInfo.Signature
		chainInfo.Signature = nil
		if chainInfo.SignAt <= time.Now().Add(-1*time.Hour).UTC().Unix() {
			return fmt.Errorf("chain info is too old: %v", chainInfo.String())
		}
		hCI, err := database.Hash(chainInfo)
		if err != nil {
			return err
		}

		if !database.VerifyWitKMS(bc.ChainAPISignKeyId, hCI, signature) {
			return fmt.Errorf("chain info is invalid: %v", chainInfo.String())
		}

		iBC := blockchain.Parse(chainInfo.BaseChain)
		if iBC == blockchain.UnknownChain {
			return fmt.Errorf("blockchain from chain api is unknown")
		} else if bc.BaseChain != iBC {
			return fmt.Errorf("%s(%d):basechain not match, from config and db is %s but the chain api is %s", bc.Slug, i+1, bc.BaseChain.String(), iBC.String())
		}
		if bc.BaseChain == blockchain.UnknownChain {
			return fmt.Errorf("UnknownChain %d:%v", i+1, bc.Slug)
		}

		if chainInfo.Network != bc.Network {
			return fmt.Errorf("%s(%d): network not match, config and db is %s but chain api is %s", bc.Slug, i+1, bc.Network, chainInfo.Network)
		}
		if chainInfo.ChainId != bc.ChainId {
			return fmt.Errorf("%s(%d): chainId not match, config and db is %s but chain api is %s", bc.Slug, i+1, bc.ChainId, chainInfo.ChainId)
		}
		if chainInfo.BlockchainId != bc.BlockchainId {
			return fmt.Errorf("%s(%d): blockchain id not match, config and db is %d but chain api is %d", bc.Slug, i+1, bc.BlockchainId, chainInfo.BlockchainId)
		}

		if c.blockchains[bc.Slug] != nil {
			return fmt.Errorf("duplicated blockchain name: %v", bc.Slug)
		}
		c.blockchains[bc.Slug] = bc
		c.slugs[bc.BlockchainId] = bc.Slug
	}

	return nil
}
