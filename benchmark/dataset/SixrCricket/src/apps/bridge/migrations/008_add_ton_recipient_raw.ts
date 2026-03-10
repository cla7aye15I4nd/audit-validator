/**
 * @file 008_add_ton_recipient_raw.ts
 * @notice Migration to add ton_recipient_raw field for storing original user-supplied TON addresses
 *
 * This migration adds the ton_recipient_raw column to store the original TON address
 * as received from burn events (UQ/EQ/raw format), while ton_recipient will always
 * contain the canonical bounceable form (EQ...) used for signatures and multisig operations.
 */

import Database from 'better-sqlite3';

/**
 * Apply migration: Add ton_recipient_raw column
 */
export function up(db: Database.Database): void {
  db.exec(`
    -- Add TON recipient raw address column (stores original format from burn event)
    ALTER TABLE payloads ADD COLUMN ton_recipient_raw TEXT;

    -- Create index on ton_recipient_raw for faster lookups and debugging
    CREATE INDEX IF NOT EXISTS idx_payloads_ton_recipient_raw ON payloads(ton_recipient_raw);
  `);
}

/**
 * Rollback migration: Remove ton_recipient_raw column
 */
export function down(db: Database.Database): void {
  // SQLite doesn't support DROP COLUMN directly in older versions
  // This is a destructive migration - dropping the raw field means losing original address format
  db.exec(`
    -- Drop index first
    DROP INDEX IF EXISTS idx_payloads_ton_recipient_raw;

    -- Create temporary table without ton_recipient_raw column
    CREATE TABLE payloads_backup AS SELECT
      hash, origin_chain_id, token, recipient, amount, amount_raw9, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      direction,
      burn_tx_hash, burn_lt, burn_status, burn_timestamp,
      burn_chain_id, burn_block_number, burn_redeem_log_index, burn_transfer_log_index,
      burn_from_address, burn_confirmations,
      ton_recipient, ton_recipient_hash,
      ton_mint_tx_hash, ton_mint_lt, ton_mint_status, ton_mint_error,
      ton_mint_timestamp, ton_mint_attempts, ton_mint_next_retry,
      ton_multisig_tx_hash, ton_multisig_lt, ton_multisig_timestamp
    FROM payloads;

    -- Drop old table
    DROP TABLE payloads;

    -- Rename backup to original name
    ALTER TABLE payloads_backup RENAME TO payloads;

    -- Recreate indexes
    CREATE INDEX IF NOT EXISTS idx_payloads_status ON payloads(status);
    CREATE INDEX IF NOT EXISTS idx_payloads_nonce ON payloads(nonce);
    CREATE INDEX IF NOT EXISTS idx_payloads_created_at ON payloads(created_at);
    CREATE INDEX IF NOT EXISTS idx_payloads_burn_status ON payloads(burn_status);
    CREATE INDEX IF NOT EXISTS idx_payloads_ton_multisig_tx_hash ON payloads(ton_multisig_tx_hash);
  `);
}
