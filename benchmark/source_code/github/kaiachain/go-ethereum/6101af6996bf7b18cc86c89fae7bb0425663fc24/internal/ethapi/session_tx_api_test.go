package ethapi

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"log"
	"math/big"
	"testing"
	"time"
)

type testSuite struct {
	client      *ethclient.Client
	chainID     *big.Int
	l1Key       *ecdsa.PrivateKey
	l1Owner     common.Address
	sessionAddr common.Address
	sessionKey  *ecdsa.PrivateKey
	to          common.Address
}

func mustKey(hex string) *ecdsa.PrivateKey {
	k, err := crypto.HexToECDSA(hex[2:])
	if err != nil {
		log.Fatal(err)
	}
	return k
}

func waitReceipt(client *ethclient.Client, txHash common.Hash) (*types.Receipt, error) {
	ctx := context.Background()
	for {
		receipt, err := client.TransactionReceipt(ctx, txHash)
		if err == nil {
			return receipt, nil
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func (s *testSuite) printBalances(tag string) {
	ctx := context.Background()
	l1OwnerBal, _ := s.client.BalanceAt(ctx, s.l1Owner, nil)
	fromBal, _ := s.client.BalanceAt(ctx, s.sessionAddr, nil)
	toBal, _ := s.client.BalanceAt(ctx, s.to, nil)
	fmt.Printf("[%s] Balances | l1Owner: %s | from(session): %s | to: %s\n", tag, l1OwnerBal, fromBal, toBal)
}

func setupSuite() *testSuite {
	client, _ := ethclient.Dial("http://localhost:8547")
	chainID, _ := client.NetworkID(context.Background())

	return &testSuite{
		client:      client,
		chainID:     chainID,
		l1Owner:     common.HexToAddress("0x3f1Eae7D46d88F08fc2F8ed27FCb2AB183EB2d0E"),
		l1Key:       mustKey("0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659"),
		sessionAddr: common.HexToAddress("0x5E1497dD1f08C87b2d8FE23e9AAB6c1De833D927"),
		sessionKey:  mustKey("0xdc04c5399f82306ec4b4d654a342f40e2e0620fe39950d967e1e574b32d4dd36"),
		to:          common.HexToAddress("0x46225F4cee2b4A1d506C7f894bb3dAeB21BF1596"),
	}
}

func (s *testSuite) SendValueTransferTx(expectFail bool) {
	s.printBalances("Before ValueTransferContext")

	nonce, _ := s.client.PendingNonceAt(context.Background(), s.sessionAddr)

	vtTx := &types.ValueTransferContext{
		L1Owner: s.l1Owner,
		To:      s.to,
		Value:   big.NewInt(100),
	}
	data, _ := vtTx.Serialize()

	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   s.chainID,
		Nonce:     nonce,
		GasFeeCap: big.NewInt(2e9),
		GasTipCap: big.NewInt(1e9),
		Gas:       10_000_000,
		To:        &common.Address{},
		Data:      append([]byte{types.DexCommandTransfer}, data...),
	})

	signer := types.LatestSignerForChainID(s.chainID)
	signedTx, _ := types.SignTx(tx, signer, s.sessionKey)

	if err := s.client.SendTransaction(context.Background(), signedTx); err != nil {
		if expectFail {
			fmt.Printf("Failed to send ValueTransferContext: %v", err)
			return
		}
		log.Fatalf("Failed to send ValueTransferContext: %v", err)
	}
	fmt.Println("ValueTransferContext sent, waiting for receipt...")

	receipt, _ := waitReceipt(s.client, signedTx.Hash())

	s.printBalances("After ValueTransferContext")

	if expectFail && receipt.Status != 0 {
		log.Fatalf("Expected failure but got success, tx hash: %s", signedTx.Hash().Hex())
	}
	if !expectFail && receipt.Status != 1 {
		log.Fatalf("Expected success but tx failed, tx hash: %s", signedTx.Hash().Hex())
	}

	if expectFail {
		fmt.Println("Correctly failed ValueTransferContext (status 0)", signedTx.Hash().Hex())
	} else {
		fmt.Println("Successfully confirmed ValueTransferContext (status 1)", signedTx.Hash().Hex())
	}
}

func (s *testSuite) SendSessionTx() {
	s.printBalances("Before SessionContext")
	nonce, _ := s.client.PendingNonceAt(context.Background(), s.sessionAddr)
	blockNum, _ := s.client.BlockNumber(context.Background())

	sessionTx := &types.SessionContext{
		Command: types.SessionCreate,
		Session: types.Session{
			PublicKey: s.sessionAddr,
			ExpiresAt: blockNum + 100,
		},
		L1Owner: s.l1Owner,
	}

	typed := types.ToTypedData(&sessionTx.Session)
	_, hash, _ := types.SignEip712(typed)
	sessionTx.L1Signature, _ = crypto.Sign(hash, mustKey("0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659"))

	data, _ := sessionTx.Serialize()

	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   s.chainID,
		Nonce:     nonce,
		GasFeeCap: big.NewInt(2e9),
		GasTipCap: big.NewInt(1e9),
		Gas:       10_000_000,
		To:        &common.Address{},
		Data:      append([]byte{types.DexCommandSession}, data...),
	})

	signer := types.LatestSignerForChainID(s.chainID)
	signedTx, _ := types.SignTx(tx, signer, s.sessionKey)

	if err := s.client.SendTransaction(context.Background(), signedTx); err != nil {
		log.Fatal("Failed to send SessionContext:", err)
	}
	fmt.Println("SessionContext sent, waiting for receipt...")

	receipt, _ := waitReceipt(s.client, signedTx.Hash())

	s.printBalances("After SessionContext")

	if receipt.Status != 1 {
		log.Fatalf("SessionContext failed, tx hash: %s", signedTx.Hash().Hex())
	}
	fmt.Println("SessionContext confirmed!", signedTx.Hash().Hex())
}

