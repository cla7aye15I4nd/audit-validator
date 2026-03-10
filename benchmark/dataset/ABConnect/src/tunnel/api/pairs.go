package api

import (
	"errors"
	"fmt"
	"strconv"
	"strings"

	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/swap"
)

func (t *Tunnel) SetDisabledPairs(disabledPairs string) error {
	if disabledPairs == "" {
		return fmt.Errorf("swap enabled but pairs is zero")
	}

	pairsStrList := strings.Split(disabledPairs, swap.PairsSplitSep)
	if len(pairsStrList) == 0 {
		return fmt.Errorf("swap enabled but pairs split len is zero")
	}

	t.disabledPairs = make(map[uint64]bool)
	t.disabledPairsDirection = make(map[uint64]map[uint64]bool)

	pairsMapConfig := make(map[uint64]map[uint64]uint64)
	for _, p := range pairsStrList {
		items := strings.Split(p, swap.PairAssetSplitSet)
		if len(items) < 1 {
			return fmt.Errorf("disabled pairs parse len error: %v", len(items))
		}
		pairId, err := strconv.ParseUint(items[0], 10, 64)
		if err != nil {
			return err
		}

		if len(items) == 1 {
			// disable pair
			t.disabledPairs[pairId] = true
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

		if t.disabledPairsDirection[pairId] == nil {
			t.disabledPairsDirection[pairId] = make(map[uint64]bool)
		}
		t.disabledPairsDirection[pairId][assetFrom] = true
	}

	// ok, check from db
	sess, err := t.openDatabase()
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
		if t.disabledPairs != nil && t.disabledPairs[p.Id] {
			if pairsMapConfig[pairId] == nil {
				pairsMapConfig[pairId] = make(map[uint64]uint64)
			}
			pairsMapConfig[pairId][p.AssetAId] = p.AssetBId
			pairsMapConfig[pairId][p.AssetBId] = p.AssetAId

			if t.disabledPairsDirection[pairId] == nil {
				t.disabledPairsDirection[pairId] = make(map[uint64]bool)
			}
			t.disabledPairsDirection[pairId][p.AssetAId] = true
			t.disabledPairsDirection[pairId][p.AssetBId] = true

			log.Printf("Pair(%d) between asset (%s-%s-%s-%s) and asset (%s-%s-%s-%s) has been disabled in both directions.",
				p.Id, p.AssetANetwork, p.AssetAChainId, p.AssetAName, p.AssetASymbol,
				p.AssetBNetwork, p.AssetBChainId, p.AssetBName, p.AssetBSymbol)

		}

		id2Pair[pairId] = p
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
				if t.disabledPairsDirection[pair.Id] == nil {
					continue
				}
				if !t.disabledPairsDirection[pair.Id][pair.AssetAId] {
					continue
				}

				log.Printf("Pair(%d) from asset(%s-%s-%s-%s) to asset(%s-%s-%s-%s) disabled.",
					p, pair.AssetANetwork, pair.AssetAChainId, pair.AssetAName, pair.AssetASymbol,
					pair.AssetBNetwork, pair.AssetBChainId, pair.AssetBName, pair.AssetBSymbol)

			} else if pair.AssetAId == assetToId && pair.AssetBId == assetFromId {
				if t.disabledPairsDirection[pair.Id] == nil {
					continue
				}
				if !t.disabledPairsDirection[pair.Id][pair.AssetBId] {
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
