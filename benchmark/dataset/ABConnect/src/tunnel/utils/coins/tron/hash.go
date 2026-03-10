package tron

import (
	"encoding/hex"
	"encoding/json"

	"github.com/ethereum/go-ethereum/common"
)

const HashLength = 32

type Hash [HashLength]byte

// BytesToHash sets b to hash.
// If b is larger than len(h), b will be cropped from the left.
func BytesToHash(b []byte) Hash {
	var h Hash
	h.SetBytes(b)
	return h
}

func (h Hash) String() string {

	return h.Hex()
}

// Hex converts a hash to a hex string.
func (h Hash) Hex() string { return hex.EncodeToString(h[:]) }

func HexToHash(s string) Hash { return BytesToHash(common.FromHex(s)) }

func (h Hash) MarshalJSON() ([]byte, error) {
	hashStr := h.Hex()
	return json.Marshal(&hashStr)
}

// UnmarshalJSON parses a hash in hex syntax.
func (h *Hash) UnmarshalJSON(input []byte) error {
	var hashStr string
	err := json.Unmarshal(input, &hashStr)
	if err != nil {
		return err
	}

	hb, err := hex.DecodeString(hashStr)
	if err != nil {
		return err
	}
	h.SetBytes(hb)

	return err
}

// SetBytes sets the hash to the value of b.
// If b is larger than len(h), b will be cropped from the left.
func (h *Hash) SetBytes(b []byte) {
	if len(b) > len(h) {
		b = b[len(b)-HashLength:]
	}

	copy(h[HashLength-len(b):], b)
}
