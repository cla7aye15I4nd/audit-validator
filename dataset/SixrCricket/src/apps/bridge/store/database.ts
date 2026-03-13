/**
 * @file database.ts
 * @notice SQLite database setup and schema management for the Bridge Aggregator
 *
 * This module initializes the SQLite database with the required schema and
 * provides a singleton database instance for use across the application.
 */

import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import * as migration001 from '../migrations/001_add_burn_fields';
import * as migration002 from '../migrations/002_add_amount_raw9';
import * as migration003 from '../migrations/003_add_evm_to_ton_fields';
import * as migration004 from '../migrations/004_split_burn_log_indexes';
import * as migration005 from '../migrations/005_add_ton_mint_retry_metadata';
import * as migration006 from '../migrations/006_add_ton_multisig_signatures';
import * as migration007 from '../migrations/007_add_ton_multisig_submitter_fields';
import * as migration008 from '../migrations/008_add_ton_recipient_raw';
import * as migration009 from '../migrations/009_add_fee_amount';

/**
 * Database schema SQL
 */
const SCHEMA_SQL = `
-- Payloads table
CREATE TABLE IF NOT EXISTS payloads (
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

-- Index for status queries
CREATE INDEX IF NOT EXISTS idx_payloads_status ON payloads(status);

-- Index for nonce ordering
CREATE INDEX IF NOT EXISTS idx_payloads_nonce ON payloads(nonce);

-- Index for time-based queries
CREATE INDEX IF NOT EXISTS idx_payloads_created_at ON payloads(created_at);

-- Index for burn status queries
CREATE INDEX IF NOT EXISTS idx_payloads_burn_status ON payloads(burn_status);

-- Payload signatures table
CREATE TABLE IF NOT EXISTS payload_signatures (
  hash TEXT NOT NULL,
  watcher TEXT NOT NULL,
  signature TEXT NOT NULL,
  received_at INTEGER NOT NULL,
  PRIMARY KEY (hash, watcher),
  FOREIGN KEY (hash) REFERENCES payloads(hash) ON DELETE CASCADE
);

-- Index for watcher queries
CREATE INDEX IF NOT EXISTS idx_signatures_watcher ON payload_signatures(watcher);

-- Index for hash lookups
CREATE INDEX IF NOT EXISTS idx_signatures_hash ON payload_signatures(hash);

-- Metadata table for configuration and worker state
CREATE TABLE IF NOT EXISTS metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
`;

/**
 * Singleton database instance
 */
let dbInstance: Database.Database | null = null;

/**
 * Database configuration
 */
export interface DatabaseConfig {
  path: string;
  readonly?: boolean;
  verbose?: boolean;
}

/**
 * Initializes the database with schema
 *
 * @param config - Database configuration
 * @returns Database instance
 */
export function initializeDatabase(config: DatabaseConfig): Database.Database {
  if (dbInstance) {
    return dbInstance;
  }

  // Ensure directory exists
  const dir = path.dirname(config.path);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  // Open database
  const options: Database.Options = {};
  if (typeof config.readonly === 'boolean') {
    options.readonly = config.readonly;
  }
  if (config.verbose) {
    options.verbose = console.log;
  }
  const db = new Database(config.path, options);

  // Enable safe integers to prevent precision loss for 64-bit values
  db.defaultSafeIntegers(true);

  // Enable WAL mode for better concurrency
  db.pragma('journal_mode = WAL');

  // Enable foreign keys
  db.pragma('foreign_keys = ON');

  // Create schema if not exists
  db.exec(SCHEMA_SQL);

  dbInstance = db;
  return db;
}

/**
 * Migration configuration
 */
interface Migration {
  id: string;
  up: (db: Database.Database) => void;
  down: (db: Database.Database) => void;
}

/**
 * All migrations in order
 */
const migrations: Migration[] = [
  { id: '001_add_burn_fields', up: migration001.up, down: migration001.down },
  { id: '002_add_amount_raw9', up: migration002.up, down: migration002.down },
  { id: '003_add_evm_to_ton_fields', up: migration003.up, down: migration003.down },
  { id: '004_split_burn_log_indexes', up: migration004.up, down: migration004.down },
  { id: '005_add_ton_mint_retry_metadata', up: migration005.up, down: migration005.down },
  { id: '006_add_ton_multisig_signatures', up: migration006.up, down: migration006.down },
  { id: '007_add_ton_multisig_submitter_fields', up: migration007.up, down: migration007.down },
  { id: '008_add_ton_recipient_raw', up: migration008.up, down: migration008.down },
  { id: '009_add_fee_amount', up: migration009.up, down: migration009.down },
];

