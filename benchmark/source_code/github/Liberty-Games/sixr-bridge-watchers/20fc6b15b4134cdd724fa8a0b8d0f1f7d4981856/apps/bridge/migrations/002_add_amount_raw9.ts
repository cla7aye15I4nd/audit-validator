/**
 * @file 002_add_amount_raw9.ts
 * @notice Database migration to add amount_raw9 field for TON raw9 values
 *
 * This migration adds amount_raw9 column to the payloads table to store
 * the original TON raw9 amount value, which is needed for accurate burn operations.
 */

import Database from 'better-sqlite3';

/**
 * Applies the migration
 *
 * @param db - Database instance
 */
export function up(db: Database.Database): void {
  console.log('Running migration: 002_add_amount_raw9');

  // SQLite doesn't support ALTER TABLE to add columns after CHECK constraints
  // We need to:
  // 1. Create a new table with the updated schema
  // 2. Copy data from the old table
  // 3. Drop the old table
  // 4. Rename the new table

  db.exec(`
    BEGIN TRANSACTION;

    -- Create new payloads table with amount_raw9 field
    CREATE TABLE IF NOT EXISTS payloads_new (
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

    -- Copy existing data (amount_raw9 will be NULL for old records)
    INSERT INTO payloads_new (
      hash, origin_chain_id, token, recipient, amount, amount_raw9, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      burn_tx_hash, burn_lt, burn_status, burn_timestamp
    )
    SELECT
      hash, origin_chain_id, token, recipient, amount, NULL, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      burn_tx_hash, burn_lt, burn_status, burn_timestamp
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

    COMMIT;
  `);

  console.log('Migration completed: 002_add_amount_raw9');
}

/**
 * Reverts the migration
 *
 * @param db - Database instance
 */
export function down(db: Database.Database): void {
  console.log('Reverting migration: 002_add_amount_raw9');

  db.exec(`
    BEGIN TRANSACTION;

    -- Create old payloads table without amount_raw9 field
    CREATE TABLE IF NOT EXISTS payloads_old (
      hash TEXT PRIMARY KEY,
      origin_chain_id INTEGER NOT NULL,
      token TEXT NOT NULL,
      recipient TEXT NOT NULL,
      amount TEXT NOT NULL,
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

    -- Copy existing data (excluding amount_raw9)
    INSERT INTO payloads_old (
      hash, origin_chain_id, token, recipient, amount, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      burn_tx_hash, burn_lt, burn_status, burn_timestamp
    )
    SELECT
      hash, origin_chain_id, token, recipient, amount, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      burn_tx_hash, burn_lt, burn_status, burn_timestamp
    FROM payloads;

    -- Drop new table
    DROP TABLE payloads;

    -- Rename old table
    ALTER TABLE payloads_old RENAME TO payloads;

    -- Recreate indexes
    CREATE INDEX IF NOT EXISTS idx_payloads_status ON payloads(status);
    CREATE INDEX IF NOT EXISTS idx_payloads_nonce ON payloads(nonce);
    CREATE INDEX IF NOT EXISTS idx_payloads_created_at ON payloads(created_at);
    CREATE INDEX IF NOT EXISTS idx_payloads_burn_status ON payloads(burn_status);

    COMMIT;
  `);

  console.log('Migration reverted: 002_add_amount_raw9');
}
