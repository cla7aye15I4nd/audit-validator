package utils

import "strings"

const (
	/*
		DetectedDepositOnChain => block-0
		DepositOnChainConfirmed => block-N
		DepositOffChainConfirmed => Human Check (UI)
		// Exchange
		WithdrawPending => tasks
		WithdrawTxSendToChain => broadcast
		WithdrawTxSendToChainConfirmed => block-0 / block-N
		// merge tx balance
		Merge/Used => Main
	*/
	BridgeDetectedDeposit  = 1
	BridgeDeposit          = 2
	BridgeDepositConfirmed = 3 // for auto_confirmed

	BridgePendingWithdraw   = 11
	BridgeWithdraw          = 12
	BridgeWithdrawConfirmed = 13

	BridgeInsufficientBalance     = 15
	BridgeInsufficientPermissions = 16

	BridgeMergedBroadcast = 21
	BridgeMergedConfirmed = 22

	BridgeInternalTx        = 31
	BridgeDirectionDisabled = 32

	BridgeDepositError  = 106
	BridgeExchangeError = 107
	BridgeWithdrawError = 108
)

var BridgeText = map[uint]string{
	BridgeDetectedDeposit:  "DetectedDeposit",
	BridgeDeposit:          "Pending",
	BridgeDepositConfirmed: "DepositConfirmed",

	BridgePendingWithdraw:   "PendingWithdraw",
	BridgeWithdraw:          "WithdrawBroadcast",
	BridgeWithdrawConfirmed: "WithdrawConfirmed",

	BridgeInsufficientBalance:     "InsufficientBalance",
	BridgeInsufficientPermissions: "InsufficientPermissions",

	BridgeMergedBroadcast: "MergedBroadcast",
	BridgeMergedConfirmed: "MergedConfirmed",

	BridgeInternalTx:        "InternalTx",
	BridgeDirectionDisabled: "Disabled",

	BridgeDepositError:  "DepositError",
	BridgeExchangeError: "ExchangeError",
	BridgeWithdrawError: "WithdrawError",
}

func ParseBridgeText(str string) uint {
	for code, text := range BridgeText {
		if strings.ToLower(text) == strings.ToLower(str) {
			return code
		}
	}
	return 0
}

// merge status
const (
	HistoryMergeStatusDefault   = 0
	HistoryMergeStatusSubmitted = TasksStatusOfSubmitted
	HistoryMergeStatusConfirmed = TasksStatusOfExecuted
	HistoryMergeStatusBroadcast = TasksStatusOfBroadcast
)

// fee status
const (
	HistoryFeeStatusDefault   = 0
	HistoryFeeStatusSubmitted = TasksStatusOfSubmitted
	HistoryFeeStatusConfirmed = TasksStatusOfExecuted
	HistoryFeeStatusBroadcast = TasksStatusOfBroadcast
)
