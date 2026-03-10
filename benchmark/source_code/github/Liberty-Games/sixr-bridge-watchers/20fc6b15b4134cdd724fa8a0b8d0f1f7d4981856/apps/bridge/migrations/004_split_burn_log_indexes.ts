/**
 * @file 004_split_burn_log_indexes.ts
 * @notice Database migration to split burn_log_index into separate redeem and transfer indexes
 *
 * This migration implements the Base -> TON burn proof validation fix by:
 * - Renaming burn_log_index to burn_redeem_log_index (for RedeemToTon event)
 * - Adding burn_transfer_log_index (nullable, for Transfer event)
 * - Adding burn_from_address (for tracking the burn originator)
 *
 * Background:
 * EVM transactions generate two logs on MOFT contract:
 * 1. RedeemToTon(address,string,uint256) - with TON recipient
 * 2. ERC-20 Transfer(address,address,uint256) - burn to 0x0
 *
 * Previous implementation expected burn_log_index to point to Transfer log,
 * but watchers were sending RedeemToTon log index, causing validation failures.
 */

import Database from 'better-sqlite3';

/**
 * Applies the migration
 *
 * @param db - Database instance
 */
export function up(db: Database.Database): void {
  console.log('Running migration: 004_split_burn_log_indexes');

  // Check if migration already partially applied
  const tableInfo = db.prepare('PRAGMA table_info(payloads)').all() as Array<{ name: string }>;
  const columnNames = tableInfo.map(col => col.name);

  const hasBurnLogIndex = columnNames.includes('burn_log_index');
  const hasBurnRedeemLogIndex = columnNames.includes('burn_redeem_log_index');
  const hasBurnTransferLogIndex = columnNames.includes('burn_transfer_log_index');
  const hasBurnFromAddress = columnNames.includes('burn_from_address');

  // If already migrated, skip
  if (!hasBurnLogIndex && hasBurnRedeemLogIndex && hasBurnTransferLogIndex && hasBurnFromAddress) {
    console.log('Migration 004 already applied, skipping');
    return;
  }

  db.exec('BEGIN TRANSACTION;');

  try {
    // Step 1: Rename burn_log_index to burn_redeem_log_index
    if (hasBurnLogIndex && !hasBurnRedeemLogIndex) {
      console.log('Renaming burn_log_index → burn_redeem_log_index');
      db.exec('ALTER TABLE payloads RENAME COLUMN burn_log_index TO burn_redeem_log_index;');
    } else if (!hasBurnRedeemLogIndex) {
      console.log('Adding burn_redeem_log_index column');
      db.exec('ALTER TABLE payloads ADD COLUMN burn_redeem_log_index INTEGER;');
    }

    // Step 2: Add burn_transfer_log_index if not exists
    if (!hasBurnTransferLogIndex) {
      console.log('Adding burn_transfer_log_index column');
      db.exec('ALTER TABLE payloads ADD COLUMN burn_transfer_log_index INTEGER;');
    }

    // Step 3: Add burn_from_address if not exists
    if (!hasBurnFromAddress) {
      console.log('Adding burn_from_address column');
      db.exec('ALTER TABLE payloads ADD COLUMN burn_from_address TEXT;');
    }

    // Step 4: Create indexes
    console.log('Creating indexes');
    db.exec(`
      CREATE INDEX IF NOT EXISTS idx_payloads_burn_redeem_log_index ON payloads(burn_redeem_log_index);
      CREATE INDEX IF NOT EXISTS idx_payloads_burn_from_address ON payloads(burn_from_address);
    `);

    db.exec('COMMIT;');
    console.log('Migration completed: 004_split_burn_log_indexes');
  } catch (err) {
    db.exec('ROLLBACK;');
    console.error('Migration 004 failed, rolled back:', err);
    throw err;
  }
}

/**
 * Reverts the migration
 *
 * @param db - Database instance
 */
