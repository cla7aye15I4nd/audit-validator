package tests

import (
	"crypto/ecdsa"
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/core/orderbook"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/holiman/uint256"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/consensus/ethash"
	"github.com/ethereum/go-ethereum/core"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/core/vm"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/params"
	"github.com/stretchr/testify/suite"
)

type OrderMatchingTestSuite struct {
	suite.Suite
	chainConfig *params.ChainConfig
	engine      *ethash.Ethash
	sessionKey  *ecdsa.PrivateKey
	sessionAddr common.Address
	signer      types.Signer
	l1Key       *ecdsa.PrivateKey
	l1Owner     common.Address
	genesis     *core.Genesis
	chain       *core.BlockChain
	blocks      []*types.Block
}

func (suite *OrderMatchingTestSuite) SetupTest() {
	suite.chainConfig = params.TestChainConfig
	suite.engine = ethash.NewFaker()
	suite.sessionKey, _ = crypto.GenerateKey()
	suite.sessionAddr = crypto.PubkeyToAddress(suite.sessionKey.PublicKey)
	suite.l1Key, _ = crypto.GenerateKey()
	suite.l1Owner = crypto.PubkeyToAddress(suite.l1Key.PublicKey)
	suite.genesis = &core.Genesis{
		Config: suite.chainConfig,
		Alloc: types.GenesisAlloc{
			suite.l1Owner:     {Balance: big.NewInt(1e18)},
			suite.sessionAddr: {Balance: big.NewInt(1e18)},
		},
	}

	suite.signer = types.LatestSigner(suite.chainConfig)
}

func (suite *OrderMatchingTestSuite) InsertTxToBlock(txs []types.Serializable) {
	db, blocks, _ := core.GenerateChainWithGenesis(suite.genesis, suite.engine, 1, func(i int, gen *core.BlockGen) {
		for i, tx := range txs {
			serializedTx, err := tx.Serialize()
			suite.Require().NoError(err)
			tx := types.NewTransaction(uint64(i), common.Address{}, big.NewInt(0), 1_000_000, big.NewInt(25e9), serializedTx)
			signedTx, err := types.SignTx(tx, suite.signer, suite.l1Key)
			suite.Require().NoError(err)
			gen.AddTx(signedTx)
		}
	})

	var err error
	suite.chain, err = core.NewBlockChain(db, nil, suite.chainConfig, suite.genesis, nil, suite.engine, vm.Config{}, nil)
	suite.Require().NoError(err)

	suite.blocks = blocks

	_, err = suite.chain.InsertChain(suite.blocks)
	suite.Require().NoError(err)

	block1 := suite.chain.GetBlockByNumber(1)
	suite.Require().NotNil(block1)
	suite.Require().Equal(len(txs), len(block1.Transactions()))
}

func (suite *OrderMatchingTestSuite) TearDownTest() {
	if suite.chain != nil {
		suite.chain.Stop()
	}
}

func TestOrderMatchingTestSuite(t *testing.T) {
	suite.Run(t, new(OrderMatchingTestSuite))
}

func (suite *OrderMatchingTestSuite) TestOrderMatchingAndLogCheck() {
	// 1. BUY 주문 생성
	orderTxBuy := &types.OrderContext{
		L1Owner:    suite.l1Owner,
		BaseToken:  "BTC",
		QuoteToken: "USDT",
		Side:       0, // BUY
		Price:      big.NewInt(40),
		Quantity:   big.NewInt(1),
		OrderType:  0, // LIMIT
	}

	// 2. SELL 주문 생성 (같은 가격, 수량)
	orderTxSell := &types.OrderContext{
		L1Owner:    suite.l1Owner,
		BaseToken:  "BTC",
		QuoteToken: "USDT",
		Side:       1, // SELL
		Price:      big.NewInt(40),
		Quantity:   big.NewInt(1),
		OrderType:  0, // LIMIT
	}

	// 3. 두 개의 주문을 블록에 추가
	suite.InsertTxToBlock([]types.Serializable{orderTxBuy, orderTxSell})

	// 4. Receipt 확인
	block1 := suite.chain.GetBlockByNumber(1)
	suite.Require().NotNil(block1)

	receipts := suite.chain.GetReceiptsByHash(block1.Hash())
	suite.Require().Equal(2, len(receipts))

	// 5. 두 번째 트랜잭션 (SELL)에 체결 로그가 있어야 함
	sellReceipt := receipts[1]
	suite.Require().Equal(types.ReceiptStatusSuccessful, sellReceipt.Status)
	suite.Require().Greater(len(sellReceipt.Logs), 0, "No logs found in SELL receipt")

	// 6. 첫 번째 Log 디코딩
	log := sellReceipt.Logs[0]
	suite.T().Logf("Log Address: %s", log.Address.Hex())
	suite.T().Logf("Log Topics: %+v", log.Topics)
	suite.T().Logf("Log Data: %x", log.Data)

	// 7. Trade 구조체로 디코딩 (예시)
	var trade *orderbook.Trade
	err := rlp.DecodeBytes(log.Data, trade)
	suite.Require().NoError(err)

	expectedPrice := uint256.NewInt(40)
	expectedQuantity := uint256.NewInt(1)

	suite.Require().Equal(0, trade.Price.Cmp(expectedPrice), "Unexpected trade price")
	suite.Require().Equal(0, trade.Quantity.Cmp(expectedQuantity), "Unexpected trade quantity")
}
