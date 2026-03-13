package database

import (
	"errors"

	db "github.com/upper/db/v4"
)

func OpenDatabase(adapterName string, settings db.ConnectionURL) (db.Session, error) {
	if adapterName != "mysql" {
		return nil, errors.New("not support adapter")
	}
	sess, err := db.Open(adapterName, settings)
	if err != nil {
		return nil, err
	}

	_, err = sess.SQL().Exec("set time_zone='+00:00'")
	if err != nil {
		return nil, err
	}
	_, err = sess.SQL().Exec("set transaction_isolation='READ-COMMITTED'")
	if err != nil {
		return nil, err
	}

	return sess, nil
}
