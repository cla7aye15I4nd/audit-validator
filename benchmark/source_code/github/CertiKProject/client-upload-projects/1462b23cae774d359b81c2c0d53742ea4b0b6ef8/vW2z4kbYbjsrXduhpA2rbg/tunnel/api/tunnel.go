package api

import (
	"context"
	"errors"
	"fmt"
	"math/big"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/proto/chainapi"
	pb "gitlab.weinvent.org/yangchenzhong/tunnel/proto/tunnelapi"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

var log *logrus.Logger

func init() {
	log = logrus.New()
	log.SetOutput(os.Stdout)
}

type Tunnel struct {
	*config.APIConfig
	cb *config.Bridge
	DB *config.ConnectionURL `json:"Db" "mapstructure":"db"`
	pb.UnimplementedTunnelAPIServer

	blockchains map[string]*config.ChainConfig // Slug ==> Blockchain
	slugs       map[uint64]string              // BlockchainId ==> Slug

	bridges map[uint64]map[uint64]bool // smallBlockchainId => bigBlockchainId => Blockchain

	sc *SwapConfig

	disabledPairs          map[uint64]bool            // pairId => disabled
	disabledPairsDirection map[uint64]map[uint64]bool // pairId => fromAsset => disabled

	isManager bool
}

func New(cb *config.Bridge, db *config.ConnectionURL) *Tunnel {
	return &Tunnel{APIConfig: cb.Router, DB: db, cb: cb}
}

func (t *Tunnel) Init() error {

	sess, err := t.openDatabase()
	if err != nil {
		return err
	}
	defer sess.Close()

	if err := t.InitBlockchains(sess); err != nil {
		return err
	}

	if t.cb.DisabledPairs != "" {
		if err := t.SetDisabledPairs(t.cb.DisabledPairs); err != nil {
			return err
		}
	}
	if t.cb.Swap != nil {
		if err := t.SetSwap(t.cb.Swap); err != nil {
			return err
		}
	}

	if err := t.InitBridges(sess); err != nil {
		return err
	}

	return nil
}

func (t *Tunnel) InitBlockchains(sess db.Session) error {
	if t.blockchains == nil {
		t.blockchains = make(map[string]*config.ChainConfig)
	}
	if t.slugs == nil {
		t.slugs = make(map[uint64]string)
	}

	for i, bc := range t.Blockchains {
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

		if t.blockchains[bc.Slug] != nil {
			return fmt.Errorf("duplicated blockchain name: %v", bc.Slug)
		}
		t.blockchains[bc.Slug] = bc
		t.slugs[bc.BlockchainId] = bc.Slug
	}

	return nil
}

func (t *Tunnel) InitBridges(sess db.Session) error {
	// bridges
	var pairsList []database.PairDetail
	s := sess.SQL().Select("p.*",
		"a1.blockchain_id AS asset_a_blockchain_id",
		"a2.blockchain_id AS asset_b_blockchain_id").From("pairs p").
		LeftJoin("assets a1").On("p.asset_a_id = a1.id").
		LeftJoin("assets a2").On("p.asset_b_id = a2.id")
	err := s.All(&pairsList)
	if errors.Is(err, db.ErrNoMoreRows) {

	} else if err != nil {
		return Error(err)
	}

	t.bridges = make(map[uint64]map[uint64]bool)
	for _, p := range pairsList {
		if t.disabledPairs != nil && t.disabledPairs[p.Id] {
			continue
		}

		if !database.Verify(&p.Pair, t.cb.ToolsSignKeyId) {
			return fmt.Errorf("pair verify failed: %v", p.Id)
		}

		if p.AssetABlockchainId < p.AssetBBlockchainId {
			if t.bridges[p.AssetABlockchainId] == nil {
				t.bridges[p.AssetABlockchainId] = make(map[uint64]bool)
			}
			if t.bridges[p.AssetABlockchainId][p.AssetBBlockchainId] == true {
				continue
			}
			t.bridges[p.AssetABlockchainId][p.AssetBBlockchainId] = true
		} else {
			if t.bridges[p.AssetBBlockchainId] == nil {
				t.bridges[p.AssetBBlockchainId] = make(map[uint64]bool)
			}
			if t.bridges[p.AssetBBlockchainId][p.AssetABlockchainId] == true {
				continue
			}

			t.bridges[p.AssetBBlockchainId][p.AssetABlockchainId] = true
		}
	}

	return nil
}

func GetChainInfo(target string) (*chainapi.ChainInfoReply, error) {
	conn, err := grpc.NewClient(target, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	ec := chainapi.NewChainAPIClient(conn)

	return ec.GetChainInfo(context.Background(), &chainapi.ChainInfoRequest{})
}

func isValidBlockchain(bc *config.ChainConfig) bool {
	return bc != nil && bc.BlockchainId != 0 && bc.Network != "" && bc.ChainId != "" && bc.Slug != ""
}

func (t *Tunnel) isBridges(aBlockchainId, bBlockchainId uint64) bool {
	if aBlockchainId > bBlockchainId {
		aBlockchainId, bBlockchainId = bBlockchainId, aBlockchainId
	}
	if t.bridges[aBlockchainId] == nil {
		return false
	}

	return t.bridges[aBlockchainId][bBlockchainId]
}

// getMainBalance
func (t *Tunnel) getMainBalance(sess db.Session, blockchains map[uint64]map[string]bool) (mainBalances map[uint64]map[string]*big.Int, err error) {
	var cfgList []database.Config
	err = sess.SQL().SelectFrom(database.TableOfConfig).All(&cfgList)
	if err != nil {
		return nil, err
	}

	mainAddresses := make(map[string]string)
	for _, cfg := range cfgList {
		if !strings.HasSuffix(cfg.Variable, utils.WithdrawMainAddress) {
			continue
		}
		mainAddresses[cfg.Variable] = cfg.Value
	}

	if len(blockchains) == 0 || len(mainAddresses) == 0 {
		return nil, fmt.Errorf("no blockchains or main addresses set")
	}

	ctx := context.Background()
	var wg sync.WaitGroup
	var mu sync.Mutex
	errChan := make(chan error, len(blockchains))
	mainBalances = make(map[uint64]map[string]*big.Int) // bcId => asset => balance

	for bcId, assets := range blockchains {
		slug, ok := t.slugs[bcId]
		if !ok {
			continue
		}
		bc, ok := t.blockchains[slug]
		if !ok {
			continue
		}

		wg.Add(1)
		go func(bcCfg *config.ChainConfig, assets map[string]bool) {
			defer wg.Done()

			mA, ok := mainAddresses[fmt.Sprintf("%s-%s-%s", bcCfg.Network, bcCfg.ChainId, utils.WithdrawMainAddress)]
			if !ok {
				errChan <- fmt.Errorf("no such main address: %s(%s)", bcCfg.Network, bcCfg.ChainId)
				return
			}

			conn, err := grpc.NewClient(bcCfg.ChainAPIHost, grpc.WithTransportCredentials(insecure.NewCredentials()))
			if err != nil {
				errChan <- err
				return
			}

			client := chainapi.NewChainAPIClient(conn)

			for asset := range assets {
				resp, err := client.GetBalance(ctx, &chainapi.BalanceRequest{
					Address: mA,
					Asset:   asset,
				})
				if err != nil {
					errChan <- err
					return
				}
				if resp == nil {
					errChan <- errors.New("GetBalance returned nil response")
					return
				}

				balance, ok := big.NewInt(0).SetString(resp.Balance, 10)
				if !ok {
					errChan <- errors.New("GetBalance returned invalid response")
					return
				}

				mu.Lock()
				if mainBalances[bcCfg.BlockchainId] == nil {
					mainBalances[bcCfg.BlockchainId] = make(map[string]*big.Int)
				}
				mainBalances[bcCfg.BlockchainId][asset] = balance
				mu.Unlock()
			}
		}(bc, assets)
	}

	wg.Wait()
	close(errChan)

	if len(errChan) > 0 {
		return nil, errors.New("error fetching balances")
	}

	return mainBalances, nil
}

// getBlockHeight return blockchainId => blockHeight
func (t *Tunnel) getBlockHeight(sess db.Session, blockchains []uint64) (blockHeights map[uint64]uint64, err error) {
	var cfgList []database.Config
	err = sess.SQL().SelectFrom(database.TableOfConfig).All(&cfgList)
	if err != nil {
		return nil, err
	}

	if len(blockchains) == 0 {
		return nil, fmt.Errorf("no blockchains or main addresses set")
	}

	ctx := context.Background()
	var wg sync.WaitGroup
	var mu sync.Mutex
	errChan := make(chan error, len(blockchains))
	blockHeights = make(map[uint64]uint64) // bcId => blockHeight

	for _, bcId := range blockchains {
		slug, ok := t.slugs[bcId]
		if !ok {
			continue
		}
		bc, ok := t.blockchains[slug]
		if !ok {
			continue
		}

		wg.Add(1)
		go func(bcCfg *config.ChainConfig) {
			defer wg.Done()

			conn, err := grpc.NewClient(bcCfg.ChainAPIHost, grpc.WithTransportCredentials(insecure.NewCredentials()))
			if err != nil {
				errChan <- err
				return
			}

			client := chainapi.NewChainAPIClient(conn)

			resp, err := client.GetBlockNumber(ctx, &chainapi.BlockNumberRequest{})

			if err != nil {
				errChan <- err
				return
			}
			if resp == nil {
				errChan <- errors.New("GetBalance returned nil response")
				return
			}

			mu.Lock()
			blockHeights[bcCfg.BlockchainId] = resp.Number
			mu.Unlock()

		}(bc)
	}

	wg.Wait()
	close(errChan)

	if len(errChan) > 0 {
		return nil, errors.New("error fetching balances")
	}

	return blockHeights, nil
}