export function down(db: Database.Database): void {
  console.log('Reverting migration: 004_split_burn_log_indexes');

  // Check current state
  const tableInfo = db.prepare('PRAGMA table_info(payloads)').all() as Array<{ name: string }>;
  const columnNames = tableInfo.map(col => col.name);

  const hasBurnLogIndex = columnNames.includes('burn_log_index');
  const hasBurnRedeemLogIndex = columnNames.includes('burn_redeem_log_index');
  const hasBurnTransferLogIndex = columnNames.includes('burn_transfer_log_index');
  const hasBurnFromAddress = columnNames.includes('burn_from_address');

  // If already reverted, skip
  if (hasBurnLogIndex && !hasBurnRedeemLogIndex && !hasBurnTransferLogIndex && !hasBurnFromAddress) {
    console.log('Migration 004 already reverted, skipping');
    return;
  }

  console.log('WARNING: Down migration requires table recreation. Data in burn_transfer_log_index and burn_from_address will be lost.');

  db.exec('BEGIN TRANSACTION;');

  try {
    // SQLite doesn't support DROP COLUMN directly, so we need to recreate the table
    db.exec(`
      -- Create old payloads table with single burn_log_index
      CREATE TABLE IF NOT EXISTS payloads_old (
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
        direction TEXT NOT NULL DEFAULT 'TON_TO_EVM' CHECK(direction IN ('TON_TO_EVM', 'EVM_TO_TON')),
        burn_tx_hash TEXT,
        burn_lt INTEGER,
        burn_status TEXT CHECK(burn_status IN ('pending', 'submitted', 'confirmed', 'failed')),
        burn_timestamp INTEGER,
        burn_chain_id INTEGER,
        burn_block_number INTEGER,
        burn_log_index INTEGER,
        burn_confirmations INTEGER,
        ton_recipient TEXT,
        ton_recipient_hash TEXT,
        ton_mint_tx_hash TEXT,
        ton_mint_lt INTEGER,
        ton_mint_status TEXT,
        ton_mint_error TEXT,
        ton_mint_timestamp INTEGER
      );

      -- Copy existing data
      -- Use burn_redeem_log_index as burn_log_index, discard burn_transfer_log_index and burn_from_address
      INSERT INTO payloads_old (
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
        direction,
        burn_tx_hash, burn_lt, burn_status, burn_timestamp,
        burn_chain_id, burn_block_number, burn_redeem_log_index, burn_confirmations,
        ton_recipient, ton_recipient_hash,
        ton_mint_tx_hash, ton_mint_lt, ton_mint_status, ton_mint_error, ton_mint_timestamp
      FROM payloads;

      -- Drop new table
      DROP TABLE payloads;

      -- Rename old table
      ALTER TABLE payloads_old RENAME TO payloads;

      -- Recreate old indexes
      CREATE INDEX IF NOT EXISTS idx_payloads_status ON payloads(status);
      CREATE INDEX IF NOT EXISTS idx_payloads_nonce ON payloads(nonce);
      CREATE INDEX IF NOT EXISTS idx_payloads_created_at ON payloads(created_at);
      CREATE INDEX IF NOT EXISTS idx_payloads_burn_status ON payloads(burn_status);
      CREATE INDEX IF NOT EXISTS idx_payloads_direction ON payloads(direction);
      CREATE INDEX IF NOT EXISTS idx_payloads_direction_status ON payloads(direction, status);
      CREATE INDEX IF NOT EXISTS idx_payloads_burn_chain_id ON payloads(burn_chain_id);
      CREATE INDEX IF NOT EXISTS idx_payloads_ton_recipient_hash ON payloads(ton_recipient_hash);
    `);

    db.exec('COMMIT;');
    console.log('Migration reverted: 004_split_burn_log_indexes');
  } catch (err) {
    db.exec('ROLLBACK;');
    console.error('Migration 004 revert failed, rolled back:', err);
    throw err;
  }
}
