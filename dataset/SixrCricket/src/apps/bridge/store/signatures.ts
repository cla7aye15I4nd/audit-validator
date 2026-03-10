/**
 * @file signatures.ts
 * @notice Signature persistence layer for the Bridge Aggregator
 *
 * This module provides CRUD operations for payload signatures in the SQLite database.
 */

import { getDatabase } from './database';
import { SignatureRow, WatcherSignature } from '../../shared/types';

/**
 * Inserts a new signature into the database
 *
 * @param hash - Payload hash
 * @param watcher - Watcher address
 * @param signature - Signature bytes
 * @throws Error if signature for this hash/watcher combination already exists
 */
export function insertSignature(hash: string, watcher: string, signature: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(`
    INSERT INTO payload_signatures (hash, watcher, signature, received_at)
    VALUES (?, ?, ?, ?)
  `);

  stmt.run(hash, watcher, signature, now);
}

/**
 * Upserts a signature (insert or replace if exists)
 *
 * @param hash - Payload hash
 * @param watcher - Watcher address
 * @param signature - Signature bytes
 * @param tonPublicKey - Optional TON ed25519 public key (hex, 64 chars)
 * @param tonSignature - Optional TON ed25519 signature (hex, 128 chars)
 */
export function upsertSignature(
  hash: string,
  watcher: string,
  signature: string,
  tonPublicKey?: string,
  tonSignature?: string
): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(`
    INSERT INTO payload_signatures (hash, watcher, signature, ton_public_key, ton_signature, received_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(hash, watcher) DO UPDATE SET
      signature = excluded.signature,
      ton_public_key = excluded.ton_public_key,
      ton_signature = excluded.ton_signature,
      received_at = excluded.received_at
  `);

  stmt.run(hash, watcher, signature, tonPublicKey || null, tonSignature || null, now);
}

/**
 * Gets all signatures for a payload hash
 *
 * @param hash - Payload hash
 * @returns Array of signature rows
 */
export function getSignaturesByHash(hash: string): SignatureRow[] {
  const db = getDatabase();
  const stmt = db.prepare('SELECT * FROM payload_signatures WHERE hash = ? ORDER BY received_at ASC');
  const rows = stmt.all(hash);
  return rows as SignatureRow[];
}

/**
 * Gets a specific signature by hash and watcher
 *
 * @param hash - Payload hash
 * @param watcher - Watcher address
 * @returns Signature row or null if not found
 */
export function getSignature(hash: string, watcher: string): SignatureRow | null {
  const db = getDatabase();
  const stmt = db.prepare('SELECT * FROM payload_signatures WHERE hash = ? AND watcher = ?');
  const row = stmt.get(hash, watcher) as SignatureRow | undefined;
  return row ?? null;
}

/**
 * Checks if a signature exists for a hash/watcher combination
 *
 * @param hash - Payload hash
 * @param watcher - Watcher address
 * @returns True if signature exists
 */
export function hasSignature(hash: string, watcher: string): boolean {
  return getSignature(hash, watcher) !== null;
}

/**
 * Gets the count of unique signatures for a payload
 *
 * @param hash - Payload hash
 * @returns Number of unique signatures
 */
export function getSignatureCount(hash: string): number {
  const db = getDatabase();
  const stmt = db.prepare('SELECT COUNT(*) as count FROM payload_signatures WHERE hash = ?');
  const result = stmt.get(hash) as { count: number };
  return result.count;
}

/**
 * Gets all signatures for a payload as WatcherSignature array
 *
 * @param hash - Payload hash
 * @returns Array of watcher signatures
 */
export function getWatcherSignatures(hash: string): WatcherSignature[] {
  const rows = getSignaturesByHash(hash);
  return rows.map((row) => ({
    watcher: row.watcher,
    signature: row.signature,
  }));
}

/**
 * Gets all signatures from a specific watcher
 *
 * @param watcher - Watcher address
 * @param limit - Maximum number of results
 * @returns Array of signature rows
 */
