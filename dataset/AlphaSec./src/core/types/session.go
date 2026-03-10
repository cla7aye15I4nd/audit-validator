package types

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"slices"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/math"
	"github.com/ethereum/go-ethereum/core/orderbook"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/log"
)

const (
	SessionCreate uint8 = iota + 1
	SessionUpdate
	SessionDelete
)

// core/types/session.go
type Session struct {
	PublicKey common.Address `json:"publickey"`
	ExpiresAt uint64         `json:"expiresAt"` // block number
	Nonce     uint64         `json:"nonce"`
	Metadata  []byte         `json:"metadata,omitempty"`
}

type SessionContext struct {
	Command uint8 `json:"type"` // create, update, delete
	Session
	L1Owner     common.Address `json:"l1owner"`
	L1Signature []byte         `json:"l1signature"`
}

func (s *SessionContext) command() byte        { return DexCommandSession }
func (s *SessionContext) from() common.Address { return s.L1Owner }
func (s *SessionContext) copy() DexCommandData {
	if s == nil {
		return nil
	}
	return &SessionContext{s.Command, *s.Session.Copy(), s.L1Owner, slices.Clone(s.L1Signature)}
}
func (s *SessionContext) Serialize() ([]byte, error) { return encode(s) }
func (s *SessionContext) Deserialize(b []byte) error { return json.Unmarshal(b, s) }
func (s *SessionContext) validate(sender common.Address, statedb BalanceGetter, orderbook orderbook.Dex, checker MarketChecker) error {
	// TODO-Orderbook: remove duplicated codes
	switch s.Command {
	case SessionCreate:
		if s.ExpiresAt == 0 {
			return fmt.Errorf("session create: expiresAt is zero")
		}
		sessionsBytes := statedb.GetSessions(s.L1Owner)
		for _, sessionBytes := range sessionsBytes {
			session := &SessionContext{}
			if err := session.Deserialize(sessionBytes); err != nil {
				log.Error("SessionContext validate: failed to deserialize session", "error", err)
				return err
			}
			if session.PublicKey == s.PublicKey {
				return fmt.Errorf("session create: session already exists")
			}
		}
	case SessionUpdate:
		sessionsBytes := statedb.GetSessions(s.L1Owner)
		found := false
		for _, sessionBytes := range sessionsBytes {
			session := &SessionContext{}
			if err := session.Deserialize(sessionBytes); err != nil {
				log.Error("SessionContext validate: failed to deserialize session", "error", err)
				return err
			}
			if session.PublicKey == s.PublicKey {
				found = true
				if s.ExpiresAt <= session.ExpiresAt {
					return fmt.Errorf("session update: new expiresAt must be greater than existing")
				}
				break
			}
		}
		if !found {
			return fmt.Errorf("session update: session not found")
		}

	case SessionDelete:
		sessionsBytes := statedb.GetSessions(s.L1Owner)
		found := false
		for _, sessionBytes := range sessionsBytes {
			session := &SessionContext{}
			if err := session.Deserialize(sessionBytes); err != nil {
				log.Error("SessionContext validate: failed to deserialize session", "error", err)
				return err
			}
			if session.PublicKey == s.PublicKey {
				found = true
				break
			}
		}
		if !found {
			return fmt.Errorf("session delete: session not found")
		}
	default:
		return fmt.Errorf("session command: unknown command %d", s.Command)
	}

	return s.Validate(sender)
}

// Copy returns a deep-copied session object.
func (s *Session) Copy() *Session {
	if s == nil {
		return nil
	}
	return &Session{
		PublicKey: s.PublicKey,
		ExpiresAt: s.ExpiresAt,
		Nonce:     s.Nonce,
		Metadata:  common.CopyBytes(s.Metadata),
	}
}

