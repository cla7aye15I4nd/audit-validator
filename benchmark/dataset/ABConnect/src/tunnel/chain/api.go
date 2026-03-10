package chain

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net"
	"os"
	"strings"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/kms"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/accounts/keystore"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/sirupsen/logrus"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/contract/newasset"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	pb "gitlab.weinvent.org/yangchenzhong/tunnel/proto/chainapi"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins/newton"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/key"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

var log *logrus.Logger

func init() {
	log = logrus.New()
	log.SetOutput(os.Stdout)
}

func logRequest(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
	if info != nil {
		log.WithField("method", info.FullMethod).Info(req)
	}

	// Continue execution of handler after ensuring a valid token.
	return handler(ctx, req)
}

type ChainId struct {
	ChainId   *big.Int
	ChainName string
}

type Chain struct {
	pb.UnimplementedChainAPIServer

	baseChain blockchain.BlockChain
	bcId      uint64 // blockchains.id from database

	chainID   *big.Int // ethereum
	chainName string   // dogecoin

	cb             *config.Bridge
	DogecoinConfig *config.ChainConfig `json:"AChain"`
	EthereumConfig *config.ChainConfig `json:"BChain"`
	config         *config.ChainConfig

	// database
	DB *config.ConnectionURL

	scrypt int

	adapterName string
	settings    db.ConnectionURL
	sess        db.Session // for api, tasks and history sess

	durationOfExecTask time.Duration

	walletType WalletType
}

const (
	ActionAPI = iota
	ActionTasks
)

func New(b *config.Bridge, walletType WalletType) (*Chain, error) {

	if b.Blockchain == nil {
		return nil, errors.New("blockchain nil")
	}
	if b.Blockchain.ChainKeyId == "" {
		return nil, errors.New("chain key id is empty")
	}

	c := &Chain{
		cb: b,

		config:    b.Blockchain,
		baseChain: b.Blockchain.BaseChain,

		DB: b.DB,

		walletType: walletType,
	}

	if chainIdBig, ok := big.NewInt(0).SetString(b.Blockchain.ChainId, 10); ok {
		c.chainID = chainIdBig
	} else {
		c.chainName = b.Blockchain.ChainId
	}

	c.adapterName = "mysql"
	c.settings = c.config.DB.ConnectionURL

	{
		if c.baseChain == blockchain.UnknownChain {
			return nil, errors.New("basechain unknown")
		}
		// chain blockchain info with database
		sess, err := database.OpenDatabase(c.DB.Adapter, c.DB.ConnectionURL)
		if err != nil {
			return nil, err
		}
		// defer sess.Close()
		c.sess = sess

		var blockchain database.Blockchain
		err = sess.SQL().Select("id", "network", "chain_id", "base_chain").From(
			"blockchains").Where(
			"network", c.config.Network).And(
			"chain_id", c.config.ChainId).One(&blockchain)
		if errors.Is(err, db.ErrNoMoreRows) {
			return nil, errors.New("no such blockchain")
		} else if err != nil {
			return nil, err
		} else if blockchain.Id == 0 {
			return nil, errors.New("blockchain id is zero")
		}
		c.bcId = blockchain.Id
	}

	log.Infof("%v-%v-%v created", c.cb.Blockchain.Network, c.cb.Blockchain.ChainId, c.cb.Blockchain.BaseChain)

	return c, nil
}

func (x *Chain) SetScript(script int) error {
	if script != ScryptStandard && script != ScryptLight {
		return errors.New("unknown scrypt")
	}
	x.scrypt = script

	return nil
}

// RunAPIServer ListenAndServer listen and server
func (x *Chain) RunAPIServer(network, hostAddress string) error {

	lis, err := net.Listen(network, hostAddress)
	if err != nil {
		return err
	}

	opts := []grpc.ServerOption{
		grpc.UnaryInterceptor(logRequest),
	}

	s := grpc.NewServer(opts...)

	pb.RegisterChainAPIServer(s, x)

	reflection.Register(s)

	if err := s.Serve(lis); err != nil {
		return err
	}

	return nil

}

// ------------------------------------------------------------------------------------------

func (x *Chain) CreateAccount(ctx context.Context, in *pb.CreateAccountRequest) (
	reply *pb.CreateAccountReply, err error) {

	address, err := CreateAccount(ctx, x.config.ChainKeyId, x.scrypt, x.adapterName, x.settings, in.Name, x.walletType == WalletRPC)
	if err != nil {
		return nil, Error(err)
	}

	return &pb.CreateAccountReply{
		Name:    in.Name,
		Address: address.String(),
	}, nil
}

