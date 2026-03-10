/**
 * Migration: Add fee_amount column to payloads table
 *
 * This migration adds support for tracking bridge fees collected during TON->EVM transfers.
 * The vault contract now takes 1% fee automatically before burning.
 */

import Database from 'better-sqlite3';

export function up(db: Database.Database): void {
  console.log('Running migration 009: Add fee_amount column');

  // Add fee_amount column to payloads table
  db.exec(`
    ALTER TABLE payloads
    ADD COLUMN fee_amount TEXT;
  `);

  console.log('✓ Added fee_amount column to payloads table');
}

export function down(db: Database.Database): void {
  console.log('Rolling back migration 009: Remove fee_amount column');

  // SQLite doesn't support DROP COLUMN directly, need to recreate table
  // For simplicity, we'll just document that downgrade is not supported
  throw new Error('Downgrade not supported for migration 009 - fee_amount is integral to vault contract flow');
}
