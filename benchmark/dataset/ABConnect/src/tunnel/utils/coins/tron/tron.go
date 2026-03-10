package tron

func GetNetWork() []byte {
	return []byte{0x41}
}

var (
	MainNetGenesisBlockHsh = HexToHash("00000000000000001ebf88508a03865c71d452e25f4d51194196a1d22b6653dc")
	MainNetChainId         = []byte(MainNetGenesisBlockHsh[len(MainNetGenesisBlockHsh)-4:])

	ShastaTestNetGenesisBlockHsh = HexToHash("0000000000000000de1aa88295e1fcf982742f773e0419c5a9c134c994a9059e")
	NileTestNetGenesisBlockHsh   = HexToHash("0000000000000000d698d4192c56cb6be724a558448e2684802de4d6cd8690dc")
)
