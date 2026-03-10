/* database */
create database tunnel;
use tunnel;

/* create user */
create user 'tunnel'@'localhost' identified by 'Weinvent123!!!';

/* Grant */
grant all on tunnel.* to 'tunnel'@'localhost';

/* config */
CREATE TABLE IF NOT EXISTS `config` (
    `variable` varchar(128) NOT NULL PRIMARY KEY,
    `value` VARCHAR(4096),

    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `sign_info` text
)engine=innodb row_format=compressed;

CREATE TABLE IF NOT EXISTS `blockchains` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `network` VARCHAR(32) NOT NULL DEFAULT "",
    `chain_id` VARCHAR(32) NOT NULL DEFAULT "", /* chain id or chain name */
    `base_chain` VARCHAR(32) NOT NULL DEFAULT "", /* Ethereum, Bitcoin, Dogecoin, Newton */

    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, /* TIME Create At */
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `sign_info` text,

    UNIQUE KEY(`network`, `chain_id`)
)engine=innodb row_format=compressed charset=utf8;

CREATE TABLE IF NOT EXISTS `assets` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `blockchain_id` INT UNSIGNED NOT NULL DEFAULT 0,
    `asset` CHAR(128) NOT NULL, /* address of erc20 or name of brc20, empty for native */
    `name` VARCHAR(32) NOT NULL DEFAULT "",
    `symbol` VARCHAR(32) NOT NULL DEFAULT "",
    `decimals` INT UNSIGNED NOT NULL DEFAULT 0,
    `attribute` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT "binary attribute", /* 1: mint 2: burn 4: TBD */
    `asset_type` VARCHAR(32) NOT NULL DEFAULT "",

    UNIQUE KEY (`blockchain_id`, `asset`),
    KEY(`blockchain_id`)
)engine=innodb row_format=compressed charset=utf8;

/* pairs_list */
CREATE TABLE IF NOT EXISTS `pairs` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `asset_a_id` INT UNSIGNED  NOT NULL, /* tokens.id */
    `asset_b_id` INT UNSIGNED NOT NULL, /* tokens.id */

    `asset_a_min_deposit_amount` VARCHAR(32) NOT NULL DEFAULT "",
    `asset_b_min_deposit_amount` VARCHAR(32) NOT NULL DEFAULT "",
    `asset_a_withdraw_fee_percent` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT "percent base is 1000000",
    `asset_b_withdraw_fee_percent` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT "percent base is 1000000",
    `asset_a_withdraw_fee_min` VARCHAR(32) NOT NULL DEFAULT "" COMMENT "in decimals",
    `asset_b_withdraw_fee_min` VARCHAR(32) NOT NULL DEFAULT "" COMMENT "in decimals",
    `asset_a_auto_confirm_deposit_amount` VARCHAR(32) NOT NULL DEFAULT "", /* only work when auto_confirm is true */
    `asset_b_auto_confirm_deposit_amount` VARCHAR(32) NOT NULL DEFAULT "", /* only work when auto_confirm is true */

    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `sign_info` text,

    UNIQUE KEY (`asset_a_id`, `asset_b_id`),
    CHECK (`asset_a_id` < `asset_b_id`)
)engine=innodb row_format=compressed charset=utf8;


/* Accounts */
/*
 * monitor internal_address@internal_blockchain_id deposit withdraw to address@blockchain_id
 * on tokens@
 */
CREATE TABLE IF NOT EXISTS `accounts` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `internal_address` CHAR(42) NOT NULL COMMENT "System internal address",
    `address` CHAR(42) NOT NULL COMMENT "User recipient address",

    `internal_blockchain_id` INT UNSIGNED NOT NULL DEFAULT 0, /* blockchain_id of internal_address */
    `blockchain_id` INT UNSIGNED NOT NULL DEFAULT 0, /* blockchain_id of address */

    /* address + enable_swap => internal address */
    `enable_swap` TINYINT(1) NOT NULL DEFAULT 0 COMMENT "enable asset swap",

    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `sign_info` text,

    /*
     * UNIQUE-KEY: (internal_address + internal_blockchain_id) + (address + blockchain_id)
     * no same address in different blockchain
     */
    UNIQUE KEY (`internal_address`, `address`, `enable_swap`),
    KEY (`internal_blockchain_id`, `internal_address`),
    KEY (`blockchain_id`, `address`)
)engine=innodb row_format=compressed;


