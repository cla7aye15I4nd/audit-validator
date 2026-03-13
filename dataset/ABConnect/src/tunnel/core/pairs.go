package core

import (
	"errors"
	"fmt"
	"strconv"
	"strings"

	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
)

type Pair struct {
	ID                             uint64 `db:"id"`
	AssetAId                       uint64 `db:"asset_a_id"`
	AssetBId                       uint64 `db:"asset_b_id"`
	AssetAMinDepositAmount         string `db:"asset_a_min_deposit_amount"`
	AssetBMinDepositAmount         string `db:"asset_b_min_deposit_amount"`
	AssetAWithdrawFeePercent       uint   `db:"asset_a_withdraw_fee_percent"`
	AssetBWithdrawFeePercent       uint   `db:"asset_b_withdraw_fee_percent"`
	AssetAWithdrawFeeMin           string `db:"asset_a_withdraw_fee_min"`
	AssetBWithdrawFeeMin           string `db:"asset_b_withdraw_fee_min"`
	AssetAAutoConfirmDepositAmount string `db:"asset_a_auto_confirm_deposit_amount"`
	AssetBAutoConfirmDepositAmount string `db:"asset_b_auto_confirm_deposit_amount"`
}

type Asset struct {
	ID           uint64
	BlockchainId uint64
	Asset        string
	Name         string
	Symbol       string
	Decimals     uint8
	Attribute    uint64
	pairs        []uint64 // pairsId
}

func (c *Core) loadAssets() (map[uint64]*Asset, error) {
	sess, err := c.openDatabase()
	if err != nil {
		return nil, Error(err)
	}
	defer sess.Close()

	var assetsList []database.Asset
	err = sess.SQL().Select("id", "blockchain_id", "asset",
		"name", "symbol", "decimals").From("assets").All(&assetsList)
	if errors.Is(err, db.ErrNoMoreRows) {
		return nil, Error(errors.New("run `asset add` to add a pair"))
	} else if err != nil {
		return nil, Error(err)
	}

	id2Asset := make(map[uint64]*Asset)

	for _, l := range assetsList {
		assetId := l.ID
		if assetId == 0 {
			return nil, Error(errors.New("asset id is zero"))
		}

		id2Asset[l.ID] = &Asset{
			ID:           l.ID,
			BlockchainId: l.BlockchainId,
			Asset:        l.Asset,
			Name:         l.Name,
			Symbol:       l.Symbol,
			Decimals:     l.Decimals,
			Attribute:    l.Attribute,
		}
	}

	return id2Asset, nil
}

func (c *Core) loadAssetsAndPairs() (map[uint64]*Asset, map[uint64]*Pair, error) {
	sess, err := c.openDatabase()
	if err != nil {
		return nil, nil, Error(err)
	}
	defer sess.Close()

	var assetsList []database.Asset
	err = sess.SQL().Select("id", "blockchain_id", "asset",
		"name", "symbol", "decimals").From("assets").All(&assetsList)
	if errors.Is(err, db.ErrNoMoreRows) {
		return nil, nil, Error(errors.New("run `asset add` to add a pair"))
	} else if err != nil {
		return nil, nil, Error(err)
	}

	id2Asset := make(map[uint64]*Asset)

	for _, l := range assetsList {
		assetId := l.ID
		if assetId == 0 {
			return nil, nil, Error(errors.New("asset id is zero"))
		}

		id2Asset[l.ID] = &Asset{
			ID:           l.ID,
			BlockchainId: l.BlockchainId,
			Asset:        l.Asset,
			Name:         l.Name,
			Symbol:       l.Symbol,
			Decimals:     l.Decimals,
			Attribute:    l.Attribute,
		}
	}

	var pairsList []database.Pair
	err = sess.SQL().SelectFrom("pairs").All(&pairsList)
	if errors.Is(err, db.ErrNoMoreRows) {
		return nil, nil, Error(errors.New("run `asset add` to add a pair"))
	} else if err != nil {
		return nil, nil, Error(err)
	}

	id2Pair := make(map[uint64]*Pair)

	for _, p := range pairsList {
		pairId := p.Id
		if p.Id == 0 {
			return nil, nil, Error(errors.New("asset id is zero"))
		}

		if !database.Verify(&p, c.ToolsSignKeyId) {
			return nil, nil, Error(errors.New("pair verify failed"))
		}

		id2Pair[pairId] = &Pair{
			ID:                             pairId,
			AssetAId:                       p.AssetAId,
			AssetBId:                       p.AssetBId,
			AssetAMinDepositAmount:         p.AssetAMinDepositAmount,
			AssetBMinDepositAmount:         p.AssetBMinDepositAmount,
			AssetAWithdrawFeePercent:       p.AssetAWithdrawFeePercent,
			AssetBWithdrawFeePercent:       p.AssetBWithdrawFeePercent,
			AssetAWithdrawFeeMin:           p.AssetAWithdrawFeeMin,
			AssetBWithdrawFeeMin:           p.AssetBWithdrawFeeMin,
			AssetAAutoConfirmDepositAmount: p.AssetAAutoConfirmDepositAmount,
			AssetBAutoConfirmDepositAmount: p.AssetBAutoConfirmDepositAmount,
		}
	}

	return id2Asset, id2Pair, nil
}

