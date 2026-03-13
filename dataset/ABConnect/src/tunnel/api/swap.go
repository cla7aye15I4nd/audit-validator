package api

import (
	"errors"
	"fmt"
	"math/big"
	"strconv"
	"strings"
	"time"

	"github.com/patrickmn/go-cache"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins/newton"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/swap"
)

type SwapConfig struct {
	// Enable bool
	pairs      map[uint64]map[uint64]bool // fromBlockchainId => toBlockchainId => enabled
	ValueInUSD uint64
	CMCAPIKey  string
	priceCache *cache.Cache
}

func (t *Tunnel) swapEnabled() bool {
	if t.sc == nil || t.sc.pairs == nil || len(t.sc.pairs) == 0 {
		return false
	}

	return true
}

func (t *Tunnel) SetSwap(sc *swap.Config) error {
	if sc == nil {
		return nil
	}
	if !sc.Enable {
		return nil
	}

	if sc.Pairs == "" {
		return fmt.Errorf("swap enabled but pairs is zero")
	}

	pairsStrList := strings.Split(sc.Pairs, swap.PairsSplitSep)
	if len(pairsStrList) == 0 {
		return fmt.Errorf("swap enabled but pairs split len is zero")
	}
	pairsMapConfig := make(map[uint64]map[uint64]uint64)
	for _, p := range pairsStrList {
		items := strings.Split(p, swap.PairAssetSplitSet)
		if len(items) != 3 {
			return fmt.Errorf("swap pairs parse len error: need 3 but got %v", len(items))
		}
		pairId, err := strconv.ParseUint(items[0], 10, 64)
		if err != nil {
			return err
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
			continue
		}

		id2Pair[pairId] = p
	}

	// native asset
	var assetsList []*database.Asset
	err = sess.SQL().SelectFrom("assets").All(&assetsList)
	if err != nil {
		return err
	}
	if len(assetsList) == 0 {
		return fmt.Errorf("no asset")
	}

	bcId2NativeAsset := make(map[uint64]*database.Asset)
	for _, a := range assetsList {
		if a.Asset != "" {
			continue
		}
		if bcId2NativeAsset[a.BlockchainId] != nil {
			return fmt.Errorf("duplicate native asset: %v", a.BlockchainId)
		}
		bcId2NativeAsset[a.BlockchainId] = a
	}

	t.sc = &SwapConfig{
		// Enable: sc.Enable,
		ValueInUSD: sc.ValueInUSD,
		CMCAPIKey:  sc.CMCAPIKey,
	}
	t.sc.pairs = make(map[uint64]map[uint64]bool)
	t.sc.priceCache = cache.New(time.Minute*5, time.Minute)

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
				if t.sc.pairs[pair.AssetABlockchainId] == nil {
					t.sc.pairs[pair.AssetABlockchainId] = make(map[uint64]bool)
				}
				t.sc.pairs[pair.AssetABlockchainId][pair.AssetBBlockchainId] = true

				na, ok := bcId2NativeAsset[pair.AssetBBlockchainId]
				if !ok || na == nil {
					return fmt.Errorf("no found natvie asset of blockchain %v:%v:%v", pair.AssetBBlockchainId, pair.AssetBNetwork, pair.AssetBChainId)
				}
				if na.ID == assetToId {
					return fmt.Errorf("config.pairs: asset to id is native")
				}
				log.Printf("Pair(%d) will enable exec swap when bridge from asset(%s-%s-%s-%s) to asset(%s-%s-%s-%s),"+
					" and %v USD value of asset(%s-%s-%s-%s) will be swaped to native asset(%s-%s-%s-%s).",
					p, pair.AssetANetwork, pair.AssetAChainId, pair.AssetAName, pair.AssetASymbol,
					pair.AssetBNetwork, pair.AssetBChainId, pair.AssetBName, pair.AssetBSymbol,
					sc.ValueInUSD, pair.AssetANetwork, pair.AssetAChainId, pair.AssetAName, pair.AssetASymbol,
					pair.AssetBNetwork, pair.AssetBChainId, na.Name, na.Symbol)

			} else if pair.AssetAId == assetToId && pair.AssetBId == assetFromId {
				if t.sc.pairs[pair.AssetBBlockchainId] == nil {
					t.sc.pairs[pair.AssetBBlockchainId] = make(map[uint64]bool)
				}
				t.sc.pairs[pair.AssetBBlockchainId][pair.AssetABlockchainId] = true

				na, ok := bcId2NativeAsset[pair.AssetABlockchainId]
				if !ok || na == nil {
					return fmt.Errorf("no found natvie asset of blockchain %v:%v:%v", pair.AssetABlockchainId, pair.AssetANetwork, pair.AssetAChainId)
				}
				if na.ID == assetToId {
					return fmt.Errorf("config.pairs: asset to id is native")
				}
				log.Printf("Pair(%d) will exec swap when bridge from asset(%s-%s-%s-%s) to asset(%s-%s-%s-%s),"+
					" and %v USD value of asset(%s-%s-%s-%s) will be swaped to native asset(%s-%s-%s-%s).",
					p, pair.AssetBNetwork, pair.AssetBChainId, pair.AssetBName, pair.AssetBSymbol,
					pair.AssetANetwork, pair.AssetAChainId, pair.AssetAName, pair.AssetASymbol,
					sc.ValueInUSD, pair.AssetBNetwork, pair.AssetBChainId, pair.AssetBName, pair.AssetBSymbol,
					pair.AssetANetwork, pair.AssetAChainId, na.Name, na.Symbol)
			}
		}
	}

	return nil
}

func (t *Tunnel) getNEWPrice() (*big.Int, error) {
	if t.sc == nil {
		return nil, fmt.Errorf("swap nil")
	}
	if t.sc.priceCache != nil {
		if sw, ok := t.sc.priceCache.Get(newton.Symbol); ok {
			return sw.(*big.Int), nil
		}
	}

	valueInUSD := t.sc.ValueInUSD
	swapAmount, err := swap.GetSwapAmount(t.sc.CMCAPIKey, valueInUSD)
	if err != nil {
		return nil, Error(err)
	}
	if swapAmount.Cmp(swap.CapAmountOfNEWValue1USD) > 0 {
		return nil, fmt.Errorf("swap amount of NEW so max")
	}

	if t.sc.priceCache != nil {
		t.sc.priceCache.Set(newton.Symbol, swapAmount, 0)
	}

	return swapAmount, nil
}
