package tests

import (
	"crypto/ecdsa"
	"encoding/hex"
	"fmt"
	"github.com/stretchr/testify/require"
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/consensus/ethash"
	"github.com/ethereum/go-ethereum/core"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/core/vm"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/params"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/suite"
)

type SessionTestSuite struct {
	suite.Suite
	chainConfig *params.ChainConfig
	engine      *ethash.Ethash
	sessionKey  *ecdsa.PrivateKey
	sessionAddr common.Address
	signer      types.Signer
	l1Key       *ecdsa.PrivateKey
	l1Owner     common.Address
	to          common.Address
	genesis     *core.Genesis
	chain       *core.BlockChain
	blocks      []*types.Block
}

func (suite *SessionTestSuite) SetupTest() {
	suite.chainConfig = params.TestChainConfig
	suite.engine = ethash.NewFaker()
	suite.sessionKey, _ = crypto.ToECDSA(common.Hex2Bytes("59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d")) // test-junk #1, 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
	suite.sessionAddr = common.HexToAddress("0x70997970C51812dc3A010C7d01b50e0d17dc79C8")
	suite.l1Owner = common.HexToAddress("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266") // test-junk #0
	suite.l1Key, _ = crypto.ToECDSA(common.Hex2Bytes("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"))
	suite.to = common.HexToAddress("0x00000000000000000000000000000000deadbeef")
	suite.genesis = &core.Genesis{
		Config: suite.chainConfig,
		Alloc: types.GenesisAlloc{
			suite.l1Owner:     {Balance: big.NewInt(1e18)},
			suite.sessionAddr: {Balance: big.NewInt(1e18)}, // TODO-nova: remove after gas price is zero.
		},
	}

	suite.signer = types.LatestSigner(suite.chainConfig)
}

func (suite *SessionTestSuite) InsertTxToBlock(txs []types.Serializable) {
	// Generate chain with genesis
	db, blocks, _ := core.GenerateChainWithGenesis(suite.genesis, suite.engine, 1, func(i int, gen *core.BlockGen) {
		for i, tx := range txs {
			serializedTx, err := types.WrapTxAsInput(tx)
			suite.Require().NoError(err)
			tx := types.NewTransaction(uint64(i), common.Address{}, big.NewInt(0), 1000000, big.NewInt(25e9), serializedTx)
			signedTx, err := types.SignTx(tx, suite.signer, suite.sessionKey)
			suite.Require().NoError(err)
			gen.AddTx(signedTx)
		}
	})

	// Create blockchain instance
	var err error
	suite.chain, err = core.NewBlockChain(db, nil, suite.chainConfig, suite.genesis, nil, suite.engine, vm.Config{}, nil)
	suite.Require().NoError(err)

	suite.blocks = blocks

	// Insert the generated blocks
	_, err = suite.chain.InsertChain(suite.blocks)
	suite.Require().NoError(err)

	// Verify the transaction was included in the block
	block1 := suite.chain.GetBlockByNumber(1)
	suite.Require().NotNil(block1)
	suite.Require().Equal(len(txs), len(block1.Transactions()))

	// Get receipts from block
	receipts := suite.chain.GetReceiptsByHash(block1.Hash())
	for _, rc := range receipts {
		suite.Require().Equal(types.ReceiptStatusSuccessful, rc.Status)
	}
}

func (suite *SessionTestSuite) GetBalanceDiff(addr common.Address) *uint256.Int {
	statedb, err := suite.chain.StateAt(suite.chain.GetBlockByNumber(0).Root())
	suite.Require().NoError(err)
	bal0 := statedb.GetBalance(addr)

	statedb, err = suite.chain.StateAt(suite.chain.GetBlockByNumber(1).Root())
	suite.Require().NoError(err)
	bal1 := statedb.GetBalance(addr)

	return new(uint256.Int).Sub(bal1, bal0)
}

func (suite *SessionTestSuite) TearDownTest() {
	if suite.chain != nil {
		suite.chain.Stop()
	}
}

func (suite *SessionTestSuite) TestSessionCreateTx() {
	// Create and sign nova session tx
	sessionTx := &types.SessionContext{
		Command: types.SessionCreate,
		Session: types.Session{
			PublicKey: suite.sessionAddr,
			ExpiresAt: 100,
			Metadata:  nil,
		},
		L1Owner:     suite.l1Owner,
		L1Signature: nil,
	}

	typedData := types.ToTypedData(&sessionTx.Session)
	_, sigHash, _ := types.SignEip712(typedData)
	sig, err := crypto.Sign(sigHash, suite.l1Key)
	suite.Require().NoError(err)
	sessionTx.L1Signature = sig

	vtTx := &types.ValueTransferContext{
		L1Owner: suite.l1Owner,
		To:      suite.to,
		Value:   big.NewInt(100),
	}
	suite.InsertTxToBlock([]types.Serializable{sessionTx, vtTx})

	statedb, _ := suite.chain.State()
	suite.Equal(1, len(statedb.GetSessions(suite.l1Owner)))
	suite.Equal("100", new(uint256.Int).Neg(suite.GetBalanceDiff(suite.l1Owner)).String())
	suite.Equal("1082800000000000", new(uint256.Int).Neg(suite.GetBalanceDiff(suite.sessionAddr)).String())
	suite.Equal("100", suite.GetBalanceDiff(suite.to).String())
}

