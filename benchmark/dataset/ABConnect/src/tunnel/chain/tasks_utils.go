package chain

import (
	"context"
	"crypto/ecdsa"
	"encoding/base64"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/kms"
	"github.com/ethereum/go-ethereum/accounts/keystore"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

func (x *Chain) getKey(ctx context.Context, address config.Address) (*ecdsa.PrivateKey, error) {
	sdb, err := database.OpenDatabase(x.adapterName, x.settings)
	if err != nil {
		return nil, Error(err)
	}
	defer sdb.Close()

	var a database.Addresses
	err = sdb.SQL().Select("address", "keyjson", "password").From(
		"addresses").Where(
		"address", address.String()).One(&a)
	if err != nil {
		return nil, Error(err)
	}

	// Load AWS configuration
	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		log.Errorln("Failed to load configuration: ", err)
		return nil, Error(err)
	}

	skms := kms.NewFromConfig(cfg)

	sDec, err := base64.StdEncoding.DecodeString(a.Password)
	if err != nil {
		return nil, Error(err)
	}
	resultDe, err := skms.Decrypt(ctx, &kms.DecryptInput{
		CiphertextBlob: sDec,
	})
	if err != nil {
		log.Errorln("Decrypt: ", Error(err))
		return nil, Error(err)
	}

	key, err := keystore.DecryptKey([]byte(a.KeyJSON), string(resultDe.Plaintext))
	if err != nil {
		return nil, Error(err)
	}
	return key.PrivateKey, nil

}

// zeroKey zeroes a private key in memory.
func zeroKey(k *ecdsa.PrivateKey) {
	b := k.D.Bits()
	for i := range b {
		b[i] = 0
	}
}
