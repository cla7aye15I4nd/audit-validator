package utils

import (
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"strings"
)

const HistoryHashSep = ":"

type HistoryHash struct {
	Network string
	ChainId string
	TxHash  string
	TxIndex uint
}

func (h HistoryHash) Hash() []byte {
	input := strings.ToLower(strings.Join([]string{
		h.Network,
		h.ChainId,
		h.TxHash,
		strconv.FormatUint(uint64(h.TxIndex), 10),
	}, HistoryHashSep))

	hash := sha256.Sum256([]byte(input))
	return hash[:]
}

func (h HistoryHash) HashHex() string {
	return hex.EncodeToString(h.Hash())
}

func GetHistoryHash(network, chainId, txHash string, txIndex uint) string {
	return HistoryHash{
		Network: network,
		ChainId: chainId,
		TxHash:  txHash,
		TxIndex: txIndex,
	}.HashHex()
}
