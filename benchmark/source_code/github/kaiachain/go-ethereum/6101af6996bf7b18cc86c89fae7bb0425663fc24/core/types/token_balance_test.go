package types

import (
	"bytes"
	"encoding/hex"
	"github.com/stretchr/testify/require"
	"sort"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
)

func TestBalanceEntryRLP(t *testing.T) {
	original := &BalanceEntry{
		Token:  "0x1234567890abcdef1234567890abcdef12345678",
		Amount: uint256.NewInt(9876543210),
	}

	// RLP 인코딩
	var buf bytes.Buffer
	err := rlp.Encode(&buf, original)
	assert.NoError(t, err, "EncodeRLP should not error")

	// RLP 디코딩
	decoded := new(BalanceEntry)
	err = rlp.DecodeBytes(buf.Bytes(), decoded)
	assert.NoError(t, err, "DecodeRLP should not error")

	// 결과 비교
	assert.Equal(t, original.Token, decoded.Token, "Address mismatch")
	assert.True(t, original.Amount.Eq(decoded.Amount), "Amount mismatch")
}

func TestBalances_RLPEncodeDecode(t *testing.T) {
	original := NewBalances()
	original.Available["0xaaa"] = uint256.NewInt(1000)
	original.Available["0xbbb"] = uint256.NewInt(2000)
	original.Available["0xccc"] = uint256.NewInt(3000)
	original.Locked = map[string]*uint256.Int{
		"0xaaa": uint256.NewInt(300),
	}

	// Encode
	buf1 := new(bytes.Buffer)
	err := original.EncodeRLP(buf1)
	require.NoError(t, err, "Balances.EncodeRLP failed")

	encoded1 := buf1.Bytes()
	t.Logf("RLP encoded: %x", encoded1)

	// Decode
	var decoded Balances
	err = decoded.DecodeRLP(rlp.NewStream(bytes.NewReader(buf1.Bytes()), 0))
	require.NoError(t, err, "Balances.DecodeRLP failed")

	// Validate Available
	require.Equal(t, len(original.Available), len(decoded.Available), "Available map length mismatch")
	for token, origAmt := range original.Available {
		gotAmt, ok := decoded.Available[token]
		require.True(t, ok, "Missing token %s", token)
		require.Equal(t, origAmt.String(), gotAmt.String(), "Mismatched available for token %s", token)
	}

	// Validate Locked
	require.Equal(t, len(original.Locked), len(decoded.Locked), "Locked map length mismatch")
	for token, origAmt := range original.Locked {
		gotAmt, ok := decoded.Locked[token]
		require.True(t, ok, "Missing locked token %s", token)
		require.Equal(t, origAmt.String(), gotAmt.String(), "Mismatched locked for token %s", token)
	}

	// 5. Re-encode and compare bytes
	var buf2 bytes.Buffer
	err = decoded.EncodeRLP(&buf2)
	require.NoError(t, err)

	encoded2 := buf2.Bytes()
	require.Equal(t, encoded1, encoded2, "RLP encoded bytes should be deterministic")
	t.Logf("RLP encoded: %s", hex.EncodeToString(encoded1))
}

func TestBalanceMap_RLPEncodingIsSorted(t *testing.T) {
	// 만든 키 순서를 바꿔도 결과 RLP는 같아야 함
	keys := []string{
		"0xbbb",
		"0x111",
		"0xaaa",
	}

	original := NewBalances()
	for _, k := range keys {
		original.Available[k] = uint256.NewInt(1)
	}

	var buf bytes.Buffer
	err := original.EncodeRLP(&buf)
	require.NoError(t, err)

	encoded := buf.Bytes()

	// 반복해서 결과가 같게 나오는지 확인
	for i := 0; i < 10; i++ {
		shuffled := NewBalances()
		shuffledKeys := make([]string, len(keys))
		copy(shuffledKeys, keys)
		sort.Slice(shuffledKeys, func(i, j int) bool { return i%2 == 0 }) // 일부러 순서를 흔듦

		for _, k := range shuffledKeys {
			shuffled.Available[k] = uint256.NewInt(1)
		}

		var buf2 bytes.Buffer
		err := shuffled.EncodeRLP(&buf2)
		require.NoError(t, err)
		require.Equal(t, encoded, buf2.Bytes(), "RLP output should be deterministic regardless of map order")
	}
}

