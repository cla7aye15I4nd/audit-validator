package api

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
	errGetInternalError     = 110
	errDirectionAndChain    = 111
	errEmptyArgs            = 112
	errNotFound             = 113

	errDuplicateKey      = 200
	errCalcTotalTransfer = 201

	errInternalAddress = 301

	errServerError = 500
)

var errText = map[uint32]string{
	OK:      "OK",
	Unknown: "Unknown",

	errInvalidAddress:       "invalid address",
	errStringToBigInt:       "value convert to big int error",
	errNotRound:             "please wait for the next round to start",
	errZeroAddress:          "address is zero hex string",
	errLockedLessFee:        "the locked amount is less than the specified fee",
	errNotSupportActionType: "not support action type",
	errConvertNF:            "convert string to NF error",
	errNegative:             "number is neg",
	errInvalidDirection:     "invalid direction",
	errGetInternalError:     "get internal address error",
	errDirectionAndChain:    "direction and chain don't match",
	errEmptyArgs:            "empty args",
	errNotFound:             "args not found",

	errDuplicateKey:      "duplicate key",
	errCalcTotalTransfer: "calc total transfer amount error",

	errInternalAddress: "internal address",

	errServerError: "internal server error",
}

func makeError(err error, skip int) error {
	pc, _, line, ok := runtime.Caller(skip)
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

func Error(err error) error {
	return makeError(err, 2)
}

func ErrorCode(code uint32) error {
	t, ok := errText[code]
	if !ok {
		t = errText[Unknown]
	}

	return status.Errorf(codes.Code(code), "%v", makeError(errors.New(t), 2))
}
