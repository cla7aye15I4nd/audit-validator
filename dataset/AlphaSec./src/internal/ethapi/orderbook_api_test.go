package ethapi

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/holiman/uint256"
	"log"
	"math/big"
	"testing"
	"time"
)

func (s *testSuite) SendOrderTx(sender common.Address, senderKey *ecdsa.PrivateKey, side uint8, orderType uint8, baseToken, quoteToken string, price, quantity *uint256.Int) {
	s.printBalances("Before OrderContext")

	nonce, _ := s.client.PendingNonceAt(context.Background(), sender)

	orderTx := &types.OrderContext{
		L1Owner:    sender,
		BaseToken:  baseToken,
		QuoteToken: quoteToken,
		Side:       side,
		Price:      price.ToBig(),
		Quantity:   quantity.ToBig(),
		OrderType:  orderType,
	}

	data, _ := orderTx.Serialize()

	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   s.chainID,
		Nonce:     nonce,
		GasFeeCap: big.NewInt(2e9),
		GasTipCap: big.NewInt(1e9),
		Gas:       10_000_000,
		To:        &common.Address{},
		Data:      data,
	})

	signer := types.LatestSignerForChainID(s.chainID)
	signedTx, _ := types.SignTx(tx, signer, senderKey)

	if err := s.client.SendTransaction(context.Background(), signedTx); err != nil {
		log.Fatal("Failed to send OrderContext:", err)
	}
	fmt.Println("OrderContext sent, waiting for receipt...")

	receipt, _ := waitReceipt(s.client, signedTx.Hash())

	s.printBalances("After OrderContext")

	if receipt.Status != 1 {
		log.Fatalf("OrderContext failed, tx hash: %s", signedTx.Hash().Hex())
	}
	fmt.Println("OrderContext confirmed!", signedTx.Hash().Hex())
}

func (s *testSuite) SendLongLivedSessionTx() {
	s.printBalances("Before LongLived SessionContext")

	nonce, _ := s.client.PendingNonceAt(context.Background(), s.sessionAddr)
	blockNum, _ := s.client.BlockNumber(context.Background())

	sessionTx := &types.SessionContext{
		Command: types.SessionCreate,
		Session: types.Session{
			PublicKey: s.sessionAddr,
			ExpiresAt: blockNum + 1_000_000, // 100만 블록 뒤 만료
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
		log.Fatal("Failed to send LongLived SessionContext:", err)
	}
	fmt.Println("LongLived SessionContext sent, waiting for receipt...")

	receipt, _ := waitReceipt(s.client, signedTx.Hash())

	s.printBalances("After LongLived SessionContext")

	if receipt.Status != 1 {
		log.Fatalf("LongLived SessionContext failed, tx hash: %s", signedTx.Hash().Hex())
	}
	fmt.Println("LongLived SessionContext confirmed!", signedTx.Hash().Hex())
}

func (s *testSuite) fundNewAccount() (common.Address, *ecdsa.PrivateKey) {
	// 새 키 만들기
	newKey, err := crypto.GenerateKey()
	if err != nil {
		log.Fatal("Failed to generate key:", err)
	}
	newAddr := crypto.PubkeyToAddress(newKey.PublicKey)
	fmt.Println("Generated new account:", newAddr.Hex())

	nonce, _ := s.client.PendingNonceAt(context.Background(), s.l1Owner)

	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   s.chainID,
		Nonce:     nonce,
		GasFeeCap: big.NewInt(2e10),
		GasTipCap: big.NewInt(1e10),
		Gas:       1_500_000,
		To:        &newAddr,
		Value:     big.NewInt(1e18), // 1 ETH
	})

	signer := types.LatestSignerForChainID(s.chainID)
	signedTx, _ := types.SignTx(tx, signer, s.l1Key)

	if err := s.client.SendTransaction(context.Background(), signedTx); err != nil {
		log.Fatal("Failed to fund new account:", err)
	}
	fmt.Println("Funding transaction sent, waiting for receipt...")

	receipt, _ := waitReceipt(s.client, signedTx.Hash())
	if receipt.Status != 1 {
		log.Fatal("Funding transaction failed")
	}
	fmt.Println("New account funded:", newAddr.Hex())

	return newAddr, newKey
}

