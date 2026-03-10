/**
 * @file 007_add_ton_multisig_submitter_fields.ts
 * @notice Migration to add TON multisig submitter tracking fields to payloads table
 *
 * This migration adds fields to track TON multisig contract interactions
 * for EVM -> TON mint operations. These fields replace the legacy ton_mint_*
 * fields when using the multisig contract instead of direct minting.
 */

import Database from 'better-sqlite3';

/**
 * Apply migration: Add ton_multisig_* tracking columns
 */
export function up(db: Database.Database): void {
  db.exec(`
    -- Add TON multisig transaction hash (hex string from TON)
    ALTER TABLE payloads ADD COLUMN ton_multisig_tx_hash TEXT;

    -- Add TON multisig logical time (lt)
    ALTER TABLE payloads ADD COLUMN ton_multisig_lt INTEGER;

    -- Add TON multisig timestamp
    ALTER TABLE payloads ADD COLUMN ton_multisig_timestamp INTEGER;

    -- Create index on ton_multisig_tx_hash for faster lookups
    CREATE INDEX IF NOT EXISTS idx_payloads_ton_multisig_tx_hash ON payloads(ton_multisig_tx_hash);
  `);
}

/**
 * Rollback migration: Remove ton_multisig_* columns
 */
export function down(db: Database.Database): void {
  // SQLite doesn't support DROP COLUMN directly in older versions
  // This is a destructive migration - dropping tracking fields means losing history
  db.exec(`
    -- Drop index first
    DROP INDEX IF EXISTS idx_payloads_ton_multisig_tx_hash;

    -- Create temporary table without ton_multisig_* columns
    CREATE TABLE payloads_backup AS SELECT
      hash, origin_chain_id, token, recipient, amount, amount_raw9, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      direction,
      burn_tx_hash, burn_lt, burn_status, burn_timestamp,
      burn_chain_id, burn_block_number, burn_redeem_log_index, burn_transfer_log_index,
      burn_from_address, burn_confirmations,
      ton_recipient, ton_recipient_hash,
      ton_mint_tx_hash, ton_mint_lt, ton_mint_status, ton_mint_error,
      ton_mint_timestamp, ton_mint_attempts, ton_mint_next_retry
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
  `);
}
