package database

import (
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/sirupsen/logrus"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
)

type Task struct {
	Id             uint64    `db:"id" json:"id"`
	From           string    `db:"from" json:"from"`
	To             string    `db:"to" json:"to"`
	Value          string    `db:"value" json:"value"`
	Data           string    `db:"data" json:"data"`
	Asset          string    `db:"asset" json:"asset"`
	AssetId        uint64    `db:"asset_id" json:"asset_id"`
	BlockchainId   uint64    `db:"blockchain_id" json:"blockchain_id"`
	BlockNumber    uint64    `db:"block_number" json:"block_number"`
	BlockTimestamp time.Time `db:"block_timestamp" json:"block_timestamp"`
	TxHash         string    `db:"tx_hash" json:"tx_hash"`
	TxIndex        uint      `db:"tx_index" json:"tx_index"`
	Fee            string    `db:"fee" json:"fee"`

	CreatedAt  time.Time `db:"created_at" json:"created_at"`
	ScheduleAt time.Time `db:"schedule_at" json:"schedule_at"`
	CanceledAt time.Time `db:"canceled_at" json:"canceled_at"`

	Status     uint   `db:"status" json:"status"`
	TableNo    uint   `db:"table_no" json:"table_no"`
	TableId    uint64 `db:"table_id" json:"table_id"`
	ActionType uint   `db:"action_type" json:"action_type"`

	UpdatedAt time.Time `db:"updated_at" json:"updated_at"`
	SignInfo  *SignInfo `db:"sign_info" json:"sign_info" json:"sign_info"`
}

func (t Task) TableType() string {
	return TableOfHistory
}

func (t Task) GetId() uint64 {
	return t.Id
}

func (t Task) GetSignInfo() *SignInfo {
	return t.SignInfo
}

func (t *Task) SetSignInfo(si *SignInfo) {
	t.SignInfo = si
}

func (t *Task) SetUpdatedAt(at time.Time) {
	t.UpdatedAt = at.UTC()
}

func SubmitStrictTasks(tasksDBtx db.Session, tasks []*utils.TaskData, signKeyId string) (err error) {
	if len(tasks) == 0 {
		return nil
	}

	for _, t := range tasks {
		from := t.From
		if from == (common.Address{}) {
			return errors.New("from is zero")
		}

		err = tasksDBtx.SQL().Select("id").From("tasks").Where(
			"from", from.String()).And(
			db.Cond{"action_type": utils.TasksActionTypeOfManagerMerge},
			db.Cond{"action_type": utils.TasksActionTypeOfManagerCharge},
		).And(db.Or(
			db.Cond{"status": utils.TasksStatusOfSubmitted},
			db.Cond{"status": utils.TasksStatusOfBroadcast},
		)).One(&struct {
			Id uint64 `db:"id"`
		}{})
		if err == db.ErrNoMoreRows {

		} else if err != nil {
			return err
		} else {
			logrus.WithFields(logrus.Fields{
				"address": from.String(),
			}).Warnln("pending tasks, please waiting...")
			continue
		}

		err = submitTask(tasksDBtx, t, signKeyId)
		if err != nil {
			return err
		}
	}

	return nil
}

func SubmitTasks(tasksDBtx db.Session, tasks []*utils.TaskData, signKeyId string) (err error) {
	if len(tasks) == 0 {
		return nil
	}

	for _, t := range tasks {
		err = submitTask(tasksDBtx, t, signKeyId)
		if err != nil {
			return err
		}
	}

	return nil
}

func submitTask(tasksDBtx db.Session, t *utils.TaskData, signKeyId string) (err error) {
	from := t.From
	to := t.To
	var fromStr string
	if from != nil {
		fromStr = from.String()
	}
	if to == nil {
		return errors.New("to is zero")
	}

	value := big.NewInt(0)
	if t.Value != nil {
		value.Set(t.Value)
	}
	if value.Cmp(big.NewInt(0)) < 0 {
		return errors.New("value negative")
	}

	tableNo := t.TableNo
	if tableNo == 0 {
		return errors.New("table no is zero")
	}

	tableId := t.TableId
	if tableId == 0 {
		return errors.New("table id is zero")
	}

	scheduleAt := t.ScheduleAt
	data := t.Data

	// if t.XChain != config.Ethereum && t.XChain != config.Dogecoin {
	// 	return errors.New("XChain error")
	// }

	// if t.XChain == config.Dogecoin {
	// 	if data == "" {
	// 		return errors.New("Dogecoin tick error")
	// 	}
	// }

	// if t.ActionType == utils.TasksActionTypeOfManagerMerge // TODO: actionType?
	// insert ignore into tasks
	sqlStr := fmt.Sprintf("insert ignore into tasks "+
		"(`from`, `to`, value, asset, asset_id, blockchain_id, data, schedule_at, status, action_type, table_no, table_id)"+
		" values('%s', '%s', '%s', '%s', %d, %d, '%s', '%s', %d, %d, %d, %d)",
		fromStr, to.String(), value.String(), t.Asset, t.AssetId, t.BlockchainId, data,
		scheduleAt.UTC().Format(utils.TimeFormat), utils.TasksStatusOfSubmitted,
		t.ActionType, tableNo, tableId)

	result, err := tasksDBtx.SQL().Exec(sqlStr)
	if err != nil {
		return err
	}
	if lastId, err := result.LastInsertId(); err != nil {
		return err
	} else if lastId == 0 {
		return errors.New("last insert id is zero")
	} else {
		err = UpdateSign(tasksDBtx, TableOfTasks, uint64(lastId), signKeyId)
		if err != nil {
			return err
		}
	}

	return nil
}
