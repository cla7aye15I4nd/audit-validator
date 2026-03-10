package database

// Addresses NewEscrow addresses
type Addresses struct {
	Address  string `db:"address"`
	KeyJSON  string `db:"keyjson"`
	Password string `db:"password"`
	Name     string `db:"name"`
}
