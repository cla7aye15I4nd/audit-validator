package monitor

import (
	"errors"
	"fmt"
	"runtime"
	"strings"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	OK      = 0
	Unknown = 1

	errInvalidAddress       = 101
	errStringToBigInt       = 102
	errNotRound             = 103
	errZeroAddress          = 104
	errLockedLessFee        = 105
	errNotSupportActionType = 106
	errConvertNF            = 107
	errHasPendingLock       = 108
	errStringToHash         = 109
	errXChainUnknown        = 110

	errNegative = 118

	errExistedCandidate   = 201
	errExistedAction      = 202
	errNotSupportNodeType = 203

	errExistedDApp         = 1001
	errNotExistedDApp      = 1002
	errNotSupportOrderUnit = 1003
	errNotRoundAddress     = 1004
	errNotCandidate        = 1005
	errTaxFeeInsufficient  = 1006
	errDAppNFExceeds       = 1007
	errDuplicateSerialNo   = 1008
)

var errText = map[uint32]string{
	OK:      "OK",
	Unknown: "Unknown",

	errInvalidAddress:       "invalid hex-encoded address",
	errStringToBigInt:       "value convert to big int error",
	errNotRound:             "please wait for the next round to start",
	errZeroAddress:          "address is zero hex string",
	errLockedLessFee:        "the locked amount is less than the specified fee",
	errNotSupportActionType: "not support action type",
	errConvertNF:            "convert string to NF error",
	errHasPendingLock:       "there's pending lock",
	errStringToHash:         "string convert to hash error",
	errXChainUnknown:        "xChain unknown",

	errExistedCandidate:   "this account is already a candidate",
	errExistedAction:      "this action has submitted",
	errNotSupportNodeType: "not support node type",

	errExistedDApp:         "existed DApp",
	errNotExistedDApp:      "not existed DApp",
	errNotSupportOrderUnit: "not support order unit",
	errNotRoundAddress:     "not found such address",
	errNotCandidate:        "not candidate address",
	errTaxFeeInsufficient:  "dApp tax account Insufficient",
	errDAppNFExceeds:       "dApp NF Exceeds",
	errDuplicateSerialNo:   "duplicate key for serial no",
}

func Error(err error) error {
	pc, _, line, ok := runtime.Caller(1)
	if !ok {
		line = 0
	}

	name := "???"
	f := runtime.FuncForPC(pc)
	if f != nil {
		name = f.Name()
		nameList := strings.Split(name, ".")
		if nameList != nil && len(nameList) > 0 {
			name = nameList[len(nameList)-1]
		}
	}

	newErr := fmt.Errorf("%s(L%d): %v", name, line, err)

	if s, ok := status.FromError(err); ok {
		newErr = status.Error(s.Code(), err.Error())
	}

	return newErr
}

func ErrorCode(code uint32) error {
	t, ok := errText[code]
	if !ok {
		t = errText[Unknown]
	}

	return status.Errorf(codes.Code(code), "%v", Error(errors.New(t)))
}
