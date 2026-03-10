package api

import (
	"context"
	"errors"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"os"
	"strings"

	dbtcutil "github.com/dogecoinw/doged/btcutil"
	dchaincfg "github.com/dogecoinw/doged/chaincfg"
	"github.com/ethereum/go-ethereum/common"
	"github.com/go-sql-driver/mysql"
	"github.com/grpc-ecosystem/grpc-gateway/v2/runtime"
	"github.com/sirupsen/logrus"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/proto/chainapi"
	pb "gitlab.weinvent.org/yangchenzhong/tunnel/proto/tunnelapi"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins/dogecoin"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins/newton"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins/tron"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/reflection"
)

func logRequest(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
	if info != nil {
		log.WithField("method", info.FullMethod).Info(req)
	}

	// Continue execution of handler after ensuring a valid token.
	return handler(ctx, req)
}

// ListenAndServer listen and server
func (t *Tunnel) RunAPIServer() error {
	if log == nil {
		log = logrus.New()
		log.SetOutput(os.Stdout)
	}

	log.Printf("Listening at %s:%v...", t.HostNetwork, t.Host)

	lis, err := net.Listen(t.HostNetwork, t.Host)
	if err != nil {
		return err
	}

	opts := []grpc.ServerOption{
		grpc.UnaryInterceptor(logRequest),
	}

	s := grpc.NewServer(opts...)

	pb.RegisterTunnelAPIServer(s, t)

	reflection.Register(s)

	if err := s.Serve(lis); err != nil {
		return err
	}

	return nil
}

// RunHttpAPIServer listen http and server
func (t *Tunnel) RunHttpAPIServer() error {
	if log == nil {
		log = logrus.New()
		log.SetOutput(os.Stdout)
	}

	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	mux := runtime.NewServeMux()
	opts := []grpc.DialOption{grpc.WithInsecure()}
	if err := pb.RegisterTunnelAPIHandlerFromEndpoint(context.Background(), mux, t.Host, opts); err != nil {
		return err
	}

	log.Printf("Http listening at %v and gRPC server is %v...", t.HttpHost, t.Host)
	if err := http.ListenAndServe(t.HttpHost, allowCORS(mux)); err != nil {
		return err
	}

	return nil
}

// allowCORS allows Cross Origin Resoruce Sharing from any origin.
// Don't do this without consideration in production systems.
func allowCORS(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			if r.Method == "OPTIONS" && r.Header.Get("Access-Control-Request-Method") != "" {
				preflightHandler(w, r)
				return
			}
		}
		h.ServeHTTP(w, r)
	})
}

// preflightHandler adds the necessary headers in order to serve
// CORS from any origin using the methods "GET", "HEAD", "POST", "PUT", "DELETE"
// We insist, don't do this without consideration in production systems.
func preflightHandler(w http.ResponseWriter, r *http.Request) {
	headers := []string{"Content-Type", "Accept", "Authorization"}
	w.Header().Set("Access-Control-Allow-Headers", strings.Join(headers, ","))
	methods := []string{"GET", "HEAD", "POST", "PUT", "DELETE"}
	w.Header().Set("Access-Control-Allow-Methods", strings.Join(methods, ","))
}

// ------------------------------------------------------------------------------------------
// Tunnel API

func (t *Tunnel) GetTunnelInfo(ctx context.Context, in *pb.TunnelInfoRequest) (
	reply *pb.TunnelInfoReply, err error) {

	return &pb.TunnelInfoReply{
		Status:      "OK",
		SwapEnabled: t.swapEnabled(),
	}, nil
}

func (t *Tunnel) GetNetworks(ctx context.Context, in *pb.NetworksRequest) (
	reply *pb.NetworksReply, err error) {

	networks := make([]*pb.Blockchain, 0)

	for _, bc := range t.blockchains {
		networks = append(networks, &pb.Blockchain{
			Slug:      bc.Slug,
			Network:   bc.Network,
			ChainId:   bc.ChainId,
			BaseChain: bc.BaseChain.String(),
		})
	}

	return &pb.NetworksReply{Networks: networks}, nil
}

func (t *Tunnel) GetBridges(ctx context.Context, in *pb.BridgesRequest) (
	reply *pb.BridgesReply, err error) {

	bridges := make([]*pb.BridgePairs, 0)

	for aBcId, bBridge := range t.bridges {
		for bBcId, isPair := range bBridge {
			if isPair {
				bc1, ok1 := t.blockchains[t.slugs[aBcId]]
				if !ok1 {
					continue
				}
				bc2, ok2 := t.blockchains[t.slugs[bBcId]]
				if !ok2 {
					continue
				}
				bridges = append(bridges, &pb.BridgePairs{
					Bc1: &pb.Blockchain{
						Slug:      bc1.Slug,
						Network:   bc1.Network,
						ChainId:   bc1.ChainId,
						BaseChain: bc1.BaseChain.String(),
					},
					Bc2: &pb.Blockchain{
						Slug:      bc2.Slug,
						Network:   bc2.Network,
						ChainId:   bc2.ChainId,
						BaseChain: bc2.BaseChain.String(),
					}})
			}
		}
	}

	return &pb.BridgesReply{
		Bridges: bridges,
	}, nil
}