func (c *Core) getAssetId(blockchainId uint64, asset string) (uint64, error) {
	id2Asset, err := c.loadAssets()
	if err != nil {
		return 0, err
	}

	for id, a := range id2Asset {
		if a == nil {
			return 0, fmt.Errorf("load id %d nil", id)
		}
		if a.BlockchainId == blockchainId && a.Asset == asset {
			return id, nil
		}
	}

	return 0, nil
}

func (c *Core) getAsset(blockchainId uint64, asset string) (*Asset, error) {
	id2Asset, err := c.loadAssets()
	if err != nil {
		return nil, err
	}

	for id, a := range id2Asset {
		if a == nil {
			return nil, fmt.Errorf("load id %d nil", id)
		}
		if a.BlockchainId == blockchainId && a.Asset == asset {
			return a, nil
		}
	}

	return nil, fmt.Errorf("no such asset")
}

func (c *Core) getPairAndDestAsset(assetAId uint64, assetBBlockchainId uint64) (*Pair, *Asset, error) {

	id2Asset, id2Pair, err := c.loadAssetsAndPairs()
	if err != nil {
		return nil, nil, err
	}

	for id, p := range id2Pair {
		if p == nil {
			return nil, nil, fmt.Errorf("load id %d nil", id)
		}
		if p.AssetAId == assetAId && id2Asset[p.AssetBId].BlockchainId == assetBBlockchainId {
			return p, id2Asset[p.AssetBId], nil
		}
		if p.AssetBId == assetAId && id2Asset[p.AssetAId].BlockchainId == assetBBlockchainId {
			return p, id2Asset[p.AssetAId], nil
		}
	}

	return nil, nil, fmt.Errorf("no such pair")
}

