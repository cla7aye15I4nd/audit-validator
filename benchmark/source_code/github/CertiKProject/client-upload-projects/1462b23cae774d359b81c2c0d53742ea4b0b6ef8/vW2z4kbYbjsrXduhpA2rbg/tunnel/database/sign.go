package database

import (
	"context"
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	"database/sql/driver"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/kms"
	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
)

type SignInfo struct {
	Signatures [][]byte `json:"signatures"`
}

func (s *SignInfo) Scan(value interface{}) error {
	b, ok := value.([]byte)
	if !ok {
		return errors.New("type assertion to []byte failed")
	}
	if len(b) == 0 {
		return nil
	}
	return json.Unmarshal(b, &s)
}

func (s SignInfo) Value() (driver.Value, error) {
	if len(s.Signatures) == 0 {
		return nil, nil
	}
	j, err := json.Marshal(s)
	if err != nil {
		return nil, err
	}
	return driver.Value(j), nil
}

func Hash(in interface{}) ([]byte, error) {
	inb, err := json.Marshal(in)
	if err != nil {
		return nil, err
	}

	h := sha256.New()
	h.Write(inb)
	return h.Sum(nil), nil
}

func Sign(keyId string, hash []byte) ([]byte, error) {
	ctx := context.Background()
	// Load AWS configuration
	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}

	client := kms.NewFromConfig(cfg)

	params := &kms.SignInput{
		KeyId:            &keyId,
		Message:          hash,
		SigningAlgorithm: "ECDSA_SHA_256",
		MessageType:      "DIGEST",
	}
	vo, err := client.Sign(ctx, params)
	if err != nil {
		return nil, err
	}
	return vo.Signature, nil
}

func VerifyWitKMS(keyId string, hash, signature []byte) bool {
	ctx := context.Background()
	// Load AWS configuration
	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return false
	}
	client := kms.NewFromConfig(cfg)

	params := &kms.VerifyInput{
		KeyId:            &keyId,
		Message:          hash,
		Signature:        signature,
		SigningAlgorithm: "ECDSA_SHA_256",
		MessageType:      "DIGEST",
	}
	vo, err := client.Verify(ctx, params)
	if err != nil {
		return false
	}
	return vo.SignatureValid
}

func VerifyWithPublicKey(pubkey, hash, signature []byte) (bool, error) {
	pubAny, err := x509.ParsePKIXPublicKey(pubkey)
	if err != nil {
		return false, fmt.Errorf("failed to parse public key: %w", err)
	}

	// Assert the key is of type *ecdsa.PublicKey
	pub, ok := pubAny.(*ecdsa.PublicKey)
	if !ok {
		return false, fmt.Errorf("not an ECDSA public key")
	}

	return ecdsa.VerifyASN1(pub, hash, signature), nil
}

type TableSign interface {
	TableType() string
	GetId() uint64
	GetSignInfo() *SignInfo
	SetSignInfo(*SignInfo)
	SetUpdatedAt(time.Time)
}

type TableVerify interface {
	GetSignInfo() *SignInfo
	SetSignInfo(*SignInfo)
}

func UpdateSign(sess db.Session, tableOfType string, lastId uint64, signKeyId string) error {
	var err error

	if lastId == 0 {
		return fmt.Errorf("last insert id zero")
	}

	var s TableSign
	selector := sess.SQL().SelectFrom(tableOfType).Where("id", lastId)
	switch tableOfType {
	case TableOfHistory:
		var lastHistory History
		err = selector.One(&lastHistory)
		s = &lastHistory
	case TableOfTasks:
		var lastTask Task
		err = selector.One(&lastTask)
		s = &lastTask
	case TableOfPairs:
		var lastPair Pair
		err = selector.One(&lastPair)
		s = &lastPair
	case TableOfAccounts:
		var lastAccount Account
		err = selector.One(&lastAccount)
		s = &lastAccount
	}

	if err != nil {
		return err
	}

	if s == nil {
		return fmt.Errorf("no %s table found", tableOfType)
	}

	if s.GetId() != lastId {
		return fmt.Errorf("last history id not match")
	}

	// hash after init SignInfo
	if s.GetSignInfo() == nil || s.GetSignInfo().Signatures == nil {
		s.SetSignInfo(&SignInfo{
			Signatures: make([][]byte, 0),
		})
	}

	updatedAt := time.Unix(time.Now().Unix(), 0).UTC()
	s.SetUpdatedAt(updatedAt)

	lhHash, err := Hash(s)
	signature, err := Sign(signKeyId, lhHash)
	if err != nil {
		return err
	}
	s.SetSignInfo(&SignInfo{Signatures: append(s.GetSignInfo().Signatures, signature)})

	_, err = sess.SQL().Update(tableOfType).Set(
		"sign_info", s.GetSignInfo()).Set(
		"updated_at", updatedAt.UTC().Format(utils.TimeFormat)).Where("id", lastId).Exec()
	if err != nil {
		return err
	}

	return nil
}

func Verify(tv TableVerify, signKeyId string) bool {
	if tv == nil {
		return false
	}
	signInfo := tv.GetSignInfo()
	if signInfo == nil {
		return false
	}
	if signInfo.Signatures == nil || len(signInfo.Signatures) == 0 {
		return false
	}
	if signKeyId == "" {
		return false
	}

	signature := signInfo.Signatures[len(signInfo.Signatures)-1]
	tv.SetSignInfo(&SignInfo{Signatures: signInfo.Signatures[:len(signInfo.Signatures)-1]})

	h, err := Hash(tv)
	if err != nil {
		return false
	}
	tv.SetSignInfo(signInfo)

	return VerifyWitKMS(signKeyId, h, signature)
}
