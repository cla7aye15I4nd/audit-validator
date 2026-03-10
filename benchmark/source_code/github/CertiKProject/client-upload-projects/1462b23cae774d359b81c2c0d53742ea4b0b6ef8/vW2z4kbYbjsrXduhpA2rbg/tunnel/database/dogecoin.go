package database

//
// CREATE TABLE IF NOT EXISTS `doge_stxo` (
// `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
// `hash` CHAR(66) NOT NULL,
// `pos` INT UNSIGNED NOT NULL,
// `internal_address` CHAR(42) NOT NULL COMMENT "System internal address",
// `value` VARCHAR(32) NOT NULL,
// `height` INT UNSIGNED NOT NULL,
// `spent_hash` CHAR(66) NOT NULL,
// `spent_pos` INT UNSIGNED NOT NULL,
//
// `table_id` BIGINT UNSIGNED NOT NULL, /* table_id of tasks_doge */
//
// /* if canceled then delete */
// `status` TINYINT NOT NULL DEFAULT 0, /* 1: submitted, 2: executed, 4: broadcast */

type DogeSTXO struct {
	ID              uint64 `db:"id,omitempty"`
	Hash            string `db:"hash"`
	Pos             uint32 `db:"pos"`
	InternalAddress string `db:"internal_address"`
	Value           string `db:"value"`
	Height          uint64 `db:"height"`
	SpentHash       string `db:"spent_hash"`
	SpentPos        uint32 `db:"spent_pos"`
	TableId         uint64 `db:"table_id"`
	Status          uint   `db:"status"`
}