func (t *Tunnel) GetAccountInfo(ctx context.Context, in *pb.AccountInfoRequest) (
	reply *pb.AccountInfoReply, err error) {

	var address config.Address

	recipientAddress := in.RecipientAddress

	if recipientAddress == "" || in.RecipientBlockchain == "" || in.DepositBlockchain == "" {
		return nil, ErrorCode(errEmptyArgs)
	}

	recipientBcName := in.RecipientBlockchain
	depositBcName := in.DepositBlockchain

	recipientBc, ok := t.blockchains[recipientBcName]
	if !ok {
		return nil, ErrorCode(errDirectionAndChain)
	}
	depositBc, ok := t.blockchains[depositBcName]
	if !ok {
		return nil, ErrorCode(errDirectionAndChain)
	}
	if recipientBc == nil || depositBc == nil {
		return nil, ErrorCode(errServerError)
	}
	if recipientBc.BlockchainId == depositBc.BlockchainId {
		return nil, ErrorCode(errInvalidDirection)
	}
	if !t.isBridges(recipientBc.BlockchainId, depositBc.BlockchainId) {
		return nil, ErrorCode(errInvalidDirection)
	}

	switch recipientBc.BaseChain {
	case blockchain.Ethereum:
		mAddress, err := common.NewMixedcaseAddressFromString(recipientAddress)
		if err != nil {
			return nil, ErrorCode(errInvalidAddress)
		}
		if !mAddress.ValidChecksum() && strings.ToLower(mAddress.Address().Hex()) != recipientAddress {
			return nil, ErrorCode(errInvalidAddress)
		}
		address = mAddress.Address()
	case blockchain.Dogecoin:
		defaultNet := &dchaincfg.MainNetParams
		if recipientBc.ChainId == "test" {
			defaultNet = &dogecoin.TestNetParams
		}
		address, err = dbtcutil.DecodeAddress(recipientAddress, defaultNet)
		if err != nil {
			return nil, ErrorCode(errInvalidDirection)
		}
	case blockchain.NewChain:
		chainIdBig, ok := big.NewInt(0).SetString(recipientBc.ChainId, 10)
		if !ok {
			return nil, ErrorCode(errInvalidAddress)
		}
		address, err = newton.ToAddress(chainIdBig, recipientAddress)
		if err != nil {
			return nil, Error(err)
		}
	case blockchain.Tron:
		// only TR-Address
		tronAddress, err := tron.NewAddress(recipientAddress)
		if err != nil {
			return nil, Error(err)
		}
		address = tronAddress
	case blockchain.Bitcoin:

	default:
		return nil, ErrorCode(errInvalidDirection)
	}

	if address == nil || address.String() == "" {
		return nil, ErrorCode(errInvalidAddress)
	}

	// enable swap
	enableSwap := in.EnableSwap
	if !t.swapEnabled() {
		enableSwap = false
	}
	if t.sc != nil && t.sc.pairs != nil {
		toBcIdMap, ok := t.sc.pairs[depositBc.BlockchainId]
		if !ok {
			enableSwap = false
		}
		if !toBcIdMap[recipientBc.BlockchainId] {
			enableSwap = false
		}
	}

	sess, err := t.openDatabase()
	if err != nil {
		log.Errorln(Error(err))
		return nil, Error(err)
	}
	defer sess.Close()

	var (
		iAddress     config.Address
		checkAccount database.Account
		account      database.Account
		// iBc          blockchain.BlockChain
	)

	// check address is internal address
	err = sess.SQL().Select("address").
		From("accounts").Where(
		"internal_blockchain_id", recipientBc.BlockchainId).And(
		"internal_address", address.String()).One(&checkAccount)
	if errors.Is(err, db.ErrNoMoreRows) {
		// ok, not the internal address, nothing to do
	} else if err != nil {
		return nil, Error(err)
	} else {
		// error, can NOT bridge to internal address
		return nil, ErrorCode(errInternalAddress)
	}

	// get internal address of address
	err = sess.SQL().Select("internal_address").
		From("accounts").Where(
		"blockchain_id", recipientBc.BlockchainId).And(
		"address", address.String()).And(
		"internal_blockchain_id", depositBc.BlockchainId).And(
		"enable_swap", enableSwap).One(&account)
	if errors.Is(err, db.ErrNoMoreRows) {
		// ok, create new internal address
		iAddress, err = t.createInternal(address, sess, depositBc, recipientBc, enableSwap)
		if err != nil {
			return nil, ErrorCode(errGetInternalError)
		}
	} else if err != nil {
		return nil, Error(err)
	} else {
		// ok
		if depositBc.BaseChain == blockchain.Dogecoin {
			defaultNet := &dchaincfg.MainNetParams
			if depositBc.ChainId == "test" {
				defaultNet = &dogecoin.TestNetParams
			}
			iAddress, err = dbtcutil.DecodeAddress(account.InternalAddress, defaultNet)
			if err != nil {
				return nil, ErrorCode(errInvalidAddress)
			}
		} else if depositBc.BaseChain == blockchain.Tron {
			tronAddress, err := tron.NewAddress(account.InternalAddress)
			if err != nil {
				return nil, Error(err)
			}
			if tronAddress.String() == tron.ZeroAddress.String() {
				return nil, ErrorCode(errInternalAddress)
			}

			iAddress = tronAddress
		} else {
			if !common.IsHexAddress(account.InternalAddress) {
				return nil, ErrorCode(errInvalidAddress)
			}
			iAddress = common.HexToAddress(account.InternalAddress)
		}
	}

	if iAddress == nil {
		return nil, ErrorCode(errInvalidAddress)
	}

	reply = &pb.AccountInfoReply{
		RecipientAddress:    address.String(),
		RecipientBlockchain: recipientBc.Slug,
		DepositAddress:      iAddress.String(),
		DepositBlockchain:   depositBc.Slug,
		EnableSwap:          enableSwap,
	}

	if recipientBc.BaseChain == blockchain.NewChain {
		chainIdBig, ok := big.NewInt(0).SetString(recipientBc.ChainId, 10)
		if !ok {
			return nil, ErrorCode(errInvalidAddress)
		}

		reply.RecipientAddress = newton.Address{
			ChainId: chainIdBig,
			Address: address.(common.Address),
		}.String()
	}

	if depositBc.BaseChain == blockchain.NewChain {
		chainIdBig, ok := big.NewInt(0).SetString(depositBc.ChainId, 10)
		if !ok {
			return nil, ErrorCode(errInvalidAddress)
		}

		reply.DepositAddress = newton.Address{
			ChainId: chainIdBig,
			Address: iAddress.(common.Address),
		}.String()
	}

	return reply, nil
}