func (suite *SessionTestSuite) TestSessionUpdateTx() {
	// Create and sign nova session tx
	sessionTxCreate := &types.SessionContext{
		Command: types.SessionCreate,
		Session: types.Session{
			PublicKey: suite.sessionAddr,
			ExpiresAt: 100,
			Metadata:  nil,
		},
		L1Owner:     suite.l1Owner,
		L1Signature: nil, // TODO: fill
	}
	typedData := types.ToTypedData(&sessionTxCreate.Session)
	_, sigHash, _ := types.SignEip712(typedData)
	sig, err := crypto.Sign(sigHash, suite.l1Key)
	suite.Require().NoError(err)
	sessionTxCreate.L1Signature = sig

	sessionTxUpdate := &types.SessionContext{
		Command: types.SessionUpdate,
		Session: types.Session{
			PublicKey: suite.sessionAddr,
			ExpiresAt: 200,
			Metadata:  nil,
		},
		L1Owner:     suite.l1Owner,
		L1Signature: nil, // TODO: fill
	}
	typedData = types.ToTypedData(&sessionTxUpdate.Session)
	_, sigHash, _ = types.SignEip712(typedData)
	sig, err = crypto.Sign(sigHash, suite.l1Key)
	suite.Require().NoError(err)
	sessionTxUpdate.L1Signature = sig

	suite.InsertTxToBlock([]types.Serializable{sessionTxCreate, sessionTxUpdate})

	statedb, _ := suite.chain.State()
	sessions := statedb.GetSessions(suite.l1Owner)
	suite.Equal(1, len(sessions))
	session := &types.SessionContext{}
	err = session.Deserialize(sessions[0])
	suite.T().Log("session", hex.EncodeToString(sessions[0]))
	suite.Require().NoError(err)
	suite.Equal(uint64(200), session.ExpiresAt)
}

func (suite *SessionTestSuite) TestSessionDeleteTx() {
	// Create and sign nova session tx
	sessionTxCreate := &types.SessionContext{
		Command: types.SessionCreate,
		Session: types.Session{
			PublicKey: suite.sessionAddr,
			ExpiresAt: 100,
			Metadata:  nil,
		},
		L1Owner:     suite.l1Owner,
		L1Signature: nil, // TODO: fill
	}

	sessionTxDelete := &types.SessionContext{
		Command: types.SessionDelete,
		Session: types.Session{
			PublicKey: suite.sessionAddr,
		},
		L1Owner:     suite.l1Owner,
		L1Signature: nil, // TODO: fill
	}

	suite.InsertTxToBlock([]types.Serializable{sessionTxCreate, sessionTxDelete})

	statedb, _ := suite.chain.State()
	sessions := statedb.GetSessions(suite.l1Owner)
	suite.Equal(0, len(sessions))
}

