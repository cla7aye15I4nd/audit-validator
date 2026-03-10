package manager

import (
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
)

func (m *Manager) openDatabase() (db.Session, error) {
	return database.OpenDatabase(m.DB.Adapter, m.DB.ConnectionURL)
}