func CreateAccount(ctx context.Context, keyID string, scrypt int, adapterName string, settings db.ConnectionURL, name string, isRPC bool) (config.Address, error) {
	if log == nil {
		log = logrus.New()
		log.SetOutput(os.Stdout)
	}

	b := make([]byte, 16)
	_, err := io.ReadFull(rand.Reader, b)
	if err != nil {
		log.Println("Error ReadFull: ", err)
		return nil, Error(err)
	}
	passphrase := common.Bytes2Hex(b)

	if keyID == "" {
		log.Errorln("not set keyID")
		return nil, Error(errors.New("not set keyID"))
	}
	// Load AWS configuration
	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		log.Errorln("Failed to load configuration: ", err)
		return nil, Error(err)
	}
	skms := kms.NewFromConfig(cfg)

	eout, err := skms.Encrypt(ctx, &kms.EncryptInput{
		KeyId:     &keyID,
		Plaintext: []byte(passphrase),
	})
	if err != nil {
		log.Errorln("Error kms Encrypt: ", err)
		return nil, Error(err)
	}
	ebase := base64.StdEncoding.EncodeToString(eout.CiphertextBlob)

	var scryptN, scryptP int
	if scrypt == ScryptLight {
		scryptN = keystore.LightScryptN
		scryptP = keystore.LightScryptP
	} else {
		scryptN = keystore.StandardScryptN
		scryptP = keystore.StandardScryptP
	}

	var (
		address config.Address
		keyjson []byte
	)
	if isRPC {
		address, keyjson, err = key.CreateNewDogecoinAccount(passphrase, scryptN, scryptP)
		if err != nil {
			log.Errorln(err)
			return nil, err
		}
		if address == nil || address.String() == "" {
			err = errors.New("address is null")
			log.Errorln("Error createNewAccount: ", err)
			return nil, Error(err)
		}
	} else {
		address, keyjson, err = key.CreateNewAccount(passphrase, scryptN, scryptP)
		if err != nil {
			log.Errorln(err)
			return nil, err
		}
		if address == nil || bytes.Compare(address.(common.Address).Bytes(), common.Address{}.Bytes()) == 0 {
			err = errors.New("address is null")
			log.Errorln("Error createNewAccount: ", err)
			return nil, Error(err)
		}
	}

	if err := saveAccount(adapterName, settings, address.String(), string(keyjson), ebase, name); err != nil {
		log.Errorln("Error saveAccount: ", err)
		return nil, Error(err)
	}

	log.Infoln("New Account: ", address.String())

	return address, nil
}

const (
	ScryptStandard = 1
	ScryptLight    = 2
)

func saveAccount(adapterName string, settings db.ConnectionURL, address, keyjson, passphrase string, name string) (err error) {
	sess, err := database.OpenDatabase(adapterName, settings)
	if err != nil {
		return Error(err)
	}
	defer sess.Close()

	err = sess.Tx(func(tx db.Session) error {
		// if common.IsHexAddress(name) {
		// 	name = hex.EncodeToString(common.HexToAddress(name).Bytes())
		// }
		_, err = tx.SQL().InsertInto("addresses").Columns(
			"address", "keyjson", "password", "name").Values(
			address, keyjson, passphrase, name).Exec()

		if err != nil {
			return Error(err)
		}

		return nil
	})
	if err != nil {
		fmt.Println(err)
		return err
	}

	return nil
}

func (x *Chain) GetChainInfo(ctx context.Context, in *pb.ChainInfoRequest) (
	reply *pb.ChainInfoReply, err error) {

	reply = &pb.ChainInfoReply{
		BlockchainId: x.config.BlockchainId,
		Network:      x.config.Network,
		ChainId:      x.config.ChainId,
		BaseChain:    x.baseChain.String(),
		SignAt:       time.Now().Unix(),
	}

	hb, err := database.Hash(reply)
	if err != nil {
		return nil, Error(err)
	}
	signature, err := database.Sign(x.config.ChainAPISignKeyId, hb)
	if err != nil {
		return nil, Error(err)
	}
	reply.Signature = signature

	return reply, nil
}

