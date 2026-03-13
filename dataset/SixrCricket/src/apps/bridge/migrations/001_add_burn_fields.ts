/**
 * @file 001_add_burn_fields.ts
 * @notice Database migration to add TON burn tracking fields
 *
 * This migration adds burn_tx_hash, burn_lt, burn_status, and burn_timestamp
 * columns to the payloads table, and extends the status CHECK constraint
 * to include new burn-related statuses.
 */

import Database from 'better-sqlite3';

/**
 * Applies the migration
 *
 * @param db - Database instance
 */
export function up(db: Database.Database): void {
  console.log('Running migration: 001_add_burn_fields');

  // SQLite doesn't support ALTER TABLE to add CHECK constraints
  // We need to:
  // 1. Create a new table with the updated schema
  // 2. Copy data from the old table
  // 3. Drop the old table
  // 4. Rename the new table

  db.exec(`
    BEGIN TRANSACTION;

    -- Create new payloads table with burn fields and updated status constraint
    CREATE TABLE IF NOT EXISTS payloads_new (
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

    -- Copy existing data
    INSERT INTO payloads_new (
      hash, origin_chain_id, token, recipient, amount, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      burn_tx_hash, burn_lt, burn_status, burn_timestamp
    )
    SELECT
      hash, origin_chain_id, token, recipient, amount, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      NULL, NULL, NULL, NULL
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

  console.log('Migration completed: 001_add_burn_fields');
}

/**
 * Reverts the migration
 *
 * @param db - Database instance
 */
export function down(db: Database.Database): void {
  console.log('Reverting migration: 001_add_burn_fields');

  db.exec(`
    BEGIN TRANSACTION;

    -- Create old payloads table without burn fields
    CREATE TABLE IF NOT EXISTS payloads_old (
      hash TEXT PRIMARY KEY,
      origin_chain_id INTEGER NOT NULL,
      token TEXT NOT NULL,
      recipient TEXT NOT NULL,
      amount TEXT NOT NULL,
      nonce INTEGER NOT NULL,
      ton_tx_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('pending', 'ready', 'submitted', 'finalized', 'failed')),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      submitted_tx TEXT,
      error TEXT
    );

    -- Copy existing data (excluding burn fields and burn statuses)
    INSERT INTO payloads_old (
      hash, origin_chain_id, token, recipient, amount, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error
    )
    SELECT
      hash, origin_chain_id, token, recipient, amount, nonce, ton_tx_id,
      CASE
        WHEN status IN ('burn_pending', 'burn_submitted', 'burn_confirmed') THEN 'ready'
        ELSE status
      END,
      created_at, updated_at, submitted_tx, error
    FROM payloads
    WHERE status IN ('pending', 'ready', 'burn_pending', 'burn_submitted', 'burn_confirmed', 'submitted', 'finalized', 'failed');

    -- Drop new table
    DROP TABLE payloads;

    -- Rename old table
    ALTER TABLE payloads_old RENAME TO payloads;

    -- Recreate old indexes
    CREATE INDEX IF NOT EXISTS idx_payloads_status ON payloads(status);
    CREATE INDEX IF NOT EXISTS idx_payloads_nonce ON payloads(nonce);
    CREATE INDEX IF NOT EXISTS idx_payloads_created_at ON payloads(created_at);

    COMMIT;
  `);

  console.log('Migration reverted: 001_add_burn_fields');
}
