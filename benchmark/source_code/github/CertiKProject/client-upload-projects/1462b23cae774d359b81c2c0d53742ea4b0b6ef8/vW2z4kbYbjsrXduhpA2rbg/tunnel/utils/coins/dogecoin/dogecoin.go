package dogecoin

import (
	dchaincfg "github.com/dogecoinw/doged/chaincfg"
	dwire "github.com/dogecoinw/doged/wire"
)

// TestNetParams defines the network parameters for the testnet Dogecoin network.
var TestNetParams = dchaincfg.Params{
	Name:        "testnet",
	Net:         dwire.TestNet,
	DefaultPort: "44555",
	DNSSeeds:    []dchaincfg.DNSSeed{},

	/*
		Dogecoin Pubkey: 30
		Dogecoin Script: 22
		Dogecoin Secret Key: 158

		Testnet Pubkey: 113
		Testnet Script: 196
		Testnet Secret Key: 241
	*/

	Bech32HRPSegwit: "doge",

	PubKeyHashAddrID:        0x71, // 113
	ScriptHashAddrID:        0xc4, // 196
	PrivateKeyID:            0xf1, // 241
	WitnessPubKeyHashAddrID: 0x00,
	WitnessScriptHashAddrID: 0x00,

	HDPublicKeyID:  [4]byte{0x02, 0xfa, 0xca, 0xfd},
	HDPrivateKeyID: [4]byte{0x02, 0xfa, 0xc3, 0x98},

	HDCoinType: 3,
}
