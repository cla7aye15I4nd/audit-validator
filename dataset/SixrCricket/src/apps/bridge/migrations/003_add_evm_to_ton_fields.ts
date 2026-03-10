/**
 * @file 003_add_evm_to_ton_fields.ts
 * @notice Database migration to add EVM -> TON bridge flow support
 *
 * This migration adds fields for:
 * - Bridge direction tracking (TON_TO_EVM vs EVM_TO_TON)
 * - EVM burn proof tracking (chain ID, block, log index, confirmations)
 * - TON recipient tracking (address and hash)
 * - TON mint transaction tracking (tx hash, lt, status, error)
 * - New status values for TON mint flow
 */

import Database from 'better-sqlite3';

/**
 * Applies the migration
 *
 * @param db - Database instance
 */
export function up(db: Database.Database): void {
  console.log('Running migration: 003_add_evm_to_ton_fields');

  // SQLite doesn't support ALTER TABLE for complex changes
  // We need to recreate the table with all new fields

  db.exec(`
    BEGIN TRANSACTION;

    -- Create new payloads table with EVM -> TON fields
    CREATE TABLE IF NOT EXISTS payloads_new (
      hash TEXT PRIMARY KEY,
      origin_chain_id INTEGER NOT NULL,
      token TEXT NOT NULL,
      recipient TEXT NOT NULL,
      amount TEXT NOT NULL,
      amount_raw9 TEXT,
      nonce INTEGER NOT NULL,
      ton_tx_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN (
        'pending', 'ready',
        'burn_pending', 'burn_submitted', 'burn_confirmed',
        'ton_mint_pending', 'ton_mint_submitted', 'ton_mint_confirmed',
        'submitted', 'finalized', 'failed'
      )),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      submitted_tx TEXT,
      error TEXT,
      -- Bridge direction (default TON_TO_EVM for backward compatibility)
      direction TEXT NOT NULL DEFAULT 'TON_TO_EVM' CHECK(direction IN ('TON_TO_EVM', 'EVM_TO_TON')),
      -- TON burn fields (for TON -> EVM flow)
      burn_tx_hash TEXT,
      burn_lt INTEGER,
      burn_status TEXT CHECK(burn_status IN ('pending', 'submitted', 'confirmed', 'failed')),
      burn_timestamp INTEGER,
      -- EVM burn fields (for EVM -> TON flow)
      burn_chain_id INTEGER,
      burn_block_number INTEGER,
      burn_log_index INTEGER,
      burn_confirmations INTEGER,
      -- TON recipient fields (for EVM -> TON flow)
      ton_recipient TEXT,
      ton_recipient_hash TEXT,
      -- TON mint tracking (for EVM -> TON flow)
      ton_mint_tx_hash TEXT,
      ton_mint_lt INTEGER,
      ton_mint_status TEXT,
      ton_mint_error TEXT,
      ton_mint_timestamp INTEGER
    );

    -- Copy existing data (all existing records are TON -> EVM)
    INSERT INTO payloads_new (
      hash, origin_chain_id, token, recipient, amount, amount_raw9, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      direction,
      burn_tx_hash, burn_lt, burn_status, burn_timestamp,
      burn_chain_id, burn_block_number, burn_log_index, burn_confirmations,
      ton_recipient, ton_recipient_hash,
      ton_mint_tx_hash, ton_mint_lt, ton_mint_status, ton_mint_error, ton_mint_timestamp
    )
    SELECT
      hash, origin_chain_id, token, recipient, amount, amount_raw9, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      'TON_TO_EVM',
      burn_tx_hash, burn_lt, burn_status, burn_timestamp,
      NULL, NULL, NULL, NULL,
      NULL, NULL,
      NULL, NULL, NULL, NULL, NULL
    FROM payloads;

    -- Drop old table
    DROP TABLE payloads;

    -- Rename new table
    ALTER TABLE payloads_new RENAME TO payloads;

    -- Recreate indexes
    CREATE INDEX IF NOT EXISTS idx_payloads_status ON payloads(status);
    CREATE INDEX IF NOT EXISTS idx_payloads_nonce ON payloads(nonce);
    CREATE INDEX IF NOT EXISTS idx_payloads_created_at ON payloads(created_at);
    CREATE INDEX IF NOT EXISTS idx_payloads_burn_status ON payloads(burn_status);

    -- New indexes for EVM -> TON flow
    CREATE INDEX IF NOT EXISTS idx_payloads_direction ON payloads(direction);
    CREATE INDEX IF NOT EXISTS idx_payloads_direction_status ON payloads(direction, status);
    CREATE INDEX IF NOT EXISTS idx_payloads_burn_chain_id ON payloads(burn_chain_id);
    CREATE INDEX IF NOT EXISTS idx_payloads_ton_recipient_hash ON payloads(ton_recipient_hash);

    COMMIT;
  `);

  console.log('Migration completed: 003_add_evm_to_ton_fields');
}

/**
 * Reverts the migration
 *
 * @param db - Database instance
 */
export function down(db: Database.Database): void {
  console.log('Reverting migration: 003_add_evm_to_ton_fields');

  db.exec(`
    BEGIN TRANSACTION;

    -- Create old payloads table without EVM -> TON fields
    CREATE TABLE IF NOT EXISTS payloads_old (
      hash TEXT PRIMARY KEY,
      origin_chain_id INTEGER NOT NULL,
      token TEXT NOT NULL,
      recipient TEXT NOT NULL,
      amount TEXT NOT NULL,
      amount_raw9 TEXT,
      nonce INTEGER NOT NULL,
      ton_tx_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('pending', 'ready', 'burn_pending', 'burn_submitted', 'burn_confirmed', 'submitted', 'finalized', 'failed')),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      submitted_tx TEXT,
      error TEXT,
      burn_tx_hash TEXT,
      burn_lt INTEGER,
      burn_status TEXT CHECK(burn_status IN ('pending', 'submitted', 'confirmed', 'failed')),
      burn_timestamp INTEGER
    );

    -- Copy existing data (only TON -> EVM records, discard EVM -> TON)
    INSERT INTO payloads_old (
      hash, origin_chain_id, token, recipient, amount, amount_raw9, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      burn_tx_hash, burn_lt, burn_status, burn_timestamp
    )
    SELECT
      hash, origin_chain_id, token, recipient, amount, amount_raw9, nonce, ton_tx_id,
      CASE
        WHEN status IN ('ton_mint_pending', 'ton_mint_submitted', 'ton_mint_confirmed') THEN 'pending'
        ELSE status
      END,
      created_at, updated_at, submitted_tx, error,
      burn_tx_hash, burn_lt, burn_status, burn_timestamp
    FROM payloads
    WHERE direction = 'TON_TO_EVM';

    -- Drop new table
    DROP TABLE payloads;

    -- Rename old table
    ALTER TABLE payloads_old RENAME TO payloads;

    -- Recreate old indexes
    CREATE INDEX IF NOT EXISTS idx_payloads_status ON payloads(status);
    CREATE INDEX IF NOT EXISTS idx_payloads_nonce ON payloads(nonce);
    CREATE INDEX IF NOT EXISTS idx_payloads_created_at ON payloads(created_at);
    CREATE INDEX IF NOT EXISTS idx_payloads_burn_status ON payloads(burn_status);

    COMMIT;
  `);

  console.log('Migration reverted: 003_add_evm_to_ton_fields');
}
