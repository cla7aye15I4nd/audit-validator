package manager

import (
	"errors"
	"os"

	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"

	"github.com/sirupsen/logrus"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

var log *logrus.Logger

func init() {
	log = logrus.New()
	log.SetOutput(os.Stdout)

}

type Manager struct {
	*config.Bridge
	blockchainId uint64
}

func New(cb *config.Bridge) (*Manager, error) {
	if cb == nil {
		return nil, Error(errors.New("config bridge is nil"))
	}

	// inviteRecents, _ := lru.NewARC(2048)
	c := &Manager{
		Bridge: cb,
	}

	{
		// chain blockchain info with database
		sess, err := database.OpenDatabase(cb.DB.Adapter, cb.DB.ConnectionURL)
		if err != nil {
			return nil, err
		}
		defer sess.Close()

		var blockchain database.Blockchain
		err = sess.SQL().Select("id", "network", "chain_id", "base_chain").From(
			"blockchains").Where(
			"network", cb.Blockchain.Network).And(
			"chain_id", cb.Blockchain.ChainId).One(&blockchain)
		if errors.Is(err, db.ErrNoMoreRows) {
			return nil, errors.New("no such blockchain")
		} else if err != nil {
			return nil, err
		} else if blockchain.Id == 0 {
			return nil, errors.New("blockchain id is zero")
		}
		c.blockchainId = blockchain.Id
	}

	return c, nil
}
