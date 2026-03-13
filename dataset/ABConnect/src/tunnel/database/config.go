package database

import (
	"fmt"
	"time"

	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
)

// tables
const (
	TableOfConfig      = "config"
	TableOfHistory     = "history"
	TableOfAccounts    = "accounts"
	TableOfBlockchains = "blockchains"
	TableOfAssets      = "assets"
	TableOfPairs       = "pairs"
	TableOfTasks       = "tasks"

	TableOfAddresses = "addresses"
)

type Config struct {
	Variable string `db:"variable" json:"variable"`
	Value    string `db:"value" json:"value"`

	CreatedAt time.Time `db:"created_at" json:"created_at"`
	UpdatedAt time.Time `db:"updated_at" json:"updated_at"`
	SignInfo  *SignInfo `db:"sign_info" json:"sign_info"`
}

func (c Config) TableType() string {
	return TableOfConfig
}

func (c Config) GetSignInfo() *SignInfo {
	return c.SignInfo
}

func (c *Config) SetSignInfo(si *SignInfo) {
	c.SignInfo = si
}

func (c *Config) SetUpdatedAt(at time.Time) {
	c.UpdatedAt = at.UTC()
}

func UpdateConfigSign(sess db.Session, variable string, signKeyId string) error {
	var err error

	if variable == "" {
		return fmt.Errorf("variable zero")
	}

	var c Config
	err = sess.SQL().SelectFrom(TableOfConfig).Where("variable", variable).One(&c)
	if err != nil {
		return err
	}

	// hash after init SignInfo
	if c.GetSignInfo() == nil || c.GetSignInfo().Signatures == nil {
		c.SetSignInfo(&SignInfo{
			Signatures: make([][]byte, 0),
		})
	}

	updatedAt := time.Unix(time.Now().Unix(), 0).UTC()
	c.SetUpdatedAt(updatedAt)

	lhHash, err := Hash(c)
	signature, err := Sign(signKeyId, lhHash)
	if err != nil {
		return err
	}
	c.SetSignInfo(&SignInfo{Signatures: append(c.GetSignInfo().Signatures, signature)})

	_, err = sess.SQL().Update(TableOfConfig).Set(
		"sign_info", c.GetSignInfo()).Set(
		"updated_at", updatedAt.UTC().Format(utils.TimeFormat)).Where("variable", variable).Exec()
	if err != nil {
		return err
	}

	return nil
}