func TestStateAccountRLPEncodeDecode_WithBalances(t *testing.T) {
	account := &StateAccount{
		Nonce:   42,
		Balance: uint256.NewInt(0),
		Balances: &Balances{
			Available: map[string]*uint256.Int{
				"0xaaa": uint256.NewInt(1000),
				"0xbbb": uint256.NewInt(2000),
			},
			Locked: map[string]*uint256.Int{
				"0xaaa": uint256.NewInt(300),
			},
		},
		Root:     common.HexToHash("0x1234"),
		CodeHash: []byte{0xde, 0xad, 0xbe, 0xef},
	}

	encoded, err := rlp.EncodeToBytes(account)
	require.NoError(t, err)

	var decoded StateAccount
	err = rlp.DecodeBytes(encoded, &decoded)
	require.NoError(t, err)

	require.Equal(t, account.Nonce, decoded.Nonce)
	require.Equal(t, account.Balance.String(), decoded.Balance.String())
	require.Equal(t, account.Root, decoded.Root)
	require.True(t, bytes.Equal(account.CodeHash, decoded.CodeHash))

	require.NotNil(t, decoded.Balances)
	require.Equal(t, "1000", decoded.Balances.Available["0xaaa"].String())
	require.Equal(t, "2000", decoded.Balances.Available["0xbbb"].String())
	require.Equal(t, "300", decoded.Balances.Locked["0xaaa"].String())
}

func TestSlimAccountRLP_Conversion(t *testing.T) {
	original := &StateAccount{
		Nonce:   7,
		Balance: uint256.NewInt(123),
		Balances: &Balances{
			Available: map[string]*uint256.Int{
				"0x1": uint256.NewInt(500),
			},
			Locked: map[string]*uint256.Int{
				"0x1": uint256.NewInt(100),
			},
		},
		Root:     EmptyRootHash,
		CodeHash: EmptyCodeHash.Bytes(),
	}

	slimEncoded := SlimAccountRLP(*original)

	full, err := FullAccount(slimEncoded)
	require.NoError(t, err)

	require.Equal(t, original.Nonce, full.Nonce)
	require.Equal(t, original.Balance.String(), full.Balance.String())

	require.NotNil(t, full.Balances)
	require.Equal(t, len(original.Balances.Available), len(full.Balances.Available))
	require.Equal(t, len(original.Balances.Locked), len(full.Balances.Locked))

	for token, origAmt := range original.Balances.Available {
		recoveredAmt := full.Balances.Available[token]
		require.Equal(t, origAmt.String(), recoveredAmt.String(), "Available mismatch for %s", token)
	}
	for token, origAmt := range original.Balances.Locked {
		recoveredAmt := full.Balances.Locked[token]
		require.Equal(t, origAmt.String(), recoveredAmt.String(), "Locked mismatch for %s", token)
	}

	require.Equal(t, EmptyRootHash, full.Root)
	require.Equal(t, EmptyCodeHash.Bytes(), full.CodeHash)
}

func TestBalances_LockUnlockConsume(t *testing.T) {
	token := "0xToken1"
	bal := &Balances{
		Available: map[string]*uint256.Int{
			token: uint256.NewInt(100),
		},
		Locked: make(map[string]*uint256.Int),
	}

	amt30 := uint256.NewInt(30)
	amt10 := uint256.NewInt(10)
	amt20 := uint256.NewInt(20)

	// Lock 30
	if err := bal.Lock(token, amt30); err != nil {
		t.Fatalf("Lock failed: %v", err)
	}
	if bal.Available[token].Cmp(uint256.NewInt(70)) != 0 {
		t.Errorf("Available after lock: expected 70, got %s", bal.Available[token].Dec())
	}
	if bal.Locked[token].Cmp(amt30) != 0 {
		t.Errorf("Locked after lock: expected 30, got %s", bal.Locked[token].Dec())
	}

	// Unlock 10
	if err := bal.Unlock(token, amt10); err != nil {
		t.Fatalf("Unlock failed: %v", err)
	}
	if bal.Available[token].Cmp(uint256.NewInt(80)) != 0 {
		t.Errorf("Available after unlock: expected 80, got %s", bal.Available[token].Dec())
	}
	if bal.Locked[token].Cmp(uint256.NewInt(20)) != 0 {
		t.Errorf("Locked after unlock: expected 20, got %s", bal.Locked[token].Dec())
	}

	// Consume 20
	if err := bal.ConsumeLock(token, amt20); err != nil {
		t.Fatalf("ConsumeLock failed: %v", err)
	}
	if bal.Locked[token].Sign() != 0 {
		t.Errorf("Locked after consume: expected 0, got %s", bal.Locked[token].Dec())
	}
}

