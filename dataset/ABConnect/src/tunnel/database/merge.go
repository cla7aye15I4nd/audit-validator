package database

import (
	"errors"
	"fmt"

	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
)

func LoadFeeAddress(sess db.Session, network, chainId, ToolsSignKeyId string) (string, error) {
	feeName := fmt.Sprintf("%s-%s-%s", network, chainId, utils.FeeAddress)

	var cfg Config
	err := sess.SQL().SelectFrom("config").Where("variable", feeName).One(&cfg)
	if errors.Is(err, db.ErrNoMoreRows) {
		return "", nil
	} else if err != nil {
		fmt.Println(err)
		return "", err
	}

	if !Verify(&cfg, ToolsSignKeyId) {
		return "", fmt.Errorf("verify failed")
	}

	return cfg.Value, nil
}