func (c *Core) SetDisabledPairs(disabledPairs string) error {
	if disabledPairs == "" {
		return fmt.Errorf("swap enabled but pairs is zero")
	}

	pairsStrList := strings.Split(disabledPairs, ",")
	if len(pairsStrList) == 0 {
		return fmt.Errorf("swap enabled but pairs split len is zero")
	}

	c.disabledPairs = make(map[uint64]map[uint64]bool)

	pairsMapConfig := make(map[uint64]map[uint64]uint64)
	disabledWholePairs := make(map[uint64]bool)
	for _, p := range pairsStrList {
		items := strings.Split(p, ":")
		if len(items) < 1 {
			return fmt.Errorf("disabled pairs parse len zero")
		}
		pairId, err := strconv.ParseUint(items[0], 10, 64)
		if err != nil {
			return err
		}
		if len(items) == 1 {
			disabledWholePairs[pairId] = true
			continue
		}
		if len(items) != 3 {
			return fmt.Errorf("disabled pairs parse len error: need 3 but got %v", len(items))
		}
		assetFrom, err := strconv.ParseUint(items[1], 10, 64)
		if err != nil {
			return err
		}
		assetTo, err := strconv.ParseUint(items[2], 10, 64)
		if err != nil {
			return err
		}
		if pairsMapConfig[pairId] == nil {
			pairsMapConfig[pairId] = make(map[uint64]uint64)
		}
		pairsMapConfig[pairId][assetFrom] = assetTo

		if c.disabledPairs[pairId] == nil {
			c.disabledPairs[pairId] = make(map[uint64]bool)
		}
		c.disabledPairs[pairId][assetFrom] = true
	}

	// ok, check from db
	sess, err := c.openDatabase()
	if err != nil {
		return Error(err)
	}
	defer sess.Close()

	var pairsList []*database.PairDetail
	err = sess.SQL().Select("p.*",
		"a1.asset AS asset_a_asset",
		"a1.name AS asset_a_name",
		"a1.symbol AS asset_a_symbol",
		"a1.decimals AS asset_a_decimals",
		"a1.asset_type AS asset_a_asset_type",
		"b1.id AS asset_a_blockchain_id",
		"b1.network AS asset_a_network",
		"b1.chain_id AS asset_a_chain_id",
		"b1.base_chain AS asset_a_base_chain",
		"a2.asset AS asset_b_asset",
		"a2.name AS asset_b_name",
		"a2.symbol AS asset_b_symbol",
		"a2.decimals AS asset_b_decimals",
		"a2.asset_type AS asset_b_asset_type",
		"b2.id AS asset_b_blockchain_id",
		"b2.network AS asset_b_network",
		"b2.chain_id AS asset_b_chain_id",
		"b2.base_chain AS asset_b_base_chain").From("pairs p").
		LeftJoin("assets a1").On("p.asset_a_id = a1.id").
		LeftJoin("blockchains b1").On("a1.blockchain_id = b1.id").
		LeftJoin("assets a2").On("p.asset_b_id = a2.id").
		LeftJoin("blockchains b2").On("a2.blockchain_id = b2.id").All(&pairsList)
	if errors.Is(err, db.ErrNoMoreRows) {
		return Error(errors.New("run `asset add` to add a pair"))
	} else if err != nil {
		return Error(err)
	}

	id2Pair := make(map[uint64]*database.PairDetail)
	for _, p := range pairsList {
		pairId := p.Id
		if p.Id == 0 {
			return Error(errors.New("pair id is zero"))
		}

		id2Pair[pairId] = p

		if disabledWholePairs[p.Id] {
			if pairsMapConfig[pairId] == nil {
				pairsMapConfig[pairId] = make(map[uint64]uint64)
			}
			pairsMapConfig[pairId][p.AssetAId] = p.AssetBId
			pairsMapConfig[pairId][p.AssetBId] = p.AssetAId

			if c.disabledPairs[pairId] == nil {
				c.disabledPairs[pairId] = make(map[uint64]bool)
			}
			c.disabledPairs[pairId][p.AssetAId] = true
			c.disabledPairs[pairId][p.AssetBId] = true
		}
	}

	for p, assets := range pairsMapConfig {
		pair, ok := id2Pair[p]
		if !ok {
			return fmt.Errorf("unknow pair id: %v", p)
		}
		for assetFromId, assetToId := range assets {
			if !((pair.AssetAId == assetFromId && pair.AssetBId == assetToId) || (pair.AssetAId == assetToId && pair.AssetBId == assetFromId)) {
				return fmt.Errorf("pair and asset not match: %v:%v:%v", p, assetFromId, assetToId)
			}

			// ok, log
			if pair.AssetAId == assetFromId && pair.AssetBId == assetToId {
				if c.disabledPairs[pair.Id] == nil {
					continue
				}
				if !c.disabledPairs[pair.Id][pair.AssetAId] {
					continue
				}

				log.Printf("Pair(%d) from asset(%s-%s-%s-%s) to asset(%s-%s-%s-%s) disabled.",
					p, pair.AssetANetwork, pair.AssetAChainId, pair.AssetAName, pair.AssetASymbol,
					pair.AssetBNetwork, pair.AssetBChainId, pair.AssetBName, pair.AssetBSymbol)

			} else if pair.AssetAId == assetToId && pair.AssetBId == assetFromId {
				if c.disabledPairs[pair.Id] == nil {
					continue
				}
				if !c.disabledPairs[pair.Id][pair.AssetBId] {
					continue
				}

				log.Printf("Pair(%d) from asset(%s-%s-%s-%s) to asset(%s-%s-%s-%s) disabled.",
					p, pair.AssetBNetwork, pair.AssetBChainId, pair.AssetBName, pair.AssetBSymbol,
					pair.AssetANetwork, pair.AssetAChainId, pair.AssetAName, pair.AssetASymbol)
			}
		}
	}

	return nil
}
