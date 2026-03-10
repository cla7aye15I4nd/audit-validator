/**
 * @file 005_add_ton_mint_retry_metadata.ts
 * @notice Database migration to add TON mint retry metadata
 *
 * This migration adds fields for tracking retry attempts and next retry timestamp
 * for the TON mint worker (EVM -> TON flow) to implement exponential backoff.
 */

import Database from 'better-sqlite3';

/**
 * Applies the migration
 *
 * @param db - Database instance
 */
export function up(db: Database.Database): void {
  console.log('Running migration: 005_add_ton_mint_retry_metadata');

  // Check if columns already exist (idempotency)
  const tableInfo = db.prepare('PRAGMA table_info(payloads)').all() as Array<{ name: string }>;
  const existingColumns = tableInfo.map((col) => col.name);

  const hasAttempts = existingColumns.includes('ton_mint_attempts');
  const hasNextRetry = existingColumns.includes('ton_mint_next_retry');

  db.exec('BEGIN TRANSACTION;');

  try {
    // Add ton_mint_attempts column if not exists
    if (!hasAttempts) {
      db.exec('ALTER TABLE payloads ADD COLUMN ton_mint_attempts INTEGER DEFAULT 0;');
      console.log('  - Added column: ton_mint_attempts');
    } else {
      console.log('  - Column already exists: ton_mint_attempts (skipping)');
    }

    // Add ton_mint_next_retry column if not exists
    if (!hasNextRetry) {
      db.exec('ALTER TABLE payloads ADD COLUMN ton_mint_next_retry INTEGER NULL;');
      console.log('  - Added column: ton_mint_next_retry');
    } else {
      console.log('  - Column already exists: ton_mint_next_retry (skipping)');
    }

    // Create index for efficient retry queries
    db.exec(`
      CREATE INDEX IF NOT EXISTS idx_payloads_ton_mint_retry
      ON payloads(ton_mint_next_retry, status)
      WHERE ton_mint_next_retry IS NOT NULL;
    `);
    console.log('  - Created index: idx_payloads_ton_mint_retry');

    db.exec('COMMIT;');
    console.log('Migration completed: 005_add_ton_mint_retry_metadata');
  } catch (err) {
    db.exec('ROLLBACK;');
    console.error('Migration failed: 005_add_ton_mint_retry_metadata', err);
    throw err;
  }
}

/**
 * Reverts the migration
 *
 * @param db - Database instance
 */
export function down(db: Database.Database): void {
  console.log('Reverting migration: 005_add_ton_mint_retry_metadata');

  // SQLite doesn't support DROP COLUMN, so we need to recreate the table
  // For simplicity, we'll leave the columns in place but document the revert behavior

  db.exec('BEGIN TRANSACTION;');

  try {
    // Drop the index
    db.exec('DROP INDEX IF EXISTS idx_payloads_ton_mint_retry;');
    console.log('  - Dropped index: idx_payloads_ton_mint_retry');

    // Note: SQLite doesn't support DROP COLUMN without recreating the table
    // In production, you would need to recreate the table to fully revert
    console.log('  - Note: Columns ton_mint_attempts and ton_mint_next_retry remain (SQLite limitation)');
    console.log('  - To fully revert, restore from migration 004 backup');

    db.exec('COMMIT;');
    console.log('Migration reverted: 005_add_ton_mint_retry_metadata');
  } catch (err) {
    db.exec('ROLLBACK;');
    console.error('Migration revert failed: 005_add_ton_mint_retry_metadata', err);
    throw err;
  }
}
