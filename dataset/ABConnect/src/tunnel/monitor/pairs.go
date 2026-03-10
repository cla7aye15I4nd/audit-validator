package monitor

import (
	"errors"

	"github.com/ethereum/go-ethereum/common"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
)

type Asset struct {
	ID           uint64
	BlockchainId uint64
	Asset        common.Address
	Name         string
	Symbol       string
	Decimals     uint8
	Attribute    uint64
}

func (m *Monitor) loadAssets() error {
	sess, err := m.openDatabase()
	if err != nil {
		return Error(err)
	}
	defer sess.Close()

	var assetsList []database.Asset
	err = sess.SQL().Select("a.*").From("assets a").Where(
		"(EXISTS (SELECT 1 FROM pairs p WHERE p.asset_a_id = a.id) OR EXISTS (SELECT 1 FROM pairs p WHERE p.asset_b_id = a.id))").And(
		"blockchain_id", m.blockchainId).All(&assetsList)
	if err == db.ErrNoMoreRows {
		return Error(errors.New("run `asset add` to add a pair"))
	} else if err != nil {
		return Error(err)
	}

	if m.asset2Id == nil {
		m.asset2Id = make(map[common.Address]*Asset)
	}

	for _, l := range assetsList {
		assetId := l.ID
		if assetId == 0 {
			return Error(errors.New("asset id is zero"))
		}

		var ethToken common.Address
		if l.Asset == "" {
			// native token, use zero address
		} else {
			if !common.IsHexAddress(l.Asset) {
				return ErrorCode(errInvalidAddress)
			}
			ethToken = common.HexToAddress(l.Asset)
		}

		m.asset2Id[ethToken] = &Asset{
			ID:           l.ID,
			BlockchainId: l.BlockchainId,
			Asset:        ethToken,
			Name:         l.Name,
			Symbol:       l.Symbol,
			Decimals:     l.Decimals,
			Attribute:    l.Attribute,
		}
	}

	return nil
}