/**
 * Runs all pending migrations
 *
 * @param db - Database instance
 */
export function runMigrations(db: Database.Database): void {
  // Create migrations table if it doesn't exist
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id TEXT PRIMARY KEY,
      applied_at INTEGER NOT NULL
    );
  `);

  // Get applied migrations
  const stmt = db.prepare('SELECT id FROM schema_migrations');
  const appliedMigrations = new Set(
    (stmt.all() as Array<{ id: string }>).map((row) => row.id)
  );

  // Run pending migrations
  for (const migration of migrations) {
    if (!appliedMigrations.has(migration.id)) {
      console.log(`Running migration: ${migration.id}`);
      try {
        migration.up(db);

        // Record migration
        const insertStmt = db.prepare(
          'INSERT INTO schema_migrations (id, applied_at) VALUES (?, ?)'
        );
        insertStmt.run(migration.id, Date.now());

        console.log(`Migration completed: ${migration.id}`);
      } catch (err) {
        console.error(`Migration failed: ${migration.id}`, err);
        throw err;
      }
    }
  }
}

/**
 * Gets the database instance
 *
 * @returns Database instance
 * @throws Error if database has not been initialized
 */
export function getDatabase(): Database.Database {
  if (!dbInstance) {
    throw new Error('Database not initialized. Call initializeDatabase() first.');
  }
  return dbInstance;
}

/**
 * Closes the database connection
 */
export function closeDatabase(): void {
  if (dbInstance) {
    dbInstance.close();
    dbInstance = null;
  }
}

/**
 * Executes a query within a transaction
 *
 * @param fn - Function to execute within transaction
 * @returns Result of the function
 */
export function transaction<T>(fn: () => T): T {
  const db = getDatabase();
  const txn = db.transaction(fn);
  return txn();
}

/**
 * Gets a metadata value
 *
 * @param key - Metadata key
 * @returns Metadata value or null if not found
 */
export function getMetadata(key: string): string | null {
  const db = getDatabase();
  const stmt = db.prepare('SELECT value FROM metadata WHERE key = ?');
  const row = stmt.get(key) as { value: string } | undefined;
  return row?.value ?? null;
}

/**
 * Sets a metadata value
 *
 * @param key - Metadata key
 * @param value - Metadata value
 */
export function setMetadata(key: string, value: string): void {
  const db = getDatabase();
  const now = Date.now();
  const stmt = db.prepare(
    'INSERT INTO metadata (key, value, updated_at) VALUES (?, ?, ?) ' +
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at'
  );
  stmt.run(key, value, now);
}

/**
 * Deletes a metadata value
 *
 * @param key - Metadata key
 */
export function deleteMetadata(key: string): void {
  const db = getDatabase();
  const stmt = db.prepare('DELETE FROM metadata WHERE key = ?');
  stmt.run(key);
}

/**
 * Gets database statistics
 *
 * @returns Database statistics
 */
export function getDatabaseStats(): {
  payloadCount: number;
  signatureCount: number;
  metadataCount: number;
  databaseSize: number;
} {
  const db = getDatabase();

  const payloadCount = (
    db.prepare('SELECT COUNT(*) as count FROM payloads').get() as { count: number }
  ).count;

  const signatureCount = (
    db.prepare('SELECT COUNT(*) as count FROM payload_signatures').get() as { count: number }
  ).count;

  const metadataCount = (
    db.prepare('SELECT COUNT(*) as count FROM metadata').get() as { count: number }
  ).count;

  const databaseSize = fs.statSync(getDatabase().name).size;

  return {
    payloadCount,
    signatureCount,
    metadataCount,
    databaseSize,
  };
}

/**
 * Vacuums the database to reclaim space
 */
export function vacuumDatabase(): void {
  const db = getDatabase();
  db.exec('VACUUM');
}

/**
 * Performs a database health check
 *
 * @returns True if database is healthy
 * @throws Error if database check fails
 */
export function checkDatabaseHealth(): boolean {
  const db = getDatabase();

  // Run integrity check
  const result = db.prepare('PRAGMA integrity_check').get() as { integrity_check: string };

  if (result.integrity_check !== 'ok') {
    throw new Error(`Database integrity check failed: ${result.integrity_check}`);
  }

  return true;
}