func TestBalances_Errors(t *testing.T) {
	token := "0xToken2"
	bal := &Balances{
		Available: map[string]*uint256.Int{
			token: uint256.NewInt(10),
		},
		Locked: make(map[string]*uint256.Int),
	}

	tooMuch := uint256.NewInt(999)

	// Lock more than available
	if err := bal.Lock(token, tooMuch); err == nil {
		t.Error("Expected error when locking more than available, got nil")
	}

	// Unlock more than locked
	if err := bal.Unlock(token, uint256.NewInt(1)); err == nil {
		t.Error("Expected error when unlocking more than locked, got nil")
	}

	// Consume more than locked
	if err := bal.ConsumeLock(token, uint256.NewInt(1)); err == nil {
		t.Error("Expected error when consuming more than locked, got nil")
	}
}

func TestBalancesCopy(t *testing.T) {
	// 원본 Balances 생성
	original := NewBalances()
	addr1 := "0x1"
	addr2 := "0x2"

	original.Available[addr1] = uint256.NewInt(100)
	original.Locked[addr2] = uint256.NewInt(200)

	// 복사
	copy := original.Copy()

	// 값이 같은지 확인
	assert.True(t, original.Available[addr1].Eq(copy.Available[addr1]), "Available value should be equal")
	assert.True(t, original.Locked[addr2].Eq(copy.Locked[addr2]), "Locked value should be equal")

	// 깊은 복사 확인 (포인터가 달라야 함)
	assert.NotSame(t, original.Available[addr1], copy.Available[addr1], "Available value should be deep copied")
	assert.NotSame(t, original.Locked[addr2], copy.Locked[addr2], "Locked value should be deep copied")

	// 복사본 수정 후 원본이 영향 받지 않는지 확인
	copy.Available[addr1].Add(copy.Available[addr1], uint256.NewInt(50))
	copy.Locked[addr2].Add(copy.Locked[addr2], uint256.NewInt(50))

	assert.False(t, original.Available[addr1].Eq(copy.Available[addr1]), "Original Available should not be changed")
	assert.False(t, original.Locked[addr2].Eq(copy.Locked[addr2]), "Original Locked should not be changed")
}

func TestBalances_IsEmpty(t *testing.T) {
	t.Run("empty maps", func(t *testing.T) {
		bs := NewBalances()
		require.True(t, bs.IsEmpty(), "IsEmpty should return true for empty maps")
	})

	t.Run("only zero Available balance", func(t *testing.T) {
		bs := NewBalances()
		bs.Available["0xaaa"] = uint256.NewInt(0)
		require.True(t, bs.IsEmpty(), "IsEmpty should return true for zero Available balance")
	})

	t.Run("only zero Locked balance", func(t *testing.T) {
		bs := NewBalances()
		bs.Locked["0xaaa"] = uint256.NewInt(0)
		require.True(t, bs.IsEmpty(), "IsEmpty should return true for zero Locked balance")
	})

	t.Run("non-zero Available balance", func(t *testing.T) {
		bs := NewBalances()
		bs.Available["0xaaa"] = uint256.NewInt(100)
		require.False(t, bs.IsEmpty(), "IsEmpty should return false when Available has non-zero balance")
	})

	t.Run("non-zero Locked balance", func(t *testing.T) {
		bs := NewBalances()
		bs.Locked["0xaaa"] = uint256.NewInt(200)
		require.False(t, bs.IsEmpty(), "IsEmpty should return false when Locked has non-zero balance")
	})

	t.Run("mixed zero and non-zero balances", func(t *testing.T) {
		bs := NewBalances()
		bs.Available["0xaaa"] = uint256.NewInt(0)
		bs.Locked["0xbbb"] = uint256.NewInt(500)
		require.False(t, bs.IsEmpty(), "IsEmpty should return false when any balance is non-zero")
	})
}