func createInternalAddress(name, target string) (string, error) {
	conn, err := grpc.NewClient(target, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return "", err
	}
	defer conn.Close()
	ec := chainapi.NewChainAPIClient(conn)

	accountReply, err := ec.CreateAccount(context.Background(),
		&chainapi.CreateAccountRequest{Name: name})
	if err != nil {
		return "", err
	}

	return accountReply.Address, nil
}

func (t *Tunnel) createInternal(address config.Address, sess db.Session, depositBc, recipientBc *config.ChainConfig, enableSwap bool) (config.Address, error) {
	name := utils.GetInternalAddressName(
		recipientBc.Network,
		recipientBc.ChainId,
		address.String(),
		enableSwap)
	iAddressStr, err := createInternalAddress(name, depositBc.ChainAPIHost)
	if err != nil {
		return nil, Error(err)
	}

	if iAddressStr == "" {
		return nil, ErrorCode(errInternalAddress)
	}

	var iAddress config.Address
	if depositBc.BaseChain == blockchain.Dogecoin {
		defaultNet := &dchaincfg.MainNetParams
		if depositBc.ChainId == "test" {
			defaultNet = &dogecoin.TestNetParams
		}

		dogeAddress, err := dbtcutil.DecodeAddress(iAddressStr, defaultNet)
		if err != nil {
			return nil, Error(err)
		}

		iAddress = dogeAddress
	} else if depositBc.BaseChain == blockchain.Tron {
		tronAddress, err := tron.NewAddress(iAddressStr)
		if err != nil {
			return nil, Error(err)
		}
		if tronAddress.String() == tron.ZeroAddress.String() {
			return nil, ErrorCode(errInternalAddress)
		}

		iAddress = tronAddress
	} else {
		if !common.IsHexAddress(iAddressStr) {
			return nil, ErrorCode(errInternalAddress)
		}
		ethAddress := common.HexToAddress(iAddressStr)
		if ethAddress == (common.Address{}) {
			return nil, ErrorCode(errInternalAddress)
		}

		iAddress = ethAddress
	}

	err = sess.Tx(func(tx db.Session) error {
		var account database.Account

		err = sess.SQL().Select("internal_address").
			From("accounts").Where(
			"blockchain_id", recipientBc.BlockchainId).And(
			"address", address.String()).And(
			"internal_blockchain_id", depositBc.BlockchainId).And(
			"enable_swap", enableSwap).One(&account)

		if errors.Is(err, db.ErrNoMoreRows) {
			result, err := tx.SQL().InsertInto("accounts").Columns(
				"blockchain_id", "address", "internal_blockchain_id", "internal_address", "enable_swap").Values(
				recipientBc.BlockchainId, address.String(), depositBc.BlockchainId, iAddress.String(), enableSwap).Exec()
			if err != nil {
				log.Errorln("insert accounts error: ", err)

				me, ok := err.(*mysql.MySQLError)
				if !ok {
					log.Errorln("convert err to MySQLError error: ", Error(err))
					return Error(err)
				}
				if me.Number == 1062 {
					var account database.Account
					err = sess.SQL().Select("internal_address").
						From("accounts").Where(
						"blockchain_id", recipientBc.BlockchainId).And(
						"address", address.String()).And(
						"internal_blockchain_id", depositBc.BlockchainId).And(
						"enable_swap", enableSwap).One(&account)
					if err != nil {
						log.Errorln("Select error: ", Error(err))
						return Error(err)
					}

					if depositBc.BaseChain == blockchain.Dogecoin {
						defaultNet := &dchaincfg.MainNetParams
						if depositBc.ChainId == "test" {
							defaultNet = &dogecoin.TestNetParams
						}
						iAddress, err = dbtcutil.DecodeAddress(account.InternalAddress, defaultNet)
						if err != nil {
							return Error(err)
						}
					} else {
						if !common.IsHexAddress(account.InternalAddress) {
							return ErrorCode(errInvalidAddress)
						}
						iAddress = common.HexToAddress(account.InternalAddress)
					}
					return nil
				}

				return Error(err)
			}

			lastId, err := result.LastInsertId()
			if err != nil {
				return Error(err)
			}
			err = database.UpdateSign(tx, database.TableOfAccounts, uint64(lastId), t.cb.APISignKeyId)
			if err != nil {
				return Error(err)
			}

			return nil
		} else if err != nil {
			return Error(err)
		}

		if depositBc.BaseChain == blockchain.Dogecoin {
			defaultNet := &dchaincfg.MainNetParams
			if depositBc.ChainId == "test" {
				defaultNet = &dogecoin.TestNetParams
			}
			iAddress, err = dbtcutil.DecodeAddress(account.InternalAddress, defaultNet)
			if err != nil {
				return Error(err)
			}
		} else if depositBc.BaseChain == blockchain.Tron {
			tronAddress, err := tron.NewAddress(iAddressStr)
			if err != nil {
				return Error(err)
			}
			if tronAddress.String() == tron.ZeroAddress.String() {
				return ErrorCode(errInternalAddress)
			}

			iAddress = tronAddress
		} else {
			if !common.IsHexAddress(account.InternalAddress) {
				return ErrorCode(errInvalidAddress)
			}
			iAddress = common.HexToAddress(account.InternalAddress)
		}

		return nil
	})
	if err != nil {
		return nil, err
	}

	if iAddress == nil || iAddress.String() == "" {
		return nil, Error(errors.New("get internal address error"))
	}

	log.Infof("Add new account: %s(%s), internal_address: %s(%s)",
		address.String(), recipientBc.Slug, iAddress.String(), depositBc.Slug)

	return iAddress, nil
}