func ToTypedData(s *Session) TypedData {
	return TypedData{
		Types: Types{
			"EIP712Domain": []Type{
				{Name: "name", Type: "string"},
				{Name: "version", Type: "string"},
				{Name: "chainId", Type: "uint256"},
				{Name: "verifyingContract", Type: "address"},
			},
			"RegisterSessionWallet": []Type{
				{Name: "sessionWallet", Type: "address"},
				{Name: "expiry", Type: "uint64"},
				{Name: "nonce", Type: "uint64"},
			},
		},
		PrimaryType: "RegisterSessionWallet",
		Domain: TypedDataDomain{
			Name:              "DEXSignTransaction",
			Version:           "1",
			ChainId:           math.NewHexOrDecimal256(1001),
			VerifyingContract: "0x0000000000000000000000000000000000000000",
		},
		Message: TypedDataMessage{
			"sessionWallet": s.PublicKey.Hex(),
			"expiry":        fmt.Sprintf("%d", s.ExpiresAt),
			"nonce":         fmt.Sprintf("%d", s.Nonce),
		},
	}
}

func ToEip712Message(sess *Session) ([]byte, error) {
	typedData := ToTypedData(sess)
	domainSeparator, err := typedData.HashStruct("EIP712Domain", typedData.Domain.Map())
	if err != nil {
		return nil, err
	}
	typedDataHash, err := typedData.HashStruct(typedData.PrimaryType, typedData.Message)
	if err != nil {
		return nil, err
	}
	rawData := []byte(fmt.Sprintf("\x19\x01%s%s", string(domainSeparator), string(typedDataHash)))
	sighash := crypto.Keccak256(rawData)
	return sighash, nil
}

// Validate checks if the session tx is valid:
// 1. txSigner is authorized by L1Owner to send session transactions on behalf of L1Owner.
// 2. L1Signature must be signed by L1Owner.
func (s *SessionContext) Validate(txSigner common.Address) error {
	msg, err := ToEip712Message(&s.Session)
	if err != nil {
		log.Error("SessionContext Validate: failed to generate EIP712 message", "error", err)
		return err
	}

	// (1)
	if txSigner != s.Session.PublicKey {
		log.Warn("SessionContext Validate: unauthorized txSigner", "expected", s.Session.PublicKey.Hex(), "got", txSigner.Hex())
		return fmt.Errorf("txSigner is not authorized")
	}

	sig := s.L1Signature

	if len(msg) != 32 {
		return errors.New("invalid message length")
	}
	if len(sig) != 65 {
		return errors.New("invalid signature length")
	}
	//if sig[64] >= 4 {
	//	return errors.New("invalid signature v value")
	//}

	R, S, _ := decodeSignature(sig)
	V := big.NewInt(int64(sig[64]))
	if V.Uint64() < 27 {
		V.SetUint64(27 + (V.Uint64() % 2)) // V 값을 27 또는 28로 설정
	}

	recovered, err := recoverPlain(common.BytesToHash(msg), R, S, V, true)
	if err != nil {
		log.Error("SessionContext Validate: failed to recover public key from signature", "error", err)
		return err
	}

	if recovered != s.L1Owner {
		log.Warn("SessionContext Validate: L1 signature mismatch", "expected", s.L1Owner.Hex(), "got", recovered.Hex())
		return fmt.Errorf("L1Signature is not signed by L1Owner")
	}

	//// Get the public key from the signature
	//pubkey, err := crypto.Ecrecover(msg, s.L1Signature)
	//if err != nil {
	//	log.Error("SessionContext Validate: failed to recover public key from signature", "error", err)
	//	return err
	//}
	//
	//// Convert public key to address
	//l1MsgSigner := common.BytesToAddress(crypto.Keccak256(pubkey[1:])[12:])
	//
	//// (2)
	//if l1MsgSigner != s.L1Owner {
	//	log.Warn("SessionContext Validate: L1 signature mismatch", "expected", s.L1Owner.Hex(), "got", l1MsgSigner.Hex())
	//	return fmt.Errorf("L1Signature is not signed by L1Owner")
	//}

	return nil
}

func (s *SessionContext) Copy() *SessionContext {
	if s == nil {
		return nil
	}
	return &SessionContext{
		Command:     s.Command,
		Session:     *s.Session.Copy(),
		L1Owner:     s.L1Owner,
		L1Signature: common.CopyBytes(s.L1Signature),
	}
}