func (x *Chain) GetAssetInfo(ctx context.Context, in *pb.AssetInfoRequest) (
	reply *pb.AssetInfoReply, err error) {

	var asset database.Asset
	if x.sess == nil {
		x.sess, err = database.OpenDatabase(x.DB.Adapter, x.DB.ConnectionURL)
		if err != nil {
			return nil, err
		}
	}
	err = x.sess.SQL().SelectFrom("assets").Where(
		"blockchain_id", x.config.BlockchainId).And(
		"asset", in.Asset).One(&asset)
	if errors.Is(err, db.ErrNoMoreRows) {

	} else if err != nil {
		return nil, Error(err)
	} else {
		reply = &pb.AssetInfoReply{
			Asset:     asset.Asset,
			Name:      asset.Name,
			Symbol:    asset.Symbol,
			Decimals:  uint32(asset.Decimals),
			Attribute: asset.Attribute,
			AssetType: asset.AssetType,
		}
	}

	// check onchain, not work for native asset
	if in.Asset != "" {

		client, err := ethclient.Dial(x.config.RpcURL)
		if err != nil {
			return nil, Error(err)
		}
		tokenAddress := common.HexToAddress(in.Asset)
		if tokenAddress == (common.Address{}) {
			return nil, Error(errors.New("token address error"))
		}
		baseToken, err := newasset.NewBaseToken(tokenAddress, client)
		if err != nil {
			return nil, Error(err)
		}

		name, err := baseToken.Name(nil)
		if err != nil {
			return nil, Error(err)
		}
		if reply != nil && reply.Name != "" && name != reply.Name {
			return nil, Error(fmt.Errorf("name onchain is %s not match db %s", reply.Name, name))
		}

		symbol, err := baseToken.Symbol(nil)
		if err != nil {
			return nil, Error(err)
		}
		if reply != nil && reply.Symbol != "" && symbol != reply.Symbol {
			return nil, Error(fmt.Errorf("symbol onchain is %s not match db %s", reply.Symbol, symbol))
		}

		decimals, err := baseToken.Decimals(nil)
		if err != nil {
			return nil, Error(err)
		}
		if reply != nil && decimals != uint8(reply.Decimals) {
			return nil, Error(fmt.Errorf("name onchain is %s not match db %s", reply.Name, name))
		}

		totalSupply, err := baseToken.TotalSupply(nil)
		if err != nil {
			return nil, Error(err)
		}
		if reply != nil {
			reply.TotalSupply = totalSupply.String()
		}

		if reply == nil {
			reply = &pb.AssetInfoReply{
				Asset:       in.Asset,
				Name:        name,
				Symbol:      symbol,
				Decimals:    uint32(decimals),
				TotalSupply: totalSupply.String(),
			}
		}
	} else {
		if reply != nil && strings.HasPrefix(x.config.Network, "AB") {
			// force, 100 Billion
			reply.TotalSupply = new(big.Int).Mul(
				big.NewInt(100_000_000_000),
				new(big.Int).Exp(big.NewInt(10), big.NewInt(18), nil),
			).String()
		}
	}

	if reply == nil {
		reply = &pb.AssetInfoReply{}
	}

	return reply, nil
}

func (x *Chain) GetBlockNumber(ctx context.Context, in *pb.BlockNumberRequest) (
	reply *pb.BlockNumberReply, err error) {

	client, err := ethclient.Dial(x.config.RpcURL)
	if err != nil {
		return nil, Error(err)
	}
	bn, err := client.BlockNumber(ctx)
	if err != nil {
		return nil, Error(err)
	}

	return &pb.BlockNumberReply{Number: bn}, nil
}

func (x *Chain) GetBalance(ctx context.Context, in *pb.BalanceRequest) (
	reply *pb.BalanceReply, err error) {

	client, err := ethclient.Dial(x.config.RpcURL)
	if err != nil {
		return nil, Error(err)
	}

	if in.Address == "" {
		return nil, Error(errors.New("address is null"))
	}

	var address common.Address
	if x.baseChain == blockchain.NewChain && newton.IsNEWAddress(in.Address) {
		newaddr, err := newton.New(x.chainID, in.Address)
		if err != nil {
			return nil, Error(err)
		}
		address = newaddr.Address
	} else {
		if !common.IsHexAddress(in.Address) {
			return nil, Error(errors.New("invalid address"))
		}
		address = common.HexToAddress(in.Address)
	}

	balance := big.NewInt(0)
	if in.Asset == "" {
		balance, err = client.BalanceAt(ctx, address, nil)
	} else {
		var asset common.Address
		if x.baseChain == blockchain.NewChain && newton.IsNEWAddress(in.Asset) {
			newaddr, err := newton.New(x.chainID, in.Asset)
			if err != nil {
				return nil, Error(err)
			}
			asset = newaddr.Address
		}
		if !common.IsHexAddress(in.Asset) {
			return nil, Error(errors.New("invalid address"))
		}
		asset = common.HexToAddress(in.Asset)

		token, err := newasset.NewBaseToken(asset, client)
		if err != nil {
			return nil, Error(err)
		}
		balance, err = token.BalanceOf(&bind.CallOpts{Context: ctx}, address)
	}
	if err != nil {
		return nil, Error(err)
	}
	if balance == nil {
		return nil, Error(errors.New("invalid balance"))
	}

	return &pb.BalanceReply{
		Address: in.Address,
		Asset:   in.Asset,
		Balance: balance.String(),
	}, nil
}