// GetPairs get all pairs
func (t *Tunnel) GetPairs(ctx context.Context, in *pb.PairsRequest) (
	reply *pb.PairsReply, err error) {

	sess, err := t.openDatabase()
	if err != nil {
		log.Errorln(Error(err))
		return nil, Error(err)
	}
	defer sess.Close()

	var pairsList []database.PairDetail
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
		LeftJoin("blockchains b2").On("a2.blockchain_id = b2.id")
	err = s.All(&pairsList)
	if errors.Is(err, db.ErrNoMoreRows) {
		return &pb.PairsReply{Pairs: nil}, nil
	} else if err != nil {
		return nil, Error(err)
	}

	var pairs []*pb.Pair
	for _, l := range pairsList {
		// l.Id
		if t.disabledPairs != nil && t.disabledPairs[l.Id] {
			continue
		}
		aSlug, ok := t.slugs[l.AssetABlockchainId]
		if !ok {
			continue
		}
		bSlug, ok := t.slugs[l.AssetBBlockchainId]
		if !ok {
			continue
		}

		pair := &pb.Pair{
			Id:       l.Id,
			AssetAId: l.AssetAId,
			AssetBId: l.AssetBId,
			BridgePair: fmt.Sprintf("%s-%s",
				aSlug, bSlug),
			AssetA: &pb.Asset{
				Id:        l.AssetAId,
				Asset:     l.AssetAAsset,
				Name:      l.AssetAName,
				Symbol:    l.AssetASymbol,
				Decimals:  uint32(l.AssetADecimals),
				AssetType: l.AssetAAssetType, // TODO: utils.AssetTypeText[utils.AssetTypeCoin],
				Network:   l.AssetANetwork,
				ChainId:   l.AssetAChainId,
				BaseChain: l.AssetABaseChain,
				Slug:      aSlug,
			},
			AssetB: &pb.Asset{
				Id:        l.AssetBId,
				Asset:     l.AssetBAsset,
				Name:      l.AssetBName,
				Symbol:    l.AssetBSymbol,
				Decimals:  uint32(l.AssetBDecimals),
				AssetType: l.AssetBAssetType, // TODO: utils.AssetTypeText[utils.AssetTypeCoin],
				Network:   l.AssetBNetwork,
				ChainId:   l.AssetBChainId,
				BaseChain: l.AssetBBaseChain,
				Slug:      bSlug,
			},
		}

		// mint deposit amount
		aMinDepositAmount, ok := big.NewInt(0).SetString(l.AssetAMinDepositAmount, 10)
		if !ok {
			return nil, ErrorCode(errStringToBigInt)
		}
		bMinDepositAmount, ok := big.NewInt(0).SetString(l.AssetBMinDepositAmount, 10)
		if !ok {
			return nil, ErrorCode(errStringToBigInt)
		}
		pair.A2BMinDepositAmount = utils.GetAmountTextFromISAACWithDecimals(aMinDepositAmount, l.AssetADecimals)
		pair.B2AMinDepositAmount = utils.GetAmountTextFromISAACWithDecimals(bMinDepositAmount, l.AssetBDecimals)

		// fee percent
		pair.A2BFeePercent = fmt.Sprintf("%.6f", float64(l.AssetBWithdrawFeePercent)/float64(utils.FeeBase))
		pair.B2AFeePercent = fmt.Sprintf("%.6f", float64(l.AssetAWithdrawFeePercent)/float64(utils.FeeBase))

		// fee min amount
		aWithdrawFeeMin, ok := big.NewInt(0).SetString(l.AssetAWithdrawFeeMin, 10)
		if !ok {
			return nil, ErrorCode(errStringToBigInt)
		}
		bWithdrawFeeMin, ok := big.NewInt(0).SetString(l.AssetBWithdrawFeeMin, 10)
		if !ok {
			return nil, ErrorCode(errStringToBigInt)
		}
		pair.A2BFeeMinAmount = utils.GetAmountTextFromISAACWithDecimals(bWithdrawFeeMin, l.AssetADecimals)
		pair.B2AFeeMinAmount = utils.GetAmountTextFromISAACWithDecimals(aWithdrawFeeMin, l.AssetBDecimals)

		// auto confirm amount
		aAutoConfirmDepositAmount, ok := big.NewInt(0).SetString(l.AssetAAutoConfirmDepositAmount, 10)
		if !ok {
			return nil, ErrorCode(errStringToBigInt)
		}
		bAutoConfirmDepositAmount, ok := big.NewInt(0).SetString(l.AssetBAutoConfirmDepositAmount, 10)
		if !ok {
			return nil, ErrorCode(errStringToBigInt)
		}
		pair.A2BAutoConfirmDepositAmount = utils.GetAmountTextFromISAACWithDecimals(aAutoConfirmDepositAmount, l.AssetADecimals)
		pair.B2AAutoConfirmDepositAmount = utils.GetAmountTextFromISAACWithDecimals(bAutoConfirmDepositAmount, l.AssetBDecimals)

		if t.sc != nil && t.sc.pairs != nil {
			if t.sc.pairs[l.AssetABlockchainId] != nil && t.sc.pairs[l.AssetABlockchainId][l.AssetBBlockchainId] {
				pair.A2BEnableSwap = true

				if l.AssetASymbol != "USDT" {
					return nil, Error(fmt.Errorf("swap config error"))
				}

				var nativeAsset database.Asset
				err = sess.SQL().Select("id", "blockchain_id", "asset",
					"name", "symbol", "decimals").From("assets").Where(
					"blockchain_id", l.AssetBBlockchainId).And(
					"asset", "").One(&nativeAsset)
				if errors.Is(err, db.ErrNoMoreRows) {
					return nil, ErrorCode(errServerError)
				} else if err != nil {
					return nil, Error(err)
				}
				if nativeAsset.Symbol != newton.Symbol {
					return nil, Error(fmt.Errorf("native asset not support"))
				}

				// ok
				swapAmount, err := t.getNEWPrice()
				if err != nil {
					return nil, Error(err)
				}

				pair.A2BSwapAmount = utils.GetAmountTextFromISAACWithDecimals(swapAmount, nativeAsset.Decimals)

			}
			if t.sc.pairs[l.AssetBBlockchainId] != nil && t.sc.pairs[l.AssetBBlockchainId][l.AssetABlockchainId] {
				pair.B2AEnableSwap = true

				if l.AssetBSymbol != "USDT" {
					return nil, Error(fmt.Errorf("swap config error"))
				}

				var nativeAsset database.Asset
				err = sess.SQL().Select("id", "blockchain_id", "asset",
					"name", "symbol", "decimals").From("assets").Where(
					"blockchain_id", l.AssetABlockchainId).And(
					"asset", "").One(&nativeAsset)
				if errors.Is(err, db.ErrNoMoreRows) {
					return nil, ErrorCode(errServerError)
				} else if err != nil {
					return nil, Error(err)
				}
				if nativeAsset.Symbol != newton.Symbol {
					return nil, Error(fmt.Errorf("native asset not support"))
				}

				// ok
				swapAmount, err := t.getNEWPrice()
				if err != nil {
					return nil, Error(err)
				}

				pair.B2ASwapAmount = utils.GetAmountTextFromISAACWithDecimals(swapAmount, nativeAsset.Decimals)
			}
		}

		if t.disabledPairsDirection != nil {
			if t.disabledPairsDirection[l.Id] != nil {
				pair.A2BDisabled = t.disabledPairsDirection[l.Id][l.AssetAId]
				pair.B2ADisabled = t.disabledPairsDirection[l.Id][l.AssetBId]
			}
		}

		pairs = append(pairs, pair)
	}

	return &pb.PairsReply{Pairs: pairs}, nil
}