/* history */
CREATE TABLE IF NOT EXISTS `history` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `hash` CHAR(66) NOT NULL DEFAULT "", /* "0x" */

    /* basic on-chain info */
    `address` CHAR(128) NOT NULL DEFAULT "", /* internal address, deposit address */
    `blockchain_id` INT UNSIGNED NOT NULL DEFAULT 0,
    `asset` CHAR(128) NOT NULL DEFAULT "", /* contract address for erc20 or name for drc20  */
    `block_number` INT UNSIGNED NOT NULL DEFAULT 0,
    `block_timestamp` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `tx_hash` CHAR(66) NOT NULL DEFAULT "", /* "0x" */
    `tx_index` INT UNSIGNED NOT NULL DEFAULT 0, /* the index inner the deposit hash  */
    `sender` CHAR(128) NOT NULL DEFAULT "", /* sender != tx.from */
    `amount` VARCHAR(128) NOT NULL DEFAULT "", /* QUANTITY */
    /* for tunnel */
    `adjusted_amount` VARCHAR(128) NOT NULL DEFAULT "", /* adjusted_amount / decimal2 = amount / decimal1 */
    `final_amount` VARCHAR(128) NOT NULL DEFAULT "", /* user received amount */
    `fee` VARCHAR(128) NOT NULL DEFAULT "", /* fee = adjusted_amount - final_amount - swap_used_amount */

    `recipient` CHAR(128) NOT NULL DEFAULT "", /* outside address, withdraw_blockchain, maybe not to */
    `target_blockchain_id` INT UNSIGNED NOT NULL DEFAULT 0,
    `target_asset` CHAR(128) NOT NULL DEFAULT "", /* contract address for erc20 or name for drc20  */
    `target_block_number` INT UNSIGNED NOT NULL DEFAULT 0,
    `target_block_timestamp` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `target_tx_hash` CHAR(66) NOT NULL DEFAULT "", /* "0x" */
    `target_tx_index` INT UNSIGNED NOT NULL DEFAULT 0, /* the index inner the deposit hash  */

    /* swap_target_asset must be native token */
    `swap_amount_used` VARCHAR(128) NOT NULL DEFAULT "", /* amount of target_asset used to swap,  */
    `swap_amount` VARCHAR(128) NOT NULL DEFAULT "", /* amount of target_asset get by swap */
    `swap_block_number` INT UNSIGNED NOT NULL DEFAULT 0,
    `swap_block_timestamp` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `swap_tx_hash` CHAR(66) NOT NULL DEFAULT "", /* "0x" */
    `swap_tx_index` INT UNSIGNED NOT NULL DEFAULT 0, /* the index inner the deposit hash  */

    /*
    * DetectedDeposit: detected onchain deposit/transfer
    * DepositSystemConfirmed: after (latest_block_number - block_number >= confirmed_block)
    * DepositConfirmed: final confirm, by human or auto confirmed
    *
    * Settled: convert amount to adjusted_amount and calc final_amount and fee
    *
    * SubmittedWithdrawTasks: submitted to SecureVault to transfer tasks
    * BroadcastWithdrawTransfer:  broadcast withdraw txs to chain
    * WithdrawTransferConfirmed:  withdraw txs onchain confirmed
    *
    * WithdrawSucceed: withdraw is done (WithdrawTransferConfirmed?)
    *
    * Merged: transfer user deposit to main/cold address (in other table)
    *
    */
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 0, /* DetectedDeposit, DepositConfirmed, Withdraw, pendingWithdraw */

    `merge_tx_hash` CHAR(66) NOT NULL DEFAULT "",
    `merge_status` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `fee_tx_hash` CHAR(66) NOT NULL DEFAULT "",
    `fee_status` TINYINT UNSIGNED NOT NULL DEFAULT 0,

    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `sign_info` text,

    UNIQUE KEY (`hash`),
    KEY(`address`),
    KEY(`recipient`),
    KEY(`blockchain_id`, `asset`),
    KEY(`target_blockchain_id`, `target_asset`),
    KEY(`tx_hash`, `tx_index`), /* blockchain? no */
    KEY(`status`)
)engine=innodb row_format=compressed;


/* Tasks, task for wallets */
CREATE TABLE IF NOT EXISTS `tasks` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `from` CHAR(42) NOT NULL,
    `to` CHAR(42) NOT NULL,
    `value` VARCHAR(32) NOT NULL,
    `data` VARCHAR(4096) NOT NULL DEFAULT "",
    `asset` CHAR(128) NOT NULL DEFAULT "",
    `asset_id` INT UNSIGNED  NOT NULL DEFAULT 0, /* asset_id = asset + blockchain_id */
    `blockchain_id` INT UNSIGNED  NOT NULL DEFAULT 0,
    `block_number` INT UNSIGNED NOT NULL DEFAULT 0,
    `block_timestamp` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `tx_hash` CHAR(66) NOT NULL DEFAULT "", /* "0x" */
    `tx_index` INT UNSIGNED NOT NULL DEFAULT 0, /* the index inner the deposit hash  */
    `fee` VARCHAR(32) NOT NULL DEFAULT "", /* onchain gas fee  */
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, /* TIME Create At */
    `canceled_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, /* TIME Canceled At */
    `schedule_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, /* TIME to be executed */
    `status` TINYINT NOT NULL DEFAULT 0, /* 1: submitted, 2: executed, 3: canceled, 4: broadcast */

    /* 0: History 1: Manager */
    `table_no` INT UNSIGNED NOT NULL DEFAULT 0,
    `table_id` BIGINT UNSIGNED NOT NULL,
    /* base on bridge itself:
       Ethereum-Newton:
       1: Bridge 2: manager merge 3: manager charge
       Ethereum-Dogecoin:
       1. Bridge 2: manager merge 3: manager charge 4: FeeTx
    */
    `action_type` INT UNSIGNED NOT NULL DEFAULT 0,

    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `sign_info` text,

    UNIQUE KEY (`table_no`, `table_id`, `action_type`),
    KEY (`asset_id`),
    KEY (`blockchain_id`),
    KEY (`status`)
)engine=innodb row_format=compressed;


CREATE TABLE IF NOT EXISTS `tasks_map` (
    `manager_id` BIGINT UNSIGNED NOT NULL,
    `history_id` BIGINT UNSIGNED NOT NULL,

    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`manager_id`, `history_id`),
    KEY (`history_id`),
    KEY (`manager_id`)
)engine=innodb row_format=compressed;
