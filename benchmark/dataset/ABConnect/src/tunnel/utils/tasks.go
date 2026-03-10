package utils

import (
	"math/big"
	"time"

	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

// tasks status
const (
	TasksStatusOfSubmitted      = 1
	TasksStatusOfExecuted       = 2
	TasksStatusOfCanceled       = 3
	TasksStatusOfBroadcast      = 4
	TasksStatusOfExecutedFailed = 5
)

var TasksStatusText = map[uint]string{
	TasksStatusOfSubmitted:      "Pending",
	TasksStatusOfExecuted:       "Arrived",
	TasksStatusOfCanceled:       "Canceled",
	TasksStatusOfBroadcast:      "Broadcast",
	TasksStatusOfExecutedFailed: "ExecutedFailed",
}

// tasks action type, base on chain
const (
	TasksActionTypeOfNewBridge     = 1 // MainWithdraw ==> user
	TasksActionTypeOfManagerMerge  = 2 // InternalAddress ==> withdrawMainAddress
	TasksActionTypeOfManagerCharge = 3 // MainWithdraw ==> InternalAddress
	TasksActionTypeOfSwap          = 4 // MainWithdraw ==> user, only native token

	TasksActionTypeOfActive             = 5 // active account
	TasksActionTypeOfManagerDelegated   = 6 // Tron
	TasksActionTypeOfManagerUnDelegated = 7 // Tron

	TasksActionTypeOfCold = 8 // withdrawMainAddress ==> ColdAddress
	TasksActionTypeOfFee  = 9 // InternalAddress ==> FeeAddress
)

var TasksActionTypeText = map[uint]string{
	TasksActionTypeOfNewBridge:     "Bridge",
	TasksActionTypeOfManagerMerge:  "Merge",
	TasksActionTypeOfManagerCharge: "Charge",
	TasksActionTypeOfSwap:          "Swap",

	TasksActionTypeOfManagerDelegated:   "Delegated",
	TasksActionTypeOfManagerUnDelegated: "UnDelegated",

	TasksActionTypeOfCold: "Cold",
	TasksActionTypeOfFee:  "Fee",
}

const (
	TableNoNewBridgeHistory = 1
	TableNoManager          = 2
	TableNoTasks            = 3
	TableNoMap              = 4
)

type TaskData struct {
	ScheduleAt time.Time
	From       config.Address
	To         config.Address
	Value      *big.Int
	Data       string
	// GasLimit   uint64
	// GasPrice   *big.Int
	TableNo    uint
	TableId    uint64
	ActionType uint

	BlockchainId uint64
	Asset        string
	AssetId      uint64
}
