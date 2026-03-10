package types

import "github.com/ethereum/go-ethereum/common"

var DexAddress = common.HexToAddress("0xcc")

const (
	DexCommandSession       = byte(0x01)
	DexCommandTransfer      = byte(0x02)
	DexCommandTokenTransfer = byte(0x11)
	DexCommandNew           = byte(0x21)
	DexCommandCancel        = byte(0x22)
	DexCommandCancelAll     = byte(0x23)
	DexCommandModify        = byte(0x24)
	DexCommandStopOrder     = byte(0x25)
	InvalidDexCommand       = byte(0xFF)
)

func IsValidNovaTxType(t byte) bool {
	return t == DexCommandSession || t == DexCommandTransfer || t == DexCommandTokenTransfer || t == DexCommandNew || t == DexCommandCancel || t == DexCommandCancelAll || t == DexCommandModify || t == DexCommandStopOrder
}

type SessionCommandBytes []byte
type ValueTransferCommandBytes = []byte
type TokenTransferCommandBytes = []byte
type OrderCommandBytes = []byte
type CancelCommandBytes = []byte
type CancelAllCommandBytes = []byte

type Serializable interface {
	Serialize() ([]byte, error)
}

func WrapTxAsInput(tx Serializable) ([]byte, error) {
	data, err := tx.Serialize()
	if err != nil {
		return nil, err
	}

	switch tx.(type) {
	case *SessionContext:
		return append([]byte{DexCommandSession}, data...), nil
	case *ValueTransferContext:
		return append([]byte{DexCommandTransfer}, data...), nil
	case *TokenTransferContext:
		return append([]byte{DexCommandTokenTransfer}, data...), nil
	case *OrderContext:
		return append([]byte{DexCommandNew}, data...), nil
	case *CancelContext:
		return append([]byte{DexCommandCancel}, data...), nil
	case *CancelAllContext:
		return append([]byte{DexCommandCancelAll}, data...), nil
	case *ModifyContext:
		return append([]byte{DexCommandModify}, data...), nil
	case *StopOrderContext:
		return append([]byte{DexCommandStopOrder}, data...), nil
	default:
		panic("unknown dex command")
	}
}
