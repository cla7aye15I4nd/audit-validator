package chain

import (
	"errors"
	"strings"
)

type WalletType int

const (
	WalletKMS WalletType = 1 // AWS KMS, database
	WalletRPC WalletType = 2 // node wallet
)

func (w *WalletType) UnmarshalText(text []byte) error {
	if len(text) == 0 {
		return errors.New("no text")
	}
	in := strings.ToLower(string(text))
	if in == "aws" || in == "kms" || in == "awskms" {
		*w = WalletKMS
	} else if in == "rpc" || in == "node" || in == "daemon" {
		*w = WalletRPC
	} else {
		return errors.New("unknown WalletType")
	}
	return nil
}
