/**
 * @file 006_add_ton_multisig_signatures.ts
 * @notice Migration to add TON multisig signature fields to payload_signatures table
 *
 * This migration adds support for TON ed25519 signatures alongside existing EVM signatures.
 * For EVM -> TON flows, watchers will sign with TON ed25519 keys and submit both
 * the TON public key and signature to the bridge aggregator.
 */

import Database from 'better-sqlite3';

/**
 * Apply migration: Add ton_public_key and ton_signature columns
 */
export function up(db: Database.Database): void {
  db.exec(`
    -- Add TON ed25519 public key (64 hex chars = 32 bytes)
    ALTER TABLE payload_signatures ADD COLUMN ton_public_key TEXT;

    -- Add TON ed25519 signature (base64 or hex encoded)
    ALTER TABLE payload_signatures ADD COLUMN ton_signature TEXT;

    -- Create index on ton_public_key for faster lookups
    CREATE INDEX IF NOT EXISTS idx_signatures_ton_public_key ON payload_signatures(ton_public_key);
  `);
}

/**
 * Rollback migration: Remove ton_public_key and ton_signature columns
 */
export function down(db: Database.Database): void {
  // SQLite doesn't support DROP COLUMN directly, need to recreate table
  db.exec(`
    -- Drop index first
    DROP INDEX IF EXISTS idx_signatures_ton_public_key;

    -- Create temporary table without TON signature columns
    CREATE TABLE payload_signatures_backup (
      hash TEXT NOT NULL,
      watcher TEXT NOT NULL,
      signature TEXT NOT NULL,
      received_at INTEGER NOT NULL,
      PRIMARY KEY (hash, watcher),
      FOREIGN KEY (hash) REFERENCES payloads(hash) ON DELETE CASCADE
    );

    -- Copy data
    INSERT INTO payload_signatures_backup (hash, watcher, signature, received_at)
    SELECT hash, watcher, signature, received_at FROM payload_signatures;

    -- Drop old table
    DROP TABLE payload_signatures;

    -- Rename backup to original name
    ALTER TABLE payload_signatures_backup RENAME TO payload_signatures;

    -- Recreate indexes
    CREATE INDEX IF NOT EXISTS idx_signatures_watcher ON payload_signatures(watcher);
    CREATE INDEX IF NOT EXISTS idx_signatures_hash ON payload_signatures(hash);
  `);
}