func (s *testSuite) SendUpdateSessionTx() {
	s.printBalances("Before UpdateSessionTx")

	nonce, _ := s.client.PendingNonceAt(context.Background(), s.sessionAddr)
	blockNum, _ := s.client.BlockNumber(context.Background())

	// 업데이트용 SessionContext 생성
	sessionTx := &types.SessionContext{
		Command: types.SessionUpdate,
		Session: types.Session{
			PublicKey: s.sessionAddr,
			ExpiresAt: blockNum + 200,
			Metadata:  nil,
		},
		L1Owner: s.l1Owner,
	}

	typedData := types.ToTypedData(&sessionTx.Session)
	_, sigHash, _ := types.SignEip712(typedData)
	sessionTx.L1Signature, _ = crypto.Sign(sigHash, mustKey("0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659"))

	data, _ := sessionTx.Serialize()

	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   s.chainID,
		Nonce:     nonce,
		GasFeeCap: big.NewInt(2e9),
		GasTipCap: big.NewInt(1e9),
		Gas:       10_000_000,
		To:        &common.Address{},
		Data:      append([]byte{types.DexCommandSession}, data...),
	})

	signer := types.LatestSignerForChainID(s.chainID)
	signedTx, _ := types.SignTx(tx, signer, s.sessionKey)

	if err := s.client.SendTransaction(context.Background(), signedTx); err != nil {
		log.Fatal("Failed to send UpdateSessionTx:", err)
	}
	fmt.Println("UpdateSessionTx sent, waiting for receipt...")

	receipt, _ := waitReceipt(s.client, signedTx.Hash())

	s.printBalances("After UpdateSessionTx")

	if receipt.Status != 1 {
		log.Fatalf("UpdateSessionTx failed, tx hash: %s", signedTx.Hash().Hex())
	}
	fmt.Println("UpdateSessionTx confirmed!", signedTx.Hash().Hex())
}

func (s *testSuite) SendDeleteSessionTx() {
	s.printBalances("Before DeleteSessionTx")

	nonce, _ := s.client.PendingNonceAt(context.Background(), s.sessionAddr)

	// 삭제용 SessionContext 생성
	sessionTx := &types.SessionContext{
		Command: types.SessionDelete,
		Session: types.Session{
			PublicKey: s.sessionAddr,
		},
		L1Owner: s.l1Owner,
	}

	typedData := types.ToTypedData(&sessionTx.Session)
	_, sigHash, _ := types.SignEip712(typedData)
	sessionTx.L1Signature, _ = crypto.Sign(sigHash, mustKey("0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659"))

	data, _ := sessionTx.Serialize()

	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   s.chainID,
		Nonce:     nonce,
		GasFeeCap: big.NewInt(2e9),
		GasTipCap: big.NewInt(1e9),
		Gas:       10_000_000,
		To:        &common.Address{},
		Data:      append([]byte{types.DexCommandSession}, data...),
	})

	signer := types.LatestSignerForChainID(s.chainID)
	signedTx, _ := types.SignTx(tx, signer, s.sessionKey)

	if err := s.client.SendTransaction(context.Background(), signedTx); err != nil {
		log.Fatal("Failed to send DeleteSessionTx:", err)
	}
	fmt.Println("DeleteSessionTx sent, waiting for receipt...")

	receipt, _ := waitReceipt(s.client, signedTx.Hash())

	s.printBalances("After DeleteSessionTx")

	if receipt.Status != 1 {
		log.Fatalf("DeleteSessionTx failed, tx hash: %s", signedTx.Hash().Hex())
	}
	fmt.Println("DeleteSessionTx confirmed!", signedTx.Hash().Hex())
}

func TestFullFlow(t *testing.T) {
	//t.Skip()
	suite := setupSuite()
	defer suite.client.Close()

	//1. 세션 등록 안 된 상태에서 실패하는 트랜잭션 보내기
	suite.SendValueTransferTx(true)

	// 2. 세션 등록
	suite.SendSessionTx()

	// 3. 세션 등록 후 다시 시도 → 성공
	suite.SendValueTransferTx(false)

	// 4. 세션 UpdateTx 보내기 (만료시간 갱신)
	suite.SendUpdateSessionTx()

	// 5. 업데이트 후 다시 트랜잭션 보내기 → 성공
	suite.SendValueTransferTx(false)

	// 6. 세션 DeleteTx 보내기
	suite.SendDeleteSessionTx()

	// 7. 삭제 후 다시 트랜잭션 보내기 → 실패 (세션 없으니까)
	suite.SendValueTransferTx(true)
}
