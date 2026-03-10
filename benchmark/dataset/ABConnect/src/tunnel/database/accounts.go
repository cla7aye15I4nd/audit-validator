package database

import (
	"time"
)

type Account struct {
	Id                   uint64 `db:"id" json:"id"`
	InternalAddress      string `db:"internal_address"`
	Address              string `db:"address" json:"address"`
	InternalBlockchainId uint64 `db:"internal_blockchain_id"`
	BlockchainId         uint64 `db:"blockchain_id"`

	EnableSwap bool `db:"enable_swap"`

	CreatedAt time.Time `db:"created_at" json:"created_at"`
	UpdatedAt time.Time `db:"updated_at" json:"updated_at"`
	SignInfo  *SignInfo `db:"sign_info" json:"sign_info"`
}

func (a Account) TableType() string {
	return TableOfAccounts
}

func (a Account) GetId() uint64 {
	return a.Id
}

func (a Account) GetSignInfo() *SignInfo {
	return a.SignInfo
}

func (a *Account) SetSignInfo(si *SignInfo) {
	a.SignInfo = si
}

func (a *Account) SetUpdatedAt(at time.Time) {
	a.UpdatedAt = at.UTC()
}