func TestOrderTxFlow(t *testing.T) {
	t.Skip()
	suite := setupSuite()
	defer suite.client.Close()

	suite.SendLongLivedSessionTx()

	newAddr, newKey := suite.fundNewAccount()

	time.Sleep(3 * time.Second)

	orderTests := []struct {
		side       uint8
		orderType  uint8
		baseToken  string
		quoteToken string
		price      *uint256.Int
		quantity   *uint256.Int
	}{
		{0, 0, "BTC", "USDT", uint256.NewInt(40), uint256.NewInt(1)}, // BUY LIMIT
		{1, 0, "ETH", "USDC", uint256.NewInt(20), uint256.NewInt(2)}, // SELL LIMIT
		{0, 1, "SOL", "KRWO", uint256.NewInt(1), uint256.NewInt(10)}, // BUY MARKET
		{1, 1, "BNB", "USDT", uint256.NewInt(1), uint256.NewInt(5)},  // SELL MARKET

		{0, 0, "ETH", "USDC", uint256.NewInt(25), uint256.NewInt(3)}, // BUY LIMIT (new)
		{1, 0, "SOL", "KRWO", uint256.NewInt(8), uint256.NewInt(7)},  // SELL LIMIT (new)

		{0, 1, "BTC", "KRWO", uint256.NewInt(1), uint256.NewInt(2)}, // BUY MARKET (new)
		{1, 1, "ETH", "USDT", uint256.NewInt(1), uint256.NewInt(1)}, // SELL MARKET (new)

		{0, 0, "BNB", "USDC", uint256.NewInt(10), uint256.NewInt(4)},   // BUY LIMIT
		{1, 0, "KRWO", "USDT", uint256.NewInt(5), uint256.NewInt(100)}, // SELL LIMIT
	}

	for i, test := range orderTests {
		fmt.Printf("Sending OrderContext #%d: %s/%s Side:%d Type:%d\n", i+1, test.baseToken, test.quoteToken, test.side, test.orderType)
		suite.SendOrderTx(
			newAddr, newKey, // 새로운 계정으로
			test.side,
			test.orderType,
			test.baseToken,
			test.quoteToken,
			test.price,
			test.quantity,
		)
	}
}

func (s *testSuite) SendCancelTx(orderId string) {
	s.printBalances("Before CancelContext")

	nonce, _ := s.client.PendingNonceAt(context.Background(), s.sessionAddr)

	cancelTx := &types.CancelContext{
		L1Owner: s.l1Owner, // 세션키 등록돼있으면 l1Owner를 보낼 수 있음
		OrderId: orderId,
	}

	data, _ := cancelTx.Serialize()

	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   s.chainID,
		Nonce:     nonce,
		GasFeeCap: big.NewInt(2e9),
		GasTipCap: big.NewInt(1e9),
		Gas:       10_000_000,
		To:        &common.Address{},
		Data:      data,
	})

	signer := types.LatestSignerForChainID(s.chainID)
	signedTx, _ := types.SignTx(tx, signer, s.sessionKey)

	if err := s.client.SendTransaction(context.Background(), signedTx); err != nil {
		log.Fatal("Failed to send CancelContext:", err)
	}
	fmt.Println("CancelContext sent, waiting for receipt...")

	receipt, _ := waitReceipt(s.client, signedTx.Hash())

	s.printBalances("After CancelContext")

	if receipt.Status != 1 {
		log.Fatalf("CancelContext failed, tx hash: %s", signedTx.Hash().Hex())
	}
	fmt.Println("CancelContext confirmed!", signedTx.Hash().Hex())
}

func TestOrderAndCancel(t *testing.T) {
	t.Skip()
	suite := setupSuite()
	defer suite.client.Close()

	// 1. 세션 등록
	suite.SendLongLivedSessionTx()

	// 2. OrderContext 보내기
	orderTxHash := suite.SendOrderTxAndReturnHash(
		0, // side (BUY)
		0, // orderType (LIMIT)
		"BTC",
		"USDT",
		uint256.NewInt(40),
		uint256.NewInt(1),
	)

	// 3. CancelContext 보내기
	suite.SendCancelTx(orderTxHash.Hex())
}

func (s *testSuite) SendOrderTxAndReturnHash(side uint8, orderType uint8, baseToken, quoteToken string, price, quantity *uint256.Int) common.Hash {
	s.printBalances("Before OrderContext")

	nonce, _ := s.client.PendingNonceAt(context.Background(), s.sessionAddr)

	orderTx := &types.OrderContext{
		L1Owner:    s.l1Owner,
		BaseToken:  baseToken,
		QuoteToken: quoteToken,
		Side:       side,
		Price:      price.ToBig(),
		Quantity:   quantity.ToBig(),
		OrderType:  orderType,
	}

	data, _ := orderTx.Serialize()

	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   s.chainID,
		Nonce:     nonce,
		GasFeeCap: big.NewInt(2e9),
		GasTipCap: big.NewInt(1e9),
		Gas:       10_000_000,
		To:        &common.Address{},
		Data:      data,
	})

	signer := types.LatestSignerForChainID(s.chainID)
	signedTx, _ := types.SignTx(tx, signer, s.sessionKey)

	if err := s.client.SendTransaction(context.Background(), signedTx); err != nil {
		log.Fatal("Failed to send OrderContext:", err)
	}
	fmt.Println("OrderContext sent, waiting for receipt...")

	receipt, _ := waitReceipt(s.client, signedTx.Hash())

	s.printBalances("After OrderContext")

	if receipt.Status != 1 {
		log.Fatalf("OrderContext failed, tx hash: %s", signedTx.Hash().Hex())
	}
	fmt.Println("OrderContext confirmed!", signedTx.Hash().Hex())

	return signedTx.Hash()
}