export function getSignaturesByWatcher(watcher: string, limit?: number): SignatureRow[] {
  const db = getDatabase();

  const sql = limit
    ? 'SELECT * FROM payload_signatures WHERE watcher = ? ORDER BY received_at DESC LIMIT ?'
    : 'SELECT * FROM payload_signatures WHERE watcher = ? ORDER BY received_at DESC';

  const stmt = db.prepare(sql);
  const rows = limit ? stmt.all(watcher, limit) : stmt.all(watcher);
  return rows as SignatureRow[];
}

/**
 * Deletes all signatures for a payload
 *
 * @param hash - Payload hash
 */
export function deleteSignaturesByHash(hash: string): void {
  const db = getDatabase();
  const stmt = db.prepare('DELETE FROM payload_signatures WHERE hash = ?');
  stmt.run(hash);
}

/**
 * Deletes a specific signature by hash and watcher
 *
 * @param hash - Payload hash
 * @param watcher - Watcher address
 */
export function deleteSignature(hash: string, watcher: string): void {
  const db = getDatabase();
  const stmt = db.prepare('DELETE FROM payload_signatures WHERE hash = ? AND watcher = ?');
  stmt.run(hash, watcher);
}

/**
 * Gets signature statistics by watcher
 *
 * @returns Array of watcher statistics
 */
export function getSignatureStatsByWatcher(): Array<{
  watcher: string;
  count: number;
  latestSignature: number;
}> {
  const db = getDatabase();

  const stmt = db.prepare(`
    SELECT
      watcher,
      COUNT(*) as count,
      MAX(received_at) as latestSignature
    FROM payload_signatures
    GROUP BY watcher
    ORDER BY count DESC
  `);

  const rows = stmt.all();
  return rows as Array<{
    watcher: string;
    count: number;
    latestSignature: number;
  }>;
}

/**
 * Checks if a payload has reached quorum
 *
 * @param hash - Payload hash
 * @param threshold - Required signature count (default: 2)
 * @returns True if quorum is met
 */
export function hasQuorum(hash: string, threshold: number = 2): boolean {
  return getSignatureCount(hash) >= threshold;
}

/**
 * Gets the count of unique TON signatures for an EVM -> TON payload
 * Only counts signatures that have non-null ton_public_key
 *
 * @param hash - Payload hash
 * @returns Number of unique TON signatures
 */
export function getTonSignatureCount(hash: string): number {
  const db = getDatabase();
  const stmt = db.prepare(
    'SELECT COUNT(DISTINCT ton_public_key) as count FROM payload_signatures WHERE hash = ? AND ton_public_key IS NOT NULL'
  );
  const result = stmt.get(hash) as { count: number };
  return result.count;
}

/**
 * Gets all TON signatures for a payload
 *
 * @param hash - Payload hash
 * @returns Array of signature rows with TON data
 */
export function getTonSignaturesByHash(hash: string): SignatureRow[] {
  const db = getDatabase();
  const stmt = db.prepare(
    'SELECT * FROM payload_signatures WHERE hash = ? AND ton_public_key IS NOT NULL ORDER BY received_at ASC'
  );
  const rows = stmt.all(hash);
  return rows as SignatureRow[];
}

/**
 * Checks if a payload has reached TON signature quorum
 *
 * @param hash - Payload hash
 * @param threshold - Required TON signature count (default: 2)
 * @returns True if TON quorum is met
 */
export function hasTonQuorum(hash: string, threshold: number = 2): boolean {
  return getTonSignatureCount(hash) >= threshold;
}

/**
 * Gets all unique watcher addresses that have signed
 *
 * @returns Array of watcher addresses
 */
export function getAllWatchers(): string[] {
  const db = getDatabase();
  const stmt = db.prepare('SELECT DISTINCT watcher FROM payload_signatures ORDER BY watcher');
  const rows = stmt.all() as Array<{ watcher: string }>;
  return rows.map((row) => row.watcher);
}
