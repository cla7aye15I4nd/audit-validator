package api

import (
	"context"
	"errors"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/grpc-ecosystem/grpc-gateway/v2/runtime"
	"github.com/shopspring/decimal"
	"github.com/sirupsen/logrus"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/proto/chainapi"
	pb "gitlab.weinvent.org/yangchenzhong/tunnel/proto/tunnelapi"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

type Manager struct {
	*Tunnel

	pb.UnimplementedManagerAPIServer

	chainClients map[uint64]chainapi.ChainAPIClient
}

func NewManager(cb *config.Bridge, db *config.ConnectionURL) *Manager {
	return &Manager{Tunnel: &Tunnel{APIConfig: cb.Router, DB: db, cb: cb, isManager: true}}
}

// RunAPIServer ListenAndServer listen and server
func (m *Manager) RunAPIServer() error {
	if log == nil {
		log = logrus.New()
		log.SetOutput(os.Stdout)
	}

	log.Printf("Listening at %s:%v...", m.HostNetwork, m.ManagerHost)

	lis, err := net.Listen(m.HostNetwork, m.ManagerHost)
	if err != nil {
		return err
	}

	opts := []grpc.ServerOption{
		grpc.UnaryInterceptor(logRequest),
	}

	s := grpc.NewServer(opts...)

	pb.RegisterTunnelAPIServer(s, m)
	pb.RegisterManagerAPIServer(s, m)

	reflection.Register(s)

	if err := s.Serve(lis); err != nil {
		return err
	}

	return nil
}

// RunHttpAPIServer listen http and server
func (m *Manager) RunHttpAPIServer() error {
	if log == nil {
		log = logrus.New()
		log.SetOutput(os.Stdout)
	}

	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	mux := runtime.NewServeMux()
	opts := []grpc.DialOption{grpc.WithInsecure()}

	if err := pb.RegisterTunnelAPIHandlerFromEndpoint(context.Background(), mux, m.ManagerHost, opts); err != nil {
		return err
	}
	if err := pb.RegisterManagerAPIHandlerFromEndpoint(context.Background(), mux, m.ManagerHost, opts); err != nil {
		return err
	}

	log.Printf("Http listening at %v and gRPC server is %v...", m.ManagerHttpHost, m.ManagerHost)
	if err := http.ListenAndServe(m.ManagerHttpHost, allowCORS(mux)); err != nil {
		return err
	}

	return nil
}

// ---------------------------API-----------------------------------------

// SystemInfo get system info
func (m *Manager) SystemInfo(ctx context.Context, in *pb.InfoRequest) (
	reply *pb.InfoReply, err error) {

	onlySystemConfig := in.OnlySystemConfig

	sess, err := m.openDatabase()
	if err != nil {
		log.Errorln(Error(err))
		return nil, Error(err)
	}
	defer sess.Close()

	var vList []struct {
		Variable string `db:"variable"`
		Value    string `db:"value"`
	}
	err = sess.SQL().Select("variable", "value").From(database.TableOfConfig).All(&vList)
	if errors.Is(err, db.ErrNoMoreRows) {
		return &pb.InfoReply{
			Status: "ok",
		}, nil
	} else if err != nil {
		fmt.Println(err)
		return
	}

	configs := make([]*pb.Config, 0)
	defaultConfigs := utils.GetSystemConfigDefaultText()
	for _, v := range vList {
		if onlySystemConfig && !strings.HasPrefix(v.Variable, utils.SystemConfigPrefix) {
			continue
		}

		configs = append(configs, &pb.Config{
			Key:   v.Variable,
			Value: v.Value,
		})

		if _, ok := defaultConfigs[utils.SystemConfigUnmarshal(v.Variable)]; ok {
			delete(defaultConfigs, utils.SystemConfigUnmarshal(v.Variable))
		}
	}

	for variable, value := range defaultConfigs {
		configs = append(configs, &pb.Config{
			Key:   variable.Text(),
			Value: fmt.Sprintf("%v", value),
		})
	}

	return &pb.InfoReply{
		Status:  "ok",
		Configs: configs,
	}, nil

}

// SetConfig set config key and value
func (m *Manager) SetConfig(ctx context.Context, in *pb.SetConfigRequest) (*pb.SetConfigReply, error) {
	return nil, fmt.Errorf("Forbidden")

	key := in.Key
	value := in.Value
	if key == "" || value == "" {
		return nil, errors.New("key or value is empty")
	}

	sess, err := m.openDatabase()
	if err != nil {
		log.Errorln(Error(err))
		return nil, Error(err)
	}
	defer sess.Close()

	var v struct {
		Variable string `db:"variable"`
		Value    string `db:"value"`
	}
	err = sess.SQL().Select("variable", "value").From(database.TableOfConfig).Where(
		"variable", key).One(&v)
	if errors.Is(err, db.ErrNoMoreRows) {
	} else if err != nil {
		fmt.Println(err)
		return &pb.SetConfigReply{
			Key:    key,
			Value:  value,
			Status: utils.ManagerSetFailure,
		}, nil
	}

	sc := utils.SystemConfigUnmarshal(key)
	switch sc {
	case utils.AutoConfirm:
		if value != utils.AutoConfirmDefault && value != utils.AutoConfirmDisable {
			return &pb.SetConfigReply{
				Key:    key,
				Value:  value,
				Status: utils.ManagerSetFailure,
			}, nil
		}
	default:
		return &pb.SetConfigReply{
			Key:    key,
			Value:  value,
			Status: utils.ManagerSetFailure,
		}, nil
	}

	sql := fmt.Sprintf(`INSERT INTO %s (variable, value) VALUES("%s", "%s") 
				ON DUPLICATE KEY UPDATE value = "%s"`,
		database.TableOfConfig, sc.Text(), value, value)
	_, err = sess.SQL().Exec(sql)
	if err != nil {
		log.Errorln(err)

		return &pb.SetConfigReply{
			Key:    key,
			Value:  value,
			Status: utils.ManagerSetFailure,
		}, nil
	}

	return &pb.SetConfigReply{
		Key:    key,
		Value:  value,
		Status: utils.ManagerSetSuccess,
	}, nil
}

// UpdatePair update pair info
func (m *Manager) UpdatePair(ctx context.Context, in *pb.UpdatePairRequest) (reply *pb.UpdatePairReply, err error) {
	return nil, fmt.Errorf("Forbidden")

	pairId := in.PairId
	assetAId := in.AssetAId
	assetBId := in.AssetBId
	if pairId == 0 || assetAId == 0 || assetBId == 0 {
		return nil, fmt.Errorf("id is zero")
	}

	sess, err := m.openDatabase()
	if err != nil {
		log.Errorln(Error(err))
		return nil, Error(err)
	}
	defer sess.Close()

	exists, err := sess.Collection("pairs").Find(db.Cond{
		"id":         pairId,
		"asset_a_id": assetAId,
		"asset_b_id": assetBId,
	}).Exists()
	if err != nil {
		return nil, fmt.Errorf("get pair error")
	}
	if !exists {
		return nil, fmt.Errorf("no such pair")
	}

	var pair database.PairDetail
	s := sess.SQL().Select("p.*",
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
		LeftJoin("blockchains b2").On("a2.blockchain_id = b2.id").Where(
		"p.id", pairId).And(
		"asset_a_id", assetAId).And(
		"asset_b_id", assetBId)
	err = s.One(&pair)
	if errors.Is(err, db.ErrNoMoreRows) {
		return nil, fmt.Errorf("no such pair's detail")
	} else if err != nil {
		return nil, Error(err)
	}

	c := db.Cond{}

	// min deposit amount
	if in.A2BMinDepositAmount != "" {
		aMinDepositAmount, err := utils.GetAmountISAACFromTextWithDecimals(in.A2BMinDepositAmount, pair.AssetADecimals)
		if err != nil {
			return nil, fmt.Errorf("A2BMinDepositAmount error")
		}
		c["asset_a_min_deposit_amount"] = aMinDepositAmount.String()
	}
	if in.B2AMinDepositAmount != "" {
		bMinDepositAmount, err := utils.GetAmountISAACFromTextWithDecimals(in.B2AMinDepositAmount, pair.AssetBDecimals)
		if err != nil {
			return nil, fmt.Errorf("B2AMinDepositAmount error")
		}
		c["asset_b_min_deposit_amount"] = bMinDepositAmount.String()
	}

	// fee percent
	if in.B2AFeePercent != "" {
		aFeePercentDecimal, err := decimal.NewFromString(in.B2AFeePercent)
		if err != nil {
			err = fmt.Errorf("B2AFeePercent error")
			log.Errorln(Error(err))
			return nil, Error(err)
		}
		aFeePercentDecimal = aFeePercentDecimal.Mul(decimal.NewFromInt(utils.FeeBase))
		aFeePercent := aFeePercentDecimal.IntPart()
		if aFeePercent < 0 {
			err = fmt.Errorf("B2AFeePercent less than zero")
			log.Errorln(Error(err))
			return nil, Error(err)
		}
		if aFeePercent > utils.FeeBase {
			err = fmt.Errorf("B2AFeePercent bigger than FeeBase")
			log.Errorln(Error(err))
			return nil, Error(err)
		}
		c["asset_a_withdraw_fee_percent"] = aFeePercent
	}
	if in.A2BFeePercent != "" {
		bFeePercentDecimal, err := decimal.NewFromString(in.A2BFeePercent)
		if err != nil {
			err = fmt.Errorf("A2BFeePercent error")
			log.Errorln(Error(err))
			return nil, Error(err)
		}
		bFeePercentDecimal = bFeePercentDecimal.Mul(decimal.NewFromInt(utils.FeeBase))
		bFeePercent := bFeePercentDecimal.IntPart()
		if bFeePercent < 0 {
			err = fmt.Errorf("A2BFeePercent less than zero")
			log.Errorln(Error(err))
			return nil, Error(err)
		}
		if bFeePercent > utils.FeeBase {
			err = fmt.Errorf("A2BFeePercent bigger than FeeBase")
			log.Errorln(Error(err))
			return nil, Error(err)
		}
		c["asset_b_withdraw_fee_percent"] = bFeePercent
	}

	// fee min base
	if in.B2AFeeMinAmount != "" {
		aWithdrawFeeMin, err := utils.GetAmountISAACFromTextWithDecimals(in.B2AFeeMinAmount, pair.AssetADecimals)
		if err != nil {
			log.Errorln(err)
			return nil, fmt.Errorf("B2AFeeMinAmount error")
		}
		c["asset_a_withdraw_fee_min"] = aWithdrawFeeMin.String()
	}
	if in.A2BFeeMinAmount != "" {
		bWithdrawFeeMin, err := utils.GetAmountISAACFromTextWithDecimals(in.A2BFeeMinAmount, pair.AssetBDecimals)
		if err != nil {
			log.Errorln(err)
			return nil, fmt.Errorf("A2BFeeMinAmount error")
		}
		c["asset_b_withdraw_fee_min"] = bWithdrawFeeMin.String()
	}

	if in.A2BAutoConfirmDepositAmount != "" {
		aAutoConfirmDepositAmount, err := utils.GetAmountISAACFromTextWithDecimals(in.A2BAutoConfirmDepositAmount, pair.AssetADecimals)
		if err != nil {
			log.Errorln(err)
			return nil, fmt.Errorf("A2BAutoConfirmDepositAmount error")
		}
		c["asset_a_auto_confirm_deposit_amount"] = aAutoConfirmDepositAmount.String()
	}
	if in.B2AAutoConfirmDepositAmount != "" {
		bAutoConfirmDepositAmount, err := utils.GetAmountISAACFromTextWithDecimals(in.B2AAutoConfirmDepositAmount, pair.AssetBDecimals)
		if err != nil {
			return nil, fmt.Errorf("B2AAutoConfirmDepositAmount error")
		}
		c["asset_b_auto_confirm_deposit_amount"] = bAutoConfirmDepositAmount.String()
	}

	if c.Empty() {
		return &pb.UpdatePairReply{
			PairId:        pairId,
			AssetAId:      assetAId,
			AssetBId:      assetBId,
			Status:        utils.ManagerSetSuccess,
			StatusMessage: "No need to update",
		}, nil
	}

	err = sess.Collection("pairs").Find(db.Cond{
		"id":         pairId,
		"asset_a_id": assetAId,
		"asset_b_id": assetBId,
	}).Update(c)
	if err != nil {
		log.Println(err)
		return nil, Error(err)
	}

	return &pb.UpdatePairReply{
		PairId:        pairId,
		AssetAId:      assetAId,
		AssetBId:      assetBId,
		Status:        utils.ManagerSetSuccess,
		StatusMessage: "UPDATED",
	}, nil
}

// ApproveTx approve tx
func (m *Manager) ApproveTx(ctx context.Context, in *pb.ApproveTxRequest) (
	reply *pb.ApproveTxReply, err error) {

	// open db
	sess, err := m.openDatabase()
	if err != nil {
		return nil, ErrorCode(errServerError)
	}
	defer sess.Close()

	hash := in.SourceTxHash
	re := regexp.MustCompile(`^(0x)?[a-fA-F0-9]{64}$`)
	if !re.MatchString(hash) {
		err = fmt.Errorf("source tx hash invalid: %v", hash)
		log.Errorln(Error(err))
		return nil, Error(err)
	}

	id := in.HistoryId
	if id == 0 {
		err = fmt.Errorf("history id is zero")
		log.Errorln(Error(err))
		return nil, Error(err)
	}

	var history *database.History
	err = sess.SQL().SelectFrom("history").Where(
		"id", id).And(
		"tx_hash", hash).One(&history)
	if errors.Is(err, db.ErrNoMoreRows) {
		err = fmt.Errorf("not such tx hash")
		log.Errorln(Error(err))
		return nil, Error(err)
	} else if err != nil {
		log.Errorln(Error(err))
		return nil, Error(err)
	}

	if history.Id == 0 {
		err = fmt.Errorf("get history id error")
		log.Errorln(Error(err))
		return nil, Error(err)
	}
	if history.Id != id {
		err = fmt.Errorf("history id error")
		log.Errorln(Error(err))
		return nil, Error(err)
	}
	if history.Status == utils.BridgeDeposit {

	} else if history.Status == utils.BridgeDepositConfirmed {
		err = fmt.Errorf("tx hash been confirmed")
		log.Errorln(Error(err))
		return nil, Error(err)
	} else {
		err = fmt.Errorf("not support status for cmd confirm")
		log.WithFields(logrus.Fields{
			"tx_hash": hash,
			"id":      history.Id,
			"status":  history.Status,
		}).Errorln(err)
		return nil, Error(err)
	}

	// verify
	slug := m.slugs[history.BlockchainId]
	if slug == "" {
		err = fmt.Errorf("block chain id is empty")
		log.WithFields(logrus.Fields{
			"tx_hash": hash,
			"id":      history.Id,
		}).Errorln(err)
		return nil, Error(err)
	}
	bcCfg := m.blockchains[slug]
	if bcCfg == nil {
		err = fmt.Errorf("block chain is empty")
		log.WithFields(logrus.Fields{
			"tx_hash": hash,
			"id":      history.Id,
		}).Errorln(err)
		return nil, Error(err)
	}

	if !database.Verify(history, bcCfg.MonitorSignKeyId) {
		err = fmt.Errorf("invalid history")
		log.WithFields(logrus.Fields{
			"tx_hash": hash,
			"id":      history.Id,
		}).Errorln(err)
		return nil, Error(err)
	}

	err = sess.Tx(func(dbTx db.Session) error {
		_, err = sess.SQL().Update("history").Set(
			"status", utils.BridgeDepositConfirmed).Where(
			"status", utils.BridgeDeposit).And(
			"id", history.Id).Exec()
		if err != nil {
			return Error(err)
		}

		err = database.UpdateSign(dbTx, database.TableOfHistory, history.Id, m.cb.ManagerAPISignKeyId)
		if err != nil {
			return Error(err)
		}

		return nil
	})
	if err != nil {
		log.Errorln(Error(err))
	}

	log.WithFields(logrus.Fields{
		"tx_hash": hash,
		"id":      history.Id,
	}).Info("tx hash confirmed")

	return &pb.ApproveTxReply{
		HistoryId: in.HistoryId,
		Status:    utils.ManagerSetSuccess,
	}, nil
}

func (m *Manager) GetSystemBalance(ctx context.Context, in *pb.SystemBalanceRequest) (
	reply *pb.SystemBalanceReply, err error) {

	// open db
	sess, err := m.openDatabase()
	if err != nil {
		return nil, ErrorCode(errServerError)
	}
	defer sess.Close()

	var (
		pageId   = 0
		pageSize = 10240
	)

	// blockchainId ==> assetId => AssetBalance
	blockchains := make(map[uint64]map[uint64]*utils.AssetBalance)
	bcForBalances := make(map[uint64]map[string]bool)
	now := time.Now().Add(-24 * time.Hour).UTC()
	startOfNow := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)

	for ; ; pageId++ {
		// all from history left join
		var historyList []*database.HistoryDetail
		err = sess.SQL().Select(
			"h.*",
			"p.id AS pair_id",
			"a1.id AS asset_id",
			"a1.name AS asset_name",
			"a1.symbol AS asset_symbol",
			"a1.decimals AS asset_decimals",
			"a1.asset_type AS asset_type",
			"b1.network AS network",
			"b1.chain_id AS chain_id",
			"b1.base_chain AS base_chain",
			"a2.id AS target_asset_id",
			"a2.name AS target_asset_name",
			"a2.symbol AS target_asset_symbol",
			"a2.decimals AS target_asset_decimals",
			"a2.asset_type AS target_asset_type",
			"b2.network AS target_network",
			"b2.chain_id AS target_chain_id",
			"b2.base_chain AS target_base_chain").From("history h").
			LeftJoin("assets a1").On("h.blockchain_id = a1.blockchain_id and h.asset = a1.asset").
			LeftJoin("blockchains b1").On("a1.blockchain_id = b1.id").
			LeftJoin("assets a2").On("h.target_blockchain_id = a2.blockchain_id and h.target_asset = a2.asset").
			LeftJoin("blockchains b2").On("a2.blockchain_id = b2.id").
			LeftJoin("pairs p").On("(p.asset_a_id = a1.id and p.asset_b_id = a2.id) or (p.asset_a_id = a2.id and p.asset_b_id = a1.id)").OrderBy(
			"h.id DESC").Offset(
			pageId * pageSize).Limit(pageSize).All(&historyList)
		if err != nil {
			log.Errorln(err)
			return nil, Error(err)
		}

		if len(historyList) == 0 {
			break
		}

		for _, h := range historyList {
			// deposit
			if blockchains[h.BlockchainId] == nil {
				blockchains[h.BlockchainId] = make(map[uint64]*utils.AssetBalance)
			}
			if blockchains[h.BlockchainId][h.AssetId] == nil {
				blockchains[h.BlockchainId][h.AssetId] = &utils.AssetBalance{
					AssetId:      h.AssetId,
					BlockchainId: h.BlockchainId,
					Asset:        h.Asset,
					Name:         h.AssetName,
					Symbol:       h.AssetSymbol,
					Decimals:     h.AssetDecimals,
					// Attribute:     h.AssetType,
					AssetType: h.AssetType,

					Network:   h.Network,
					ChainId:   h.ChainId,
					BaseChain: h.BaseChain,
					Slug:      m.slugs[h.BlockchainId],

					TotalDeposit:         big.NewInt(0),
					TotalWithdraw:        big.NewInt(0),
					TotalDepositLastDay:  big.NewInt(0),
					TotalWithdrawLastDay: big.NewInt(0),
				}
			}
			amount, ok := big.NewInt(0).SetString(h.Amount, 10)
			if !ok {
				return nil, ErrorCode(errStringToBigInt)
			}
			blockchains[h.BlockchainId][h.AssetId].TotalDeposit.Add(
				blockchains[h.BlockchainId][h.AssetId].TotalDeposit,
				amount)
			if h.BlockTimestamp.After(startOfNow) {
				blockchains[h.BlockchainId][h.AssetId].TotalDepositLastDay.Add(
					blockchains[h.BlockchainId][h.AssetId].TotalDepositLastDay,
					amount)
			}

			if h.TargetAssetId == nil ||
				h.TargetAssetName == nil ||
				h.TargetAssetSymbol == nil ||
				h.TargetAssetDecimals == nil ||
				h.TargetNetwork == nil ||
				h.TargetChainId == nil ||
				h.TargetBaseChain == nil {
				continue
			}
			if blockchains[h.TargetBlockchainId] == nil {
				blockchains[h.TargetBlockchainId] = make(map[uint64]*utils.AssetBalance)
			}
			if blockchains[h.TargetBlockchainId][*h.TargetAssetId] == nil {
				blockchains[h.TargetBlockchainId][*h.TargetAssetId] = &utils.AssetBalance{
					AssetId:      *h.TargetAssetId,
					BlockchainId: h.TargetBlockchainId,
					Asset:        h.TargetAsset,
					Name:         *h.TargetAssetName,
					Symbol:       *h.TargetAssetSymbol,
					Decimals:     *h.TargetAssetDecimals,
					// Attribute:     0,
					AssetType: *h.TargetAssetType,

					Network:   *h.TargetNetwork,
					ChainId:   *h.TargetChainId,
					BaseChain: *h.TargetBaseChain,
					Slug:      m.slugs[h.TargetBlockchainId],

					TotalDeposit:         big.NewInt(0),
					TotalWithdraw:        big.NewInt(0),
					TotalDepositLastDay:  big.NewInt(0),
					TotalWithdrawLastDay: big.NewInt(0),
				}
			}
			finalAmount := big.NewInt(0)
			if h.FinalAmount != "" {
				finalAmount, ok = big.NewInt(0).SetString(h.FinalAmount, 10)
				if !ok {
					return nil, ErrorCode(errStringToBigInt)
				}
			}
			blockchains[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdraw.Add(
				blockchains[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdraw,
				finalAmount)

			// base on deposit block timestamp not target block timestamp
			if h.BlockTimestamp.After(startOfNow) {
				blockchains[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdrawLastDay.Add(
					blockchains[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdrawLastDay,
					finalAmount)
			}

			// blockchains => assets
			// blockchains[h.BlockchainId][h.AssetId]
			if bcForBalances[h.BlockchainId] == nil {
				bcForBalances[h.BlockchainId] = make(map[string]bool)
			}
			bcForBalances[h.BlockchainId][h.Asset] = true
			if bcForBalances[h.TargetBlockchainId] == nil {
				bcForBalances[h.TargetBlockchainId] = make(map[string]bool)
			}
			bcForBalances[h.TargetBlockchainId][h.TargetAsset] = true
		}

		if len(historyList) < pageSize {
			break
		}
	}

	if len(blockchains) == 0 {
		return &pb.SystemBalanceReply{}, nil
	}

	// load configs
	var cfgList []database.Config
	if err := sess.SQL().SelectFrom(database.TableOfConfig).All(&cfgList); err != nil {
		return nil, Error(err)
	}
	cfgMap := make(map[string]interface{})
	for _, cfg := range cfgList {
		if strings.HasSuffix(cfg.Variable, utils.LatestBlockHeight) {
			if number, ok := big.NewInt(0).SetString(cfg.Value, 10); !ok {
				return nil, ErrorCode(errStringToBigInt)
			} else {
				cfgMap[cfg.Variable] = number.Uint64()
			}
		} else {
			cfgMap[cfg.Variable] = cfg.Value
		}
	}

	mainBalances, err := m.getMainBalance(sess, bcForBalances)
	if err != nil {
		return nil, Error(err)
	}

	bhIds := make([]uint64, 0)
	for bcId := range bcForBalances {
		bhIds = append(bhIds, bcId)
	}

	blockHeights, err := m.getBlockHeight(sess, bhIds)
	if err != nil {
		return nil, Error(err)
	}

	blockchainsList := make([]*pb.Balance, 0)
	for i, assetBalance := range blockchains {
		assetBalances := make([]*pb.AssetBalance, 0)
		slug, ok := m.slugs[i]
		if !ok {
			continue
		}
		bc, ok := m.blockchains[slug]
		if !ok {
			continue
		}

		latestBlockHeightOnChain, ok := blockHeights[bc.BlockchainId]
		if !ok {
			return nil, errors.New("GetBlockNumber returned failed")
		}
		LatestBlockHeight, ok := cfgMap[fmt.Sprintf("%s-%s-%s", bc.Network, bc.ChainId, utils.LatestBlockHeight)]
		if !ok {
			return nil, Error(fmt.Errorf("LatestBlockHeight not found in db: %s(%s)", bc.Network, bc.ChainId))
		}

		for _, b := range assetBalance {
			mBalance := big.NewInt(0)
			if mainBalances != nil && mainBalances[b.BlockchainId] != nil {
				mBalance = mainBalances[b.BlockchainId][b.Asset]
				if mBalance == nil {
					mBalance = big.NewInt(0)
				}
			}

			assetBalances = append(assetBalances, &pb.AssetBalance{
				Asset: &pb.Asset{
					Id:        b.AssetId,
					Asset:     b.Asset,
					Name:      b.Name,
					Symbol:    b.Symbol,
					Decimals:  uint32(b.Decimals),
					AssetType: b.AssetType,
					Network:   b.Network,
					ChainId:   b.ChainId,
					BaseChain: b.BaseChain,
					Slug:      b.Slug,
				},
				TotalDeposit:         utils.GetAmountTextFromISAACWithDecimals(b.TotalDeposit, b.Decimals),
				TotalWithdraw:        utils.GetAmountTextFromISAACWithDecimals(b.TotalWithdraw, b.Decimals),
				TotalDepositLastDay:  utils.GetAmountTextFromISAACWithDecimals(b.TotalDepositLastDay, b.Decimals),
				TotalWithdrawLastDay: utils.GetAmountTextFromISAACWithDecimals(b.TotalWithdrawLastDay, b.Decimals),
				Balance:              utils.GetAmountTextFromISAACWithDecimals(mBalance, b.Decimals),
			})
		}

		blockchainsList = append(blockchainsList, &pb.Balance{
			BlockchainId: i,
			Blockchain: &pb.Blockchain{
				Network:   bc.Network,
				ChainId:   bc.ChainId,
				BaseChain: bc.BaseChain.String(),
				Slug:      slug,
			},
			Balances:                 assetBalances,
			LatestBlockHeight:        LatestBlockHeight.(uint64),
			LatestBlockHeightOnChain: latestBlockHeightOnChain,
		})
	}

	return &pb.SystemBalanceReply{
		Blockchains: blockchainsList,
		Pairs:       nil,
	}, nil

}
