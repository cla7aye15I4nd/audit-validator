package chain

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
	errNegative             = 108
	errInvalidDirection     = 109

	errDuplicateKey      = 200
	errCalcTotalTransfer = 201
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
	errNegative:             "number is neg",

	errDuplicateKey:      "duplicate key",
	errCalcTotalTransfer: "calc total transfer amount error",
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