func (t *Tunnel) GetTunnelHistory(ctx context.Context, in *pb.HistoryRequest) (
	reply *pb.HistoryReply, err error) {

	reply = &pb.HistoryReply{
		SourceAddress:         in.SourceAddress,
		SourceSender:          in.SourceSender,
		SourceBlockchain:      in.SourceBlockchain,
		SourceAssetId:         in.SourceAssetId,
		DestinationBlockchain: in.DestinationBlockchain,
		DestinationAssetId:    in.DestinationAssetId,
		PairId:                in.PairId,
		Status:                in.Status,
	}

	pageId, pageSize := in.PageId, in.PageSize
	if pageId == 0 {
		pageId = 1
	}
	if pageSize == 0 {
		pageSize = 50
	}

	whereCond := db.Cond{}
	if in.SourceAddress != "" {
		if !coins.IsSupportAddress(in.SourceAddress) {
			return nil, ErrorCode(errInvalidAddress)
		}
		whereCond["h.address"] = in.SourceAddress
	}

	if in.SourceSender != "" {
		senderListAll := strings.Split(in.SourceSender, ",")
		var senderList []interface{}
		for _, sender := range senderListAll {
			// just ignore not support address
			if !coins.IsSupportAddress(sender) {
				// 	return nil, ErrorCode(errInvalidAddress)
				continue
			}

			if sender[:3] == "NEW" {
				senderAddress, err := newton.ToAddressUnsafe(sender)
				if err != nil {
					return nil, ErrorCode(errInvalidAddress)
				}
				sender = senderAddress.String()
			}

			senderList = append(senderList, sender)
		}
		if len(senderList) > 0 {
			whereCond["h.sender IN"] = senderList
		}
	}

	if in.SourceBlockchain != "" {
		bc, ok := t.blockchains[in.SourceBlockchain]
		if !ok {
			return nil, ErrorCode(errDirectionAndChain)
		}
		if bc == nil {
			return nil, ErrorCode(errServerError)
		}
		whereCond["h.blockchain_id"] = bc.BlockchainId

		switch bc.BaseChain {
		case blockchain.NewChain:
			chainId, ok := big.NewInt(0).SetString(bc.ChainId, 10)
			if !ok {
				return nil, ErrorCode(errServerError)
			}

			if in.SourceAddress != "" {
				nAddr, err := newton.New(chainId, in.SourceAddress)
				if err != nil {
					return nil, Error(err)
				}
				whereCond["h.address"] = nAddr.Address.String()
			}
			if in.SourceSender != "" {
				senderListAll := strings.Split(in.SourceSender, ",")
				var senderList []interface{}
				for _, sender := range senderListAll {
					senderAddress, err := newton.New(chainId, sender)
					if err != nil {
						return nil, ErrorCode(errInvalidAddress)
					}
					sender = senderAddress.String()

					senderList = append(senderList, sender)
				}
				if len(senderList) > 0 {
					whereCond["h.sender IN"] = senderList
				}
			}
		case blockchain.Ethereum:
			if in.SourceAddress != "" {
				if !common.IsHexAddress(in.SourceAddress) {
					return nil, ErrorCode(errInvalidAddress)
				}
				whereCond["h.address"] = common.HexToAddress(in.SourceAddress)
			}
			if in.SourceSender != "" {
				senderListAll := strings.Split(in.SourceSender, ",")
				var senderList []interface{}
				for _, sender := range senderListAll {
					if !common.IsHexAddress(sender) {
						return nil, ErrorCode(errInvalidAddress)
					}

					senderList = append(senderList, common.HexToAddress(sender).String())
				}

				if len(senderList) > 0 {
					whereCond["h.sender IN"] = senderList
				}
			}
		case blockchain.Tron:
			if in.SourceAddress != "" {
				tAddr, err := tron.NewAddress(in.SourceAddress)
				if err != nil {
					return nil, ErrorCode(errInvalidAddress)
				}
				whereCond["h.address"] = tAddr.String()
			}
			if in.SourceSender != "" {
				senderListAll := strings.Split(in.SourceSender, ",")
				var senderList []interface{}
				for _, sender := range senderListAll {
					tAddr, err := tron.NewAddress(sender)
					if err != nil {
						return nil, ErrorCode(errInvalidAddress)
					}

					senderList = append(senderList, tAddr.String())
				}

				if len(senderList) > 0 {
					whereCond["h.sender IN"] = senderList
				}
			}
		default:
			return nil, ErrorCode(errDirectionAndChain)
		}
	}

	if in.DestinationAddress != "" {
		if !coins.IsSupportAddress(in.DestinationAddress) {
			return nil, ErrorCode(errInvalidAddress)
		}
		whereCond["h.recipient"] = in.DestinationAddress
	}
	if in.DestinationBlockchain != "" {
		bc, ok := t.blockchains[in.DestinationBlockchain]
		if !ok {
			return nil, ErrorCode(errDirectionAndChain)
		}
		if bc == nil {
			return nil, ErrorCode(errServerError)
		}
		whereCond["h.target_blockchain_id"] = bc.BlockchainId

		if in.DestinationAddress != "" {
			whereCond["h.recipient"] = in.DestinationAddress

			var address config.Address
			switch bc.BaseChain {
			case blockchain.NewChain:
				chainId, ok := big.NewInt(0).SetString(bc.ChainId, 10)
				if !ok {
					return nil, ErrorCode(errServerError)
				}

				nAddr, err := newton.New(chainId, in.DestinationAddress)
				if err != nil {
					return nil, Error(err)
				}
				address = nAddr.Address
			case blockchain.Ethereum:
				if !common.IsHexAddress(in.DestinationAddress) {
					return nil, ErrorCode(errInvalidAddress)
				}
				address = common.HexToAddress(in.DestinationAddress)
			case blockchain.Tron:
				tAddr, err := tron.NewAddress(in.DestinationAddress)
				if err != nil {
					return nil, ErrorCode(errInvalidAddress)
				}
				address = tAddr
			default:
				return nil, ErrorCode(errDirectionAndChain)
			}
			whereCond["h.recipient"] = address.String()
		}
	}
	if in.Status != "" {
		statusStrList := strings.Split(in.Status, ",")
		var statusList []uint
		for _, statusStr := range statusStrList {
			if strings.ToLower(statusStr) == "confirmed" {
				statusList = append(statusList, []uint{
					utils.BridgeWithdrawConfirmed,
					utils.BridgeMergedBroadcast,
					utils.BridgeMergedConfirmed}...)
				continue
			} else if strings.ToLower(statusStr) == "pending" {
				statusList = append(statusList, []uint{
					utils.BridgeDetectedDeposit,
					utils.BridgeDeposit,
					utils.BridgeDepositConfirmed,
					utils.BridgePendingWithdraw,
					utils.BridgeWithdraw,
					utils.BridgeInsufficientBalance,
					utils.BridgeInsufficientPermissions,
				}...)
				continue
			}
			status := utils.ParseBridgeText(statusStr)
			if status != 0 {
				statusList = append(statusList, status)
			}
		}
		if len(statusList) == 0 {
			return nil, ErrorCode(errNotFound)
		} else if len(statusList) == 1 {
			whereCond["h.status"] = statusList[0]
		} else {
			whereCond["h.status IN"] = statusList
		}
	}

	sess, err := t.openDatabase()
	if err != nil {
		log.Errorln(Error(err))
		return nil, Error(err)
	}
	defer sess.Close()

	// select count(*) from history where doge_address = ""
	total := uint64(0)
	var hCount struct {
		Count uint64 `db:"count"`
	}
	cs := sess.SQL().Select(db.Raw("count(h.id) AS count")).From(
		"history h")

	if in.PairId != "" {
		cs = cs.LeftJoin("assets a1").On("h.blockchain_id = a1.blockchain_id and h.asset = a1.asset").
			LeftJoin("blockchains b1").On("a1.blockchain_id = b1.id").
			LeftJoin("assets a2").On("h.target_blockchain_id = a2.blockchain_id and h.target_asset = a2.asset").
			LeftJoin("blockchains b2").On("a2.blockchain_id = b2.id").
			LeftJoin("pairs p").On("(p.asset_a_id = a1.id and p.asset_b_id = a2.id) or (p.asset_a_id = a2.id and p.asset_b_id = a1.id)")
		whereCond["p.id IN"] = stringToCond(in.PairId)

		if in.SourceAssetId != "" {
			whereCond["a1.id IN"] = stringToCond(in.SourceAssetId)
		}
		if in.DestinationAssetId != "" {
			whereCond["a2.id IN"] = stringToCond(in.DestinationAssetId)
		}
	} else {
		if in.SourceAssetId != "" {
			cs = cs.LeftJoin("assets a1").On("h.blockchain_id = a1.blockchain_id and h.asset = a1.asset")
			whereCond["a1.id IN"] = stringToCond(in.SourceAssetId)
		}
		if in.DestinationAssetId != "" {
			cs = cs.LeftJoin("assets a2").On("h.target_blockchain_id = a2.blockchain_id and h.target_asset = a2.asset")
			whereCond["a2.id IN"] = stringToCond(in.DestinationAssetId)
		}
	}

	if !whereCond.Empty() {
		cs = cs.Where(whereCond)
	}
	err = cs.One(&hCount)
	if err != nil {
		log.Errorln(Error(err))
		return nil, Error(err)
	}
	total = hCount.Count
	if total == 0 {
		return reply, nil
	}
	reply.PageId = pageId
	reply.PageSize = pageSize
	reply.TotalHistory = total
	reply.TotalPage = total/pageSize + 1

	var historyList []database.HistoryDetail
	s := sess.SQL().Select(
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
		"b2.base_chain AS target_base_chain",
		"a.id AS swap_asset_id",
		"a.name AS swap_asset_name",
		"a.symbol AS swap_asset_symbol",
		"a.decimals AS swap_asset_decimals",
		"a.asset_type AS swap_asset_type",
	).From("history h").
		LeftJoin("assets a1").On("h.blockchain_id = a1.blockchain_id and h.asset = a1.asset").
		LeftJoin("blockchains b1").On("a1.blockchain_id = b1.id").
		LeftJoin("assets a2").On("h.target_blockchain_id = a2.blockchain_id and h.target_asset = a2.asset").
		LeftJoin("blockchains b2").On("a2.blockchain_id = b2.id").
		LeftJoin("pairs p").On("(p.asset_a_id = a1.id and p.asset_b_id = a2.id) or (p.asset_a_id = a2.id and p.asset_b_id = a1.id)").
		LeftJoin("assets a").On("h.target_blockchain_id = a.blockchain_id and a.asset = ''")

	if !whereCond.Empty() {
		s = s.Where(whereCond)
	}

	err = s.OrderBy("h.id DESC").Offset(
		int((pageId - 1) * pageSize)).Limit(int(pageSize)).All(&historyList)
	if errors.Is(err, db.ErrNoMoreRows) {

	} else if err != nil {
		log.Errorln(Error(err))
		return nil, Error(err)
	}
	if len(historyList) == 0 {
		return reply, nil
	}

	list := make([]*pb.History, len(historyList))
	for i, l := range historyList {
		h := &pb.History{
			Id: l.Id,

			SourceSlug:      t.slugs[l.BlockchainId],
			SourceNetwork:   l.Network,
			SourceChainId:   l.ChainId,
			SourceBaseChain: l.BaseChain,
			DestinationSlug: t.slugs[l.TargetBlockchainId],
			// DestinationNetwork:   l.TargetNetwork,
			// DestinationChainId:   l.TargetChainId,
			// DestinationBaseChain: l.TargetBaseChain,

			SourceAddress:      l.Address,
			SourceSender:       l.Sender,
			DestinationAddress: l.Recipient,

			SourceBlockNumber:         l.BlockNumber,
			DestinationBlockNumber:    l.TargetBlockNumber,
			SourceBlockTimestamp:      l.BlockTimestamp.Unix(),
			DestinationBlockTimestamp: l.TargetBlockTimestamp.Unix(),
			SourceTxHash:              l.TxHash,
			DestinationTxHash:         l.TargetTxHash,

			SourceAssetId:       l.AssetId,
			SourceAssetAddress:  l.Asset,
			SourceAssetName:     l.AssetName,
			SourceAssetSymbol:   l.AssetSymbol,
			SourceAssetDecimals: uint32(l.AssetDecimals),
			SourceAssetType:     l.AssetType,

			// DestinationAssetId:       l.TargetAssetId,
			DestinationAssetAddress: l.TargetAsset,
			// DestinationAssetName:     l.TargetAssetName,
			// DestinationAssetSymbol:   l.TargetAssetSymbol,
			// DestinationAssetDecimals: uint32(l.TargetAssetDecimals),
			// DestinationAssetType:     l.TargetAssetType,

			Status:        utils.BridgeText[l.Status],
			StatusMessage: utils.BridgeText[l.Status],
		}
		if l.PairId != nil {
			h.PairId = *l.PairId
		}

		if blockchain.Parse(l.BaseChain) == blockchain.NewChain {
			chainId, ok := big.NewInt(0).SetString(l.ChainId, 10)
			if !ok {
				return nil, ErrorCode(errServerError)
			}
			if l.Address != "" {
				h.SourceAddress = newton.Address{
					ChainId: chainId,
					Address: common.HexToAddress(l.Address),
				}.String()
			}
			if l.Sender != "" {
				h.SourceSender = newton.Address{
					ChainId: chainId,
					Address: common.HexToAddress(l.Sender),
				}.String()
			}
		}

		if l.Status == utils.BridgeWithdrawConfirmed || l.Status == utils.BridgeMergedBroadcast || l.Status == utils.BridgeMergedConfirmed {
			h.Status = "Confirmed"
			h.StatusMessage = "Confirmed"
		} else if !t.isManager && l.Status != 0 {
			// change status for user
			if l.Status < utils.BridgeMergedBroadcast {
				h.Status = "Pending"
			} else if l.Status > utils.BridgeInternalTx {
				h.Status = "Error"
			}
		}

		if l.TargetNetwork != nil {
			h.DestinationNetwork = *l.TargetNetwork
		}
		if l.TargetChainId != nil {
			h.DestinationChainId = *l.TargetChainId
		}
		if l.TargetBaseChain != nil {
			h.DestinationBaseChain = *l.TargetBaseChain
		}
		if l.TargetChainId != nil && l.TargetBaseChain != nil && l.Recipient != "" {
			if blockchain.Parse(*l.TargetBaseChain) == blockchain.NewChain {
				chainId, ok := big.NewInt(0).SetString(*l.TargetChainId, 10)
				if !ok {
					return nil, ErrorCode(errServerError)
				}

				h.DestinationAddress = newton.Address{
					ChainId: chainId,
					Address: common.HexToAddress(l.Recipient),
				}.String()
			}
		}

		if l.TargetAssetId != nil {
			h.DestinationAssetId = *l.TargetAssetId
		}
		if l.TargetAssetName != nil {
			h.DestinationAssetName = *l.TargetAssetName
		}
		if l.TargetAssetSymbol != nil {
			h.DestinationAssetSymbol = *l.TargetAssetSymbol
		}
		if l.TargetAssetDecimals != nil {
			h.DestinationAssetDecimals = uint32(*l.TargetAssetDecimals)
		}
		if l.TargetAssetType != nil {
			h.DestinationAssetType = *l.TargetAssetType
		}

		if l.Amount != "" {
			amount := big.NewInt(0)
			if _, ok := amount.SetString(l.Amount, 10); !ok {
				return nil, ErrorCode(errServerError)
			}
			h.SourceAmount = utils.GetAmountTextFromISAACWithDecimals(amount, l.AssetDecimals)
		}

		if l.FinalAmount != "" && l.TargetAssetDecimals != nil {
			finalAmount := big.NewInt(0)
			if _, ok := finalAmount.SetString(l.FinalAmount, 10); !ok {
				return nil, ErrorCode(errServerError)
			}
			h.DestinationAmount = utils.GetAmountTextFromISAACWithDecimals(finalAmount, *l.TargetAssetDecimals)
		}

		if l.Fee != "" && l.TargetAssetDecimals != nil {
			fee := big.NewInt(0)
			if _, ok := fee.SetString(l.Fee, 10); !ok {
				return nil, ErrorCode(errServerError)
			}
			h.Fee = utils.GetAmountTextFromISAACWithDecimals(fee, *l.TargetAssetDecimals)
		}

		if l.SwapAmountUsed != "" {
			// ok, swap
			swapAmountUsed := big.NewInt(0)
			if _, ok := swapAmountUsed.SetString(l.SwapAmountUsed, 10); !ok {
				return nil, ErrorCode(errServerError)
			}
			h.SwapAmountUsed = utils.GetAmountTextFromISAACWithDecimals(swapAmountUsed, l.AssetDecimals)

			if l.SwapAssetDecimals != nil {
				swapAmount := big.NewInt(0)
				if _, ok := swapAmount.SetString(l.SwapAmount, 10); !ok {
					return nil, ErrorCode(errServerError)
				}
				h.SwapAmount = utils.GetAmountTextFromISAACWithDecimals(swapAmount, *l.SwapAssetDecimals)
			}

			if l.SwapAssetId != nil {
				h.SwapAssetId = *l.SwapAssetId
			}
			if l.SwapAssetName != nil {
				h.SwapAssetName = *l.SwapAssetName
			}
			if l.SwapAssetSymbol != nil {
				h.SwapAssetSymbol = *l.SwapAssetSymbol
			}
			if l.SwapAssetDecimals != nil {
				h.SwapAssetDecimals = uint32(*l.SwapAssetDecimals)
			}
			if l.SwapAssetType != nil {
				h.SwapAssetType = *l.SwapAssetType
			}

			h.SwapBlockNumber = l.SwapBlockNumber
			h.SwapBlockTimestamp = l.SwapBlockTimestamp.Unix()
			h.SwapTxHash = l.SwapTxHash
		}

		// list = append(list, h)
		list[i] = h
	}

	reply.List = list
	return reply, nil
}

func stringToCond(strs string) []interface{} {
	if strs == "" {
		return nil
	}

	strList := strings.Split(strs, ",")
	if len(strList) == 0 {
		return nil
	}

	result := make([]interface{}, len(strList))
	for i, str := range strList {
		result[i] = str
	}

	return result
}