func (suite *SessionTestSuite) TestSessionCreateTxExpiresOutdatedSession() {
	var txs []types.Serializable
	for _, expiresAt := range []uint64{10, 40, 25} {
		sessionTx := &types.SessionContext{
			Command: types.SessionCreate,
			Session: types.Session{
				PublicKey: suite.sessionAddr,
				ExpiresAt: expiresAt,
				Metadata:  nil,
			},
			L1Owner:     suite.l1Owner,
			L1Signature: nil,
		}

		typedData := types.ToTypedData(&sessionTx.Session)
		_, sigHash, _ := types.SignEip712(typedData)
		sig, err := crypto.Sign(sigHash, suite.l1Key)
		suite.Require().NoError(err)
		sessionTx.L1Signature = sig

		txs = append(txs, sessionTx)
	}

	nonce := uint64(0)
	// Generate chain with genesis
	db, blocks, _ := core.GenerateChainWithGenesis(suite.genesis, suite.engine, 50, func(i int, gen *core.BlockGen) {
		txAtBlock := map[uint64]types.Serializable{
			5:  txs[0],
			8:  txs[1],
			15: txs[2],
		}
		// +1 because tx should be added after mining previous block
		if tx, ok := txAtBlock[uint64(i)+1]; ok {
			serializedTx, err := types.WrapTxAsInput(tx)
			suite.Require().NoError(err)
			tx := types.NewTransaction(nonce, common.Address{}, big.NewInt(0), 1000000, big.NewInt(25e9), serializedTx)
			signedTx, err := types.SignTx(tx, suite.signer, suite.sessionKey)
			suite.Require().NoError(err)
			gen.AddTx(signedTx)
			nonce++
		}
	})

	// Create blockchain instance
	var err error
	suite.chain, err = core.NewBlockChain(db, nil, suite.chainConfig, suite.genesis, nil, suite.engine, vm.Config{}, nil)
	suite.Require().NoError(err)

	suite.blocks = blocks

	// Insert the generated blocks
	_, err = suite.chain.InsertChain(suite.blocks)
	suite.Require().NoError(err)

	for i := 0; i < len(suite.blocks); i++ {
		block := suite.chain.GetBlockByNumber(uint64(i))
		statedb, err := suite.chain.StateAt(block.Root())
		suite.Require().NoError(err)
		sessions := statedb.GetSessions(suite.l1Owner)
		switch {
		// before tx0: no session
		case i < 5:
			suite.Equal(0, len(sessions), "block %d", i)
		// after tx0: create session with expiry 10.
		case 5 <= i && i < 8:
			suite.Require().Equal(1, len(sessions), "block %d", i)
			session := &types.SessionContext{}
			err := session.Deserialize(sessions[0])
			suite.Require().NoError(err)
			suite.Equal(uint64(10), session.ExpiresAt, "block %d", i)
		// after tx1: create session with expiry 40.
		// tx0's session expires at 10, but it remains in the state until tx2 is executed.
		case 8 <= i && i < 15:
			suite.Require().Equal(2, len(sessions), "block %d", i)
			{
				session := &types.SessionContext{}
				err := session.Deserialize(sessions[0])
				suite.Require().NoError(err)
				suite.Equal(uint64(10), session.ExpiresAt, "block %d", i)
			}
			{
				session := &types.SessionContext{}
				err := session.Deserialize(sessions[1])
				suite.Require().NoError(err)
				suite.Equal(uint64(40), session.ExpiresAt, "block %d", i)
			}

		// after tx2: create session with expiry 25. tx0's session is removed.
		// tx1 and tx2 sessions still remain in the state.
		case i >= 15:
			suite.Require().Equal(2, len(sessions), "block %d", i)
			{
				session := &types.SessionContext{}
				err := session.Deserialize(sessions[0])
				suite.Require().NoError(err)
				suite.Equal(uint64(40), session.ExpiresAt, "block %d", i)
			}
			{
				session := &types.SessionContext{}
				err := session.Deserialize(sessions[1])
				suite.Require().NoError(err)
				suite.Equal(uint64(25), session.ExpiresAt, "block %d", i)
			}
		}
	}
}

func TestSessionSuite(t *testing.T) {
	suite.Run(t, new(SessionTestSuite))
}

func (suite *SessionTestSuite) TestValidate_InvalidSig() {
	sessionTx := &types.SessionContext{
		Command: types.SessionCreate,
		Session: types.Session{
			PublicKey: suite.sessionAddr,
			ExpiresAt: 100,
			Metadata:  nil,
		},
		L1Owner:     suite.l1Owner,
		L1Signature: nil,
	}
	attackerKey, _ := crypto.GenerateKey()
	typedData := types.ToTypedData(&sessionTx.Session)
	_, sigHash, _ := types.SignEip712(typedData)
	sig, err := crypto.Sign(sigHash, attackerKey)
	suite.Require().NoError(err)
	sessionTx.L1Signature = sig

	err = sessionTx.Validate(suite.sessionAddr) // attacker signed the L1Signature.
	suite.Equal("L1Signature is not signed by L1Owner", err.Error())
}

func (suite *SessionTestSuite) TestValidate_ValidSig() {
	sessionTx := &types.SessionContext{
		Command: types.SessionCreate,
		Session: types.Session{
			PublicKey: suite.sessionAddr,
			ExpiresAt: 100,
			Metadata:  nil,
		},
		L1Owner:     suite.l1Owner,
		L1Signature: nil,
	}
	typedData := types.ToTypedData(&sessionTx.Session)
	_, sigHash, _ := types.SignEip712(typedData)
	sig, err := crypto.Sign(sigHash, suite.l1Key)
	suite.Require().NoError(err)

	sessionTx.L1Signature = sig

	err = sessionTx.Validate(suite.sessionAddr)
	if err != nil {
		fmt.Println(err)
	}
	require.Nil(suite.T(), err)
}

func (suite *SessionTestSuite) TestValidate_Replay() {
	sessionTx := &types.SessionContext{
		Command: types.SessionCreate,
		Session: types.Session{
			PublicKey: suite.sessionAddr,
			ExpiresAt: 100,
			Metadata:  nil,
		},
		L1Owner:     suite.l1Owner,
		L1Signature: nil,
	}

	typedData := types.ToTypedData(&sessionTx.Session)
	_, sigHash, _ := types.SignEip712(typedData)
	sig, err := crypto.Sign(sigHash, suite.l1Key)
	suite.Require().NoError(err)
	sessionTx.L1Signature = sig

	attackerKey, _ := crypto.GenerateKey()
	attackerAddr := crypto.PubkeyToAddress(attackerKey.PublicKey)
	err = sessionTx.Validate(attackerAddr) // attacker sent the tx with a replayed session.
	suite.Equal("txSigner is not authorized", err.Error())
}
