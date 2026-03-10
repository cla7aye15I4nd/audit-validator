package key

import (
	"crypto/ecdsa"
	crand "crypto/rand"
	"encoding/hex"
	"fmt"

	dbtcec "github.com/dogecoinw/doged/btcec"

	dbtcutil "github.com/dogecoinw/doged/btcutil"
	dchaincfg "github.com/dogecoinw/doged/chaincfg"
	"github.com/ethereum/go-ethereum/crypto"
)

func CreateNewDogecoinAccount(passphrase string, scryptN, scryptP int) (dbtcutil.Address, []byte, error) {

	privateKeyECDSA, err := ecdsa.GenerateKey(crypto.S256(), crand.Reader)
	if err != nil {
		return nil, nil, err
	}
	defer zeroKey(privateKeyECDSA)

	privateKey, publicKey := dbtcec.PrivKeyFromBytes(privateKeyECDSA.D.Bytes())

	wif, err := dbtcutil.NewWIF(privateKey, &dchaincfg.MainNetParams, false)
	if err != nil {
		return nil, nil, err
	}

	// TODO: remove this
	fmt.Println("Keys: ",
		hex.EncodeToString(privateKey.Serialize()),
		wif.String(),
		hex.EncodeToString(publicKey.SerializeUncompressed()), hex.EncodeToString(publicKey.SerializeCompressed()))

	address, err := dbtcutil.NewAddressPubKeyHash(dbtcutil.Hash160(publicKey.SerializeCompressed()), &dchaincfg.MainNetParams)
	if err != nil {
		return nil, nil, err
	}

	keyjson, err := encryptKey(address.String(), privateKeyECDSA, passphrase, scryptN, scryptP)
	if err != nil {
		return nil, nil, err
	}

	return address, keyjson, nil
}
