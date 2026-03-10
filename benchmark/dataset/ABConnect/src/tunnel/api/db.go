package api

import (
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
)

func (t *Tunnel) openDatabase() (db.Session, error) {
	return database.OpenDatabase(t.DB.Adapter, t.DB.ConnectionURL)
}
