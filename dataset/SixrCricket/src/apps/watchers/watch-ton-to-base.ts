/**
 * TON -> Base watcher (Vault Contract Integration) - READ-ONLY + SIGNER
 * - Fetches latest TON events with cursor-based pagination
 * - Uses before_lt for efficient pagination
 * - Fast catch-up even after long downtime
 * - Listens for vault contract BURN events (0x4255524e "BURN")
 * - Vault contract automatically takes 1% fee and burns 99%
 * - Signs payloads and submits to Bridge Aggregator
 * - Bridge Aggregator handles Base mint execution
 * - Watcher does NOT hold TON keys or perform burns (vault does it atomically)
 * - State tracking (lastTs + lastLt + bridge submission status)
 */

import 'dotenv/config';
import * as fs from 'fs';
import * as path from 'path';
import { ethers } from 'ethers';
import Database from 'better-sqlite3';
import { Address, toNano } from '@ton/core';
import {
  buildPayload,
  buildDomain,
  signPayload as signPayloadHelper,
  MINT_PAYLOAD_TYPES,
} from '../shared/payload';
import { MintPayload } from '../shared/types';

/* eslint-disable @typescript-eslint/no-var-requires */
const TonWebLib = require('tonweb');
const TonWeb = TonWebLib.default || TonWebLib;

const fetch = (global as any).fetch ?? require('node-fetch');

// ====== ENV ======
const TON_CHAIN = (process.env.TON_CHAIN || 'mainnet').trim() as 'mainnet' | 'testnet';
const TON_VAULT = (process.env.TON_VAULT || '').trim(); // Vault contract address (smart contract)
const TON_JETTON_ROOT = (process.env.TON_JETTON_ROOT || '').trim();
const TON_JETTON_ROOT_RAW = (process.env.TON_JETTON_ROOT_RAW || '').trim();
const TONCENTER_API_KEY = (process.env.TONCENTER_API_KEY || '').trim();

const PRIVATE_KEY = (process.env.PRIVATE_KEY || '').trim();
const OFT_CONTRACT_ADDRESS = (process.env.OFT_CONTRACT_ADDRESS || '').trim();
const REQUIRE_MEMO_RECIPIENT = String(process.env.REQUIRE_MEMO_RECIPIENT || 'true') === 'true';

// Bridge Aggregator configuration
const BRIDGE_URL = (process.env.BRIDGE_URL || 'http://localhost:3000').trim();
const BRIDGE_API_KEY = (process.env.BRIDGE_API_KEY || '').trim();
const BRIDGE_TIMEOUT_MS = parseInt(process.env.BRIDGE_TIMEOUT_MS || '5000', 10);
const MULTISIG_ADDRESS = (process.env.MULTISIG_ADDRESS || '').trim();
const ORIGIN_CHAIN_ID = parseInt(process.env.ORIGIN_CHAIN_ID || '0', 10);
const DESTINATION_CHAIN_ID = parseInt(process.env.DESTINATION_CHAIN_ID || '8453', 10); // Base mainnet
const TOKEN_DECIMALS = parseInt(process.env.TOKEN_DECIMALS || '18', 10);

const POLL_INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS || '12000', 10);
const CONFIRMATIONS_DELAY_S = parseInt(process.env.CONFIRMATIONS_DELAY_S || '15', 10);
const EVENTS_PER_PAGE = parseInt(process.env.EVENTS_PER_PAGE || '100', 10);
const MAX_PAGES = parseInt(process.env.MAX_PAGES || '20', 10);

// ====== DATABASE ======
const DATA_DIR = process.env.DATA_DIR || process.cwd();
const DB_FILE = path.join(DATA_DIR, 'ton-to-base-watcher.db');
const ADDRESS_MAP_FILE = path.join(DATA_DIR, '.ton-evm-addresses.json'); // Keep for backwards compat

// ====== CONSTANTS ======
const TON_BASE = TON_CHAIN === 'testnet' ? 'https://testnet.tonapi.io' : 'https://tonapi.io';
const TON_EXPLORER = TON_CHAIN === 'testnet' ? 'https://testnet.tonviewer.com' : 'https://tonviewer.com';

const VAULT_CONTRACT_RAW_EXPECTED = (() => {
  try {
    return toRaw(TON_VAULT);
  } catch {
    return TON_VAULT;
  }
})();
const JETTON_RAW_EXPECTED = (() => {
  if (TON_JETTON_ROOT_RAW) return TON_JETTON_ROOT_RAW;
  try {
    return toRaw(TON_JETTON_ROOT);
  } catch {
    return TON_JETTON_ROOT;
  }
})();

let cachedVaultJettonWallet: Address | null = null;

/**
 * Generates deterministic nonce from TON logical time and action index
 * This ensures all watchers generate the same nonce for the same TON event
 *
 * Formula: (lt * 1000) + actionIndex
 * - Multiplying by 1000 leaves room for up to 1000 actions per event
 * - Action index ensures uniqueness within a single event
 *
 * IMPORTANT: Uses BigInt arithmetic to avoid precision loss with large TON lt values.
 * TON lt values can exceed 1e13, and multiplying by 1000 exceeds Number.MAX_SAFE_INTEGER,
 * causing silent rounding errors and different hashes between watchers.
 *
 * @param tonLt - TON logical time from event
 * @param actionIndex - Index of action in event's action array
 * @returns Deterministic nonce as string (fits in uint64)
 */
function generateDeterministicNonce(tonLt: number, actionIndex: number): string {
  // Use BigInt to prevent precision loss with large lt values
  const nonce = BigInt(tonLt) * 1000n + BigInt(actionIndex);

  // Validate nonce fits in uint64 (max value: 2^64 - 1)
  const MAX_UINT64 = BigInt('18446744073709551615');
  if (nonce > MAX_UINT64) {
    throw new Error(`Nonce ${nonce.toString()} exceeds uint64 maximum`);
  }

  // Return as string to preserve precision when passing to ethers
  return nonce.toString();
}

console.log('VAULT_CONTRACT_RAW_EXPECTED:', VAULT_CONTRACT_RAW_EXPECTED);
console.log('JETTON_RAW_EXPECTED:', JETTON_RAW_EXPECTED);

function toRaw(addr: string): string {
  return Address.parse(addr).toRawString();
}

function isHexEvm(addr?: string | null): addr is string {
  return !!addr && /^0x[0-9a-fA-F]{40}$/.test(addr);
}

function formatTokenAmount(raw9: string | bigint, decimals = 9): string {
  const n = typeof raw9 === 'bigint' ? raw9 : BigInt(raw9);
  const s = n.toString().padStart(decimals + 1, '0');
  const head = s.slice(0, -decimals) || '0';
  const tail = s.slice(-decimals).replace(/0+$/, '');
  return tail ? `${head}.${tail}` : head;
}

// ====== DATABASE SETUP ======
const db = new Database(DB_FILE);
db.pragma('journal_mode = WAL');

// Create tables
db.exec(`
  CREATE TABLE IF NOT EXISTS state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    last_ts INTEGER NOT NULL DEFAULT 0,
    last_lt INTEGER,
    last_event_id TEXT,
    consecutive_errors INTEGER NOT NULL DEFAULT 0,
    in_catchup_mode INTEGER NOT NULL DEFAULT 0
  );

  CREATE TABLE IF NOT EXISTS processed_deposits (
    id TEXT PRIMARY KEY,
    ts INTEGER NOT NULL,
    ton_tx TEXT,
    ton_lt INTEGER,
    action_index INTEGER,
    from_address TEXT,
    amount TEXT NOT NULL,
    ton_memo TEXT,
    evm_recipient TEXT,
    bridge_payload_hash TEXT,
    bridge_status TEXT,
    bridge_response TEXT,
    status TEXT NOT NULL,
    error TEXT,
    processed_at INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS pending_submissions (
    id TEXT PRIMARY KEY,
    ts INTEGER NOT NULL,
    ton_tx TEXT,
    ton_lt INTEGER,
    action_index INTEGER,
    from_address TEXT,
    amount TEXT NOT NULL,
    ton_memo TEXT,
    evm_recipient TEXT,
    first_attempt_at INTEGER NOT NULL,
    last_attempt_at INTEGER NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    bridge_payload_hash TEXT,
    bridge_status TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_processed_ts ON processed_deposits(ts);
  CREATE INDEX IF NOT EXISTS idx_processed_status ON processed_deposits(status);
  CREATE INDEX IF NOT EXISTS idx_pending_last_attempt ON pending_submissions(last_attempt_at);

  INSERT OR IGNORE INTO state (id, last_ts) VALUES (1, 0);
`);

// Migration: Add consecutive_errors column if it doesn't exist
try {
  db.prepare('SELECT consecutive_errors FROM state LIMIT 1').get();
} catch (e) {
  console.log('Migrating database: adding consecutive_errors column...');
  db.prepare('ALTER TABLE state ADD COLUMN consecutive_errors INTEGER NOT NULL DEFAULT 0').run();
  console.log('Migration complete.');
}

// Migration: Add in_catchup_mode column if it doesn't exist
try {
  db.prepare('SELECT in_catchup_mode FROM state LIMIT 1').get();
} catch (e) {
  console.log('Migrating database: adding in_catchup_mode column...');
  db.prepare('ALTER TABLE state ADD COLUMN in_catchup_mode INTEGER NOT NULL DEFAULT 0').run();
  console.log('Migration complete.');
}

// Migration: Add fee_amount column if it doesn't exist
try {
  db.prepare('SELECT fee_amount FROM processed_deposits LIMIT 1').get();
} catch (e) {
  console.log('Migrating database: adding fee_amount column to processed_deposits...');
  db.prepare('ALTER TABLE processed_deposits ADD COLUMN fee_amount TEXT').run();
  console.log('Migration complete.');
}

try {
  db.prepare('SELECT fee_amount FROM pending_submissions LIMIT 1').get();
} catch (e) {
  console.log('Migrating database: adding fee_amount column to pending_submissions...');
  db.prepare('ALTER TABLE pending_submissions ADD COLUMN fee_amount TEXT').run();
  console.log('Migration complete.');
}

// Retry configuration
const RETRY_MIN_DELAY_MS = 10000; // Wait at least 10s between retries for same submission
const RETRY_MAX_ATTEMPTS = 100; // Give up after 100 attempts

// Error backoff configuration
const BACKOFF_BASE_MS = 30000; // Start with 30s delay after 10 errors
const MAX_BACKOFF_MS = 16 * 60 * 60 * 1000; // Maximum 16 hours backoff

// ====== TYPES ======
type TonNetEvent = {
  event_id: string;
  timestamp: number;
  lt?: number;
  actions?: any[];
};
type DepositStatus = 'pending' | 'completed' | 'error';
type BridgeStatus = 'submitted' | 'pending' | 'ready' | 'finalized' | 'failed';
type ProcessedDeposit = {
  id: string;
  ts: number;
  tonTx?: string;
  tonLt?: number; // Logical time from TON event (for deterministic nonce)
  actionIndex?: number; // Index in actions array (for deterministic nonce)
  from?: string;
  amount: string;
  feeAmount?: string; // Fee collected by vault contract (1%)
  tonMemo?: string | null;
  evmRecipient?: string | null;
  // Bridge aggregator fields
  bridgePayloadHash?: string;
  bridgeStatus?: BridgeStatus;
  bridgeResponse?: any;
  status: DepositStatus;
  error?: string;
};

// ====== STATE IO ======
interface ScanState {
  lastTs: number;
  lastLt?: number;
  lastEventId?: string;
  consecutiveErrors: number;
  inCatchupMode: boolean;
}

function getScanState(): ScanState {
  const row = db.prepare('SELECT * FROM state WHERE id = 1').get() as any;
  return {
    lastTs: row.last_ts || 0,
    lastLt: row.last_lt || undefined,
    lastEventId: row.last_event_id || undefined,
    consecutiveErrors: row.consecutive_errors || 0,
    inCatchupMode: Boolean(row.in_catchup_mode),
  };
}

function updateScanState(state: Partial<ScanState>): void {
  const updates: string[] = [];
  const values: any[] = [];

  if (state.lastTs !== undefined) {
    updates.push('last_ts = ?');
    values.push(state.lastTs);
  }
  if (state.lastLt !== undefined) {
    updates.push('last_lt = ?');
    values.push(state.lastLt);
  }
  if (state.lastEventId !== undefined) {
    updates.push('last_event_id = ?');
    values.push(state.lastEventId);
  }
  if (state.consecutiveErrors !== undefined) {
    updates.push('consecutive_errors = ?');
    values.push(state.consecutiveErrors);
  }
  if (state.inCatchupMode !== undefined) {
    updates.push('in_catchup_mode = ?');
    values.push(state.inCatchupMode ? 1 : 0);
  }

  if (updates.length > 0) {
    db.prepare(`UPDATE state SET ${updates.join(', ')} WHERE id = 1`).run(...values);
  }
}

function isDepositProcessed(id: string): boolean {
  const row = db.prepare('SELECT 1 FROM processed_deposits WHERE id = ?').get(id);
  return !!row;
}

function getProcessedDeposit(id: string): ProcessedDeposit | null {
  const row = db.prepare('SELECT * FROM processed_deposits WHERE id = ?').get(id) as any;
  if (!row) return null;

  return {
    id: row.id,
    ts: row.ts,
    tonTx: row.ton_tx || undefined,
    tonLt: row.ton_lt ?? undefined,
    actionIndex: row.action_index ?? undefined,
    from: row.from_address || undefined,
    amount: row.amount,
    tonMemo: row.ton_memo,
    evmRecipient: row.evm_recipient,
    bridgePayloadHash: row.bridge_payload_hash || undefined,
    bridgeStatus: row.bridge_status || undefined,
    bridgeResponse: row.bridge_response ? JSON.parse(row.bridge_response) : undefined,
    status: row.status as DepositStatus,
    error: row.error || undefined,
  };
}

function saveProcessedDeposit(deposit: ProcessedDeposit): void {
  db.prepare(`
    INSERT OR REPLACE INTO processed_deposits (
      id, ts, ton_tx, ton_lt, action_index, from_address, amount, fee_amount, ton_memo, evm_recipient,
      bridge_payload_hash, bridge_status, bridge_response, status, error, processed_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    deposit.id,
    deposit.ts,
    deposit.tonTx || null,
    deposit.tonLt || null,
    deposit.actionIndex || null,
    deposit.from || null,
    deposit.amount,
    deposit.feeAmount || null,
    deposit.tonMemo || null,
    deposit.evmRecipient || null,
    deposit.bridgePayloadHash || null,
    deposit.bridgeStatus || null,
    deposit.bridgeResponse ? JSON.stringify(deposit.bridgeResponse) : null,
    deposit.status,
    deposit.error || null,
    Date.now()
  );
}

function addPendingSubmission(deposit: ProcessedDeposit, error: string): void {
  const now = Date.now();

  db.prepare(`
    INSERT INTO pending_submissions (
      id, ts, ton_tx, ton_lt, action_index, from_address, amount, fee_amount, ton_memo, evm_recipient,
      first_attempt_at, last_attempt_at, attempt_count, last_error, bridge_payload_hash, bridge_status
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      last_attempt_at = ?,
      attempt_count = attempt_count + 1,
      last_error = ?
  `).run(
    deposit.id,
    deposit.ts,
    deposit.tonTx || null,
    deposit.tonLt || null,
    deposit.actionIndex || null,
    deposit.from || null,
    deposit.amount,
    deposit.feeAmount || null,
    deposit.tonMemo || null,
    deposit.evmRecipient || null,
    now, now, error,
    deposit.bridgePayloadHash || null,
    deposit.bridgeStatus || null,
    now, error
  );
}

function getPendingSubmissions(): ProcessedDeposit[] {
  const now = Date.now();
  const minLastAttempt = now - RETRY_MIN_DELAY_MS;

  const rows = db.prepare(`
    SELECT * FROM pending_submissions
    WHERE last_attempt_at < ?
      AND attempt_count < ?
    ORDER BY first_attempt_at ASC
    LIMIT 50
  `).all(minLastAttempt, RETRY_MAX_ATTEMPTS) as any[];

  return rows.map((row) => ({
    id: row.id,
    ts: row.ts,
    tonTx: row.ton_tx || undefined,
    tonLt: row.ton_lt ?? undefined,
    actionIndex: row.action_index ?? undefined,
    from: row.from_address || undefined,
    amount: row.amount,
    feeAmount: row.fee_amount || undefined,
    tonMemo: row.ton_memo,
    evmRecipient: row.evm_recipient,
    bridgePayloadHash: row.bridge_payload_hash || undefined,
    bridgeStatus: row.bridge_status || undefined,
    status: 'pending' as DepositStatus,
  }));
}

function markSubmissionSuccess(id: string): void {
  db.prepare('DELETE FROM pending_submissions WHERE id = ?').run(id);
}

function getPendingCount(): number {
  const row = db.prepare('SELECT COUNT(*) as count FROM pending_submissions').get() as any;
  return row.count;
}

// Keep for backwards compatibility
function readJson<T>(file: string, fallback: T): T {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf-8'));
  } catch {
    return fallback;
  }
}

// ====== TON API ======
function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

/**
 * Fetch events with cursor-based pagination
 * @param beforeLt - Logical time cursor for pagination
 * @param limit - Number of events per page
 */
async function fetchEventsPage(
  beforeLt?: number,
  limit = 100
): Promise<{ events: TonNetEvent[]; nextLt?: number }> {
  let url = `${TON_BASE}/v2/accounts/${TON_VAULT}/events?limit=${Math.min(limit, 100)}`;
  if (beforeLt) {
    url += `&before_lt=${beforeLt}`;
  }

  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const res = await fetch(url, { headers: { Accept: 'application/json' } });

      if (res.status === 429) {
        await sleep(500 * Math.pow(2, attempt));
        continue;
      }

      if (!res.ok) {
        throw new Error(`TonAPI events error: ${res.status} ${res.statusText}`);
      }

      const j = await res.json();
      const events = (j?.events ?? []) as TonNetEvent[];

      const nextLt = events.length > 0 ? events[events.length - 1]?.lt : undefined;

      return { events, nextLt };
    } catch (e: any) {
      if (attempt === 4) throw e;
      console.warn(`[FETCH_PAGE] Retry ${attempt + 1}/5: ${e.message}`);
      await sleep(500 * Math.pow(2, attempt));
    }
  }
  return { events: [], nextLt: undefined };
}

/**
 * Fetch all new events since lastLt with pagination
 * @param lastLt - Last processed logical time
 * @param maxPages - Maximum number of pages to fetch
 */
async function fetchAllNewEvents(lastLt?: number, maxPages = MAX_PAGES): Promise<TonNetEvent[]> {
  const allEvents: TonNetEvent[] = [];
  let currentLt: number | undefined = undefined;
  let pagesProcessed = 0;

  while (pagesProcessed < maxPages) {
    const { events, nextLt } = await fetchEventsPage(currentLt, EVENTS_PER_PAGE);

    if (events.length === 0) {
      break;
    }

    const newEvents = lastLt ? events.filter((ev) => (ev.lt ?? 0) > lastLt) : events;

    allEvents.push(...newEvents);

    if (lastLt && events.some((ev) => (ev.lt ?? 0) <= lastLt)) {
      break;
    }

    currentLt = nextLt;
    pagesProcessed++;

    if (!nextLt) {
      break;
    }

    await sleep(200);
  }

  if (allEvents.length > 0) {
    console.log(`📥 Fetched ${allEvents.length} new events (${pagesProcessed} pages)`);
  }

  if (pagesProcessed >= maxPages && allEvents.length > 0) {
    console.warn(`⚠️ Reached MAX_PAGES limit (${maxPages}), may have more events`);
  }

  return allEvents;
}

async function fetchVaultJettonWalletAddr(): Promise<Address> {
  if (cachedVaultJettonWallet) {
    return cachedVaultJettonWallet;
  }

  const owner = TON_VAULT;
  const jetton = TON_JETTON_ROOT_RAW || TON_JETTON_ROOT;
  if (!owner || !jetton) throw new Error('fetchVaultJettonWalletAddr: missing vault or jetton');

  const url = `${TON_BASE}/v2/accounts/${owner}/jettons`;

  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const r2 = await fetch(url, { headers: { Accept: 'application/json' } });

      if (r2.status === 429) {
        const waitMs = 1000 * Math.pow(2, attempt);
        console.log(
          `[FETCH_JETTON_WALLET] Rate limited (429), waiting ${waitMs}ms before retry ${attempt + 1}/5`
        );
        await sleep(waitMs);
        continue;
      }

      if (!r2.ok) {
        throw new Error(`TonAPI jettons error: ${r2.status} ${r2.statusText}`);
      }

      const j2 = await r2.json();
      const balances = j2?.balances ?? [];

      const hit = balances.find((x: any) => {
        const a = x?.jetton?.address as string | undefined;
        return a === jetton || (a && toRaw(a) === JETTON_RAW_EXPECTED);
      });

      let addr = hit?.wallet_address || hit?.wallet?.address;

      if (typeof addr === 'object' && addr !== null) {
        addr = addr.address || String(addr);
      }

      if (!addr || typeof addr !== 'string') {
        throw new Error('Cannot resolve vault jetton wallet address');
      }

      cachedVaultJettonWallet = Address.parse(addr);
      console.log('[FETCH_JETTON_WALLET] Successfully fetched and cached jetton wallet address');

      return cachedVaultJettonWallet;
    } catch (e: any) {
      if (attempt === 4 || (e.message && !e.message.includes('429'))) {
        throw e;
      }
      console.log(`[FETCH_JETTON_WALLET] Attempt ${attempt + 1}/5 failed: ${e.message}`);
    }
  }

  throw new Error('Failed to fetch vault jetton wallet after 5 attempts');
}

// ====== BRIDGE AGGREGATOR INTEGRATION ======

/**
 * Builds a bridge payload from deposit information
 * Uses shared payload helpers to ensure canonical format
 */
async function buildBridgePayload(dep: ProcessedDeposit): Promise<MintPayload> {
  const token = OFT_CONTRACT_ADDRESS;
  const recipient = dep.evmRecipient!;
  const amountRaw9 = dep.amount;

  // Generate deterministic nonce from TON LT and action index
  // This ensures all watchers generate the same nonce for the same event
  if (dep.tonLt === undefined || dep.actionIndex === undefined) {
    throw new Error(`Cannot generate nonce: missing tonLt (${dep.tonLt}) or actionIndex (${dep.actionIndex})`);
  }

  const nonce = generateDeterministicNonce(dep.tonLt, dep.actionIndex);

  const payload = buildPayload(
    ORIGIN_CHAIN_ID,
    token,
    recipient,
    amountRaw9,
    nonce,
    TOKEN_DECIMALS
  );

  console.log(`[PAYLOAD] Built payload with deterministic nonce:`, {
    originChainId: payload.originChainId,
    token: payload.token,
    recipient: payload.recipient,
    amount: payload.amount,
    nonce: payload.nonce,
    tonLt: dep.tonLt,
    actionIndex: dep.actionIndex,
    amountRaw9,
  });

  return payload;
}

/**
 * Signs a mint payload using watcher's private key
 * Follows EIP-712 standard matching BridgeMultisig
 */
async function signMintPayload(payload: MintPayload): Promise<string> {
  const wallet = new ethers.Wallet(PRIVATE_KEY);

  const domain = buildDomain(DESTINATION_CHAIN_ID, MULTISIG_ADDRESS);

  console.log(`[SIGN] Signing with domain:`, {
    name: domain.name,
    version: domain.version,
    chainId: domain.chainId,
    verifyingContract: domain.verifyingContract,
    watcherAddress: wallet.address,
  });

  const signature = await signPayloadHelper(wallet, payload, domain);

  console.log(`[SIGN] Generated signature:`, signature);

  return signature;
}

/**
 * Bridge API response type
 */
interface BridgeSubmissionResponse {
  hash: string;
  status: BridgeStatus;
  originChainId: number;
  token: string;
  recipient: string;
  amount: string;
  nonce: number | string;
  tonTxId: string;
  createdAt: number;
  signatures: Array<{ watcher: string; signature: string }>;
}

/**
 * Submits a signed payload to the Bridge Aggregator API
 * Implements retry logic with exponential backoff
 * Ensures idempotency for network failures
 */
async function submitToBridge(
  payload: MintPayload,
  signature: string,
  tonTxId: string,
  amountRaw9: string,
  feeAmount?: string
): Promise<BridgeSubmissionResponse> {
  const wallet = new ethers.Wallet(PRIVATE_KEY);
  const watcherAddress = wallet.address;

  const body = {
    originChainId: parseInt(payload.originChainId, 10),
    token: payload.token,
    recipient: payload.recipient,
    amountRaw9,
    nonce: payload.nonce,
    watcher: watcherAddress,
    signature,
    tonTxId,
    feeAmount, // Fee collected by vault contract (1%)
    metadata: {
      amount: payload.amount,
      scaledFromRaw9: amountRaw9,
      tokenDecimals: TOKEN_DECIMALS,
    },
  };

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };

  if (BRIDGE_API_KEY) {
    headers['X-API-Key'] = BRIDGE_API_KEY;
  }

  console.log(`[BRIDGE] Submitting to ${BRIDGE_URL}/payloads`, {
    watcher: watcherAddress,
    tonTxId,
    nonce: body.nonce,
  });

  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), BRIDGE_TIMEOUT_MS);

      const response = await fetch(`${BRIDGE_URL}/payloads`, {
        method: 'POST',
        headers,
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      clearTimeout(timeout);

      // Handle 409 Conflict (duplicate submission) as success - idempotent behavior
      if (response.status === 409) {
        const result: BridgeSubmissionResponse = await response.json();
        console.log(
          `✅ [BRIDGE] Payload already submitted (409): hash=${result.hash} status=${result.status}`
        );
        return result;
      }

      if (!response.ok) {
        const error = await response.text();
        throw new Error(`Bridge API error: ${response.status} ${error}`);
      }

      const result: BridgeSubmissionResponse = await response.json();
      console.log(
        `✅ [BRIDGE] Submitted successfully: hash=${result.hash} status=${result.status}`
      );

      return result;
    } catch (e: any) {
      if (attempt === 2) {
        throw new Error(`Bridge submission failed after 3 attempts: ${e.message}`);
      }
      const waitMs = 1000 * Math.pow(2, attempt);
      console.warn(`⚠️ [BRIDGE] Retry ${attempt + 1}/3 after ${waitMs}ms: ${e.message}`);
      await sleep(waitMs);
    }
  }

  throw new Error('Bridge submission failed after 3 attempts');
}

// ====== ADDRESS MAP ======
function readAddressMap(): Record<string, string> {
  return readJson(ADDRESS_MAP_FILE, {});
}
function resolveRecipientFromMap(tonSenderRaw: string): string | null {
  const map = readAddressMap();
  const v = map[tonSenderRaw] || map[tonSenderRaw.toLowerCase()];
  return isHexEvm(v) ? v : null;
}

// ====== CORE SCAN ======
// Legacy functions removed - now using SQLite database
// See getScanState(), updateScanState(), saveProcessedDeposit(), getPendingSubmissions() above

/**
 * Processes a deposit by signing and submitting to Bridge Aggregator
 * Bridge Aggregator will handle TON burn and Base mint
 * Watcher is read-only and does NOT hold TON keys
 */
async function processDeposit(dep: ProcessedDeposit): Promise<ProcessedDeposit> {
  let recipient: string | null = dep.evmRecipient ?? null;

  if (!recipient) {
    if (dep.from) recipient = resolveRecipientFromMap(dep.from);
  }

  if (REQUIRE_MEMO_RECIPIENT && !recipient) {
    console.log(`Pending (no recipient): ${dep.id}`);
    dep.status = 'pending';
    return dep;
  }

  try {
    const human = formatTokenAmount(dep.amount);

    // Build and sign payload
    console.log(`📦 Building bridge payload for recipient ${recipient} (${human} MOFT)...`);
    const payload = await buildBridgePayload(dep);
    const signature = await signMintPayload(payload);

    // Submit to bridge aggregator (vault already burned, bridge will mint on EVM)
    console.log(`🌉 Submitting signed payload to Bridge Aggregator...`);
    const response = await submitToBridge(payload, signature, dep.tonTx!, dep.amount, dep.feeAmount);

    dep.bridgePayloadHash = response.hash;
    dep.bridgeStatus = response.status;
    dep.bridgeResponse = response;
    dep.status = 'completed'; // Bridge acknowledged receipt, will handle burn + mint

    console.log(`✅ Submitted ${dep.id} → Bridge hash: ${dep.bridgePayloadHash}`);
    console.log(`   Bridge status: ${dep.bridgeStatus} (Bridge will handle TON burn + Base mint)`);
  } catch (e: any) {
    dep.status = 'error';
    dep.error = e?.message || e?.name || String(e);
    console.error(`❌ ${dep.id} failed:`);
    console.error('Error message:', e?.message);
    console.error('Error name:', e?.name);
    console.error('Error stack:', e?.stack);
    console.error('Full error:', e);
  }

  return dep;
}

/**
 * Extract deposits from vault burn events
 *
 * Vault contract emits burn_log events when user deposits are processed:
 * burn_log#4255524e from_address burn_amount fee_amount original_amount timestamp
 *
 * The vault automatically:
 * 1. Takes 1% fee (sends to fee wallet)
 * 2. Burns 99% of deposited jettons
 * 3. Emits burn_log event
 *
 * We listen for these burn events and create bridge payloads.
 */
function extractDepositsFromEvent(ev: TonNetEvent): ProcessedDeposit[] {
  const deposits: ProcessedDeposit[] = [];
  const acts: any[] = ev.actions || [];

  // First, check if any action involves the vault contract
  let hasVaultInteraction = false;
  for (let i = 0; i < acts.length; i++) {
    const a = acts[i];

    // Check SmartContractExec
    const smartContractExec = a?.SmartContractExec || a?.smart_contract_exec;
    if (smartContractExec) {
      const contractAddr = smartContractExec?.contract?.address || smartContractExec?.contract;
      let contractRaw: string | undefined;
      try {
        if (contractAddr) contractRaw = toRaw(String(contractAddr));
      } catch {
        contractRaw = String(contractAddr);
      }
      if (contractRaw === VAULT_CONTRACT_RAW_EXPECTED) {
        hasVaultInteraction = true;
        break;
      }
    }

    // Check TonTransfer or JettonTransfer to vault
    const tonTransfer = a?.TonTransfer || a?.ton_transfer;
    if (tonTransfer) {
      const recipient = tonTransfer?.recipient?.address || tonTransfer?.recipient;
      let recipientRaw: string | undefined;
      try {
        if (recipient) recipientRaw = toRaw(String(recipient));
      } catch {
        recipientRaw = String(recipient);
      }
      if (recipientRaw === VAULT_CONTRACT_RAW_EXPECTED) {
        hasVaultInteraction = true;
        break;
      }
    }
  }

  if (!hasVaultInteraction) {
    return deposits;
  }

  console.log(`[DEBUG] Event ${ev.event_id} has vault interaction, looking for burns...`);

  // Now look for JettonBurn actions
  for (let i = 0; i < acts.length; i++) {
    const a = acts[i];
    console.log(`[DEBUG] Action ${i}:`, Object.keys(a || {}));

    const jettonBurn = a?.JettonBurn || a?.jetton_burn;
    if (!jettonBurn) {
      console.log(`[DEBUG] Action ${i}: No JettonBurn found, skipping`);
      continue;
    }

    console.log(`[DEBUG] Action ${i}: Found JettonBurn, checking details...`);

    const burnAmount = String(jettonBurn?.amount ?? '0');
    const senderAny = jettonBurn?.sender?.address || jettonBurn?.sender;
    const jettonAny = jettonBurn?.jetton?.address || jettonBurn?.jetton;

    let fromRaw: string | undefined;
    try {
      if (senderAny) fromRaw = toRaw(String(senderAny));
    } catch {
      fromRaw = String(senderAny);
    }

    let jettonRaw: string | undefined;
    try {
      if (jettonAny) jettonRaw = toRaw(String(jettonAny));
    } catch {
      jettonRaw = String(jettonAny);
    }

    console.log(`[DEBUG] Action ${i} JettonBurn details:`, {
      burnAmount,
      fromRaw,
      jettonRaw,
      expectedJetton: JETTON_RAW_EXPECTED,
    });

    // Check if this is our jetton
    if (jettonRaw !== JETTON_RAW_EXPECTED) {
      console.log(`[DEBUG] Action ${i}: Wrong jetton (got: ${jettonRaw}, expected: ${JETTON_RAW_EXPECTED})`);
      continue;
    }

    // Calculate fee (1% of burn amount means original was burn / 0.99)
    const burnAmountBigInt = BigInt(burnAmount);
    const originalAmount = (burnAmountBigInt * 100n) / 99n; // Reverse calculate: burn = original * 0.99
    const feeAmount = originalAmount - burnAmountBigInt;

    console.log(`[DEBUG] Action ${i} vault burn:`, {
      burnAmount,
      feeAmount: feeAmount.toString(),
      originalAmount: originalAmount.toString(),
      fromRaw,
    });

    if (burnAmount === '0') {
      console.log(`[DEBUG] Action ${i}: Zero burn amount, skipping`);
      continue;
    }

    // For vault flow, we might not have EVM recipient in jetton burn event
    // We need to look at the original jetton transfer that triggered the vault
    // Look for JettonTransfer with comment field containing EVM address
    let evmRecipient: string | null = null;
    for (const act of acts) {
      const jettonTransfer = act?.JettonTransfer || act?.jetton_transfer;
      if (jettonTransfer) {
        const comment = jettonTransfer?.comment;
        if (comment && /^0x[0-9a-fA-F]{40}$/.test(comment)) {
          evmRecipient = comment;
          console.log(`[DEBUG] Found EVM recipient in JettonTransfer comment: ${evmRecipient}`);
          break;
        }
      }
    }

    const id = `${ev.event_id}#${i}@${burnAmount}`;

    // Check if already processed
    if (isDepositProcessed(id)) {
      console.log(`[DEBUG] Action ${i}: Already processed (${id})`);
      continue;
    }

    console.log(`[DEBUG] Action ${i}: Valid vault burn found! ID: ${id}`);

    deposits.push({
      id,
      ts: ev.timestamp,
      tonTx: ev.event_id,
      tonLt: ev.lt, // For deterministic nonce generation
      actionIndex: i, // For deterministic nonce generation
      from: fromRaw,
      amount: burnAmount, // Amount to mint on EVM (99% of original)
      feeAmount: feeAmount.toString(), // Fee collected by vault (1% of original)
      tonMemo: evmRecipient, // Store EVM address from comment
      evmRecipient: evmRecipient,
      status: 'pending' as const,
    });
  }

  return deposits;
}

// ====== MAIN LOOP (PAGINATED) ======
async function pollOnce() {
  // First, try to process pending submissions (failed submissions that need retry)
  const pending = getPendingSubmissions();
  if (pending.length > 0) {
    const totalPending = getPendingCount();
    console.log(`\n[RETRY QUEUE] Processing ${pending.length} of ${totalPending} pending submissions...`);

    for (const dep of pending) {
      console.log(`[RETRY] ${dep.id}`);
      try {
        const done = await processDeposit(dep);
        if (done.status === 'completed') {
          saveProcessedDeposit(done);
          markSubmissionSuccess(dep.id);
          console.log(`[RETRY SUCCESS] ${dep.id}`);
        } else if (done.status === 'error') {
          addPendingSubmission(done, done.error || 'Unknown error');
          console.log(`[RETRY FAILED] ${dep.id}: ${done.error}`);
        }
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        console.error(`[RETRY FAILED] ${dep.id}: ${errorMsg}`);
        addPendingSubmission(dep, errorMsg);
      }
    }
  }

  const state = getScanState();
  const nowSec = Math.floor(Date.now() / 1000);
  const confirmationCutoff = nowSec - CONFIRMATIONS_DELAY_S;

  // On first run, fetch latest event to set initial cursor
  if (!state.lastLt) {
    try {
      const { events } = await fetchEventsPage(undefined, 1);
      if (events.length > 0 && events[0].lt) {
        console.log(`🔖 Setting initial cursor to latest lt: ${events[0].lt}`);
        updateScanState({
          lastTs: nowSec,
          lastLt: events[0].lt,
          lastEventId: events[0].event_id,
        });
        return;
      }
    } catch (e: any) {
      console.warn(`⚠️ Failed to fetch initial cursor: ${e.message}`);
    }
  }

  let allEvents: TonNetEvent[] = [];
  try {
    allEvents = await fetchAllNewEvents(state.lastLt, MAX_PAGES);
  } catch (e: any) {
    console.warn(`⚠️ Fetch failed: ${e.message}`);
    return;
  }

  if (allEvents.length === 0) {
    return;
  }

  const confirmedEvents = allEvents.filter((ev) => ev.timestamp <= confirmationCutoff);

  if (confirmedEvents.length === 0) {
    return;
  }

  // Check if we're in catch-up mode
  const eventsBehind = confirmedEvents.length;
  const shouldEnterCatchUpMode = eventsBehind > 50;

  // Enter catch-up mode if significantly behind
  if (shouldEnterCatchUpMode && !state.inCatchupMode) {
    updateScanState({ inCatchupMode: true });
    state.inCatchupMode = true;
  }

  // Log catch-up status if in catch-up mode
  if (state.inCatchupMode) {
    console.log(`\n[CATCH-UP MODE] ${eventsBehind.toLocaleString()} events behind`);
  } else if (eventsBehind > 5) {
    // Show progress even when not in full catch-up mode
    console.log(`📥 Fetched ${allEvents.length} new events (${confirmedEvents.length} confirmed, ${allEvents.length - confirmedEvents.length} pending confirmation)`);
  }

  confirmedEvents.sort((a, b) => a.timestamp - b.timestamp);

  console.log(`📦 Processing ${confirmedEvents.length} confirmed events`);

  let eventsProcessed = 0;
  const totalEventsToProcess = confirmedEvents.length;

  for (const ev of confirmedEvents) {
    if (state.lastEventId && ev.event_id === state.lastEventId) {
      console.log('↩️ Skip already processed:', ev.event_id);
      continue;
    }

    const deposits = extractDepositsFromEvent(ev);

    console.log(`📦 Extracted ${deposits.length} deposits from event ${ev.event_id}`);
    if (deposits.length === 0) {
      console.log(`⚠️  No valid deposits found in event. Actions:`, ev.actions?.length || 0);
    }

    for (const dep of deposits) {
      console.log('🚦 Deposit:', dep.id);

      // Check if already completed in database
      const prev = getProcessedDeposit(dep.id);
      if (prev && prev.status === 'completed') {
        console.log('↩️ Already completed:', dep.id);
        continue;
      }

      try {
        const done = await processDeposit(dep);
        saveProcessedDeposit(done);

        // If failed, add to retry queue
        if (done.status === 'error') {
          addPendingSubmission(done, done.error || 'Unknown error');
          console.log(`Added ${dep.id} to retry queue`);
        } else if (done.status === 'completed') {
          markSubmissionSuccess(dep.id); // Remove from pending if it was there
        }
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        console.error(`Failed to process ${dep.id}: ${errorMsg}`);
        dep.status = 'error';
        dep.error = errorMsg;
        saveProcessedDeposit(dep);
        addPendingSubmission(dep, errorMsg);
      }
    }

    updateScanState({
      lastTs: ev.timestamp,
      lastLt: ev.lt,
      lastEventId: ev.event_id,
    });

    eventsProcessed++;
  }

  // Check if we completed catch-up
  const wasCatchingUp = state.inCatchupMode;
  const eventsRemaining = totalEventsToProcess - eventsProcessed;

  // Log progress if in catch-up mode
  if (state.inCatchupMode && eventsRemaining > 0) {
    const progress = (eventsProcessed / totalEventsToProcess * 100).toFixed(1);
    console.log(`[PROGRESS] Processed ${eventsProcessed.toLocaleString()} events. ${eventsRemaining.toLocaleString()} remaining (${progress}% done)`);
  } else if (wasCatchingUp && eventsRemaining === 0) {
    updateScanState({ inCatchupMode: false, consecutiveErrors: 0 });
    console.log(`\n✅ [CAUGHT UP] Processed ${eventsProcessed} events. Now monitoring live events.`);
  }

  // Reset consecutive errors on successful poll
  if (state.consecutiveErrors > 0) {
    updateScanState({ consecutiveErrors: 0 });
  }
}

/**
 * Validates required configuration at startup
 */
async function validateConfiguration() {
  const missing: string[] = [];

  if (!TON_VAULT) missing.push('TON_VAULT');
  if (!TON_JETTON_ROOT && !TON_JETTON_ROOT_RAW) missing.push('TON_JETTON_ROOT');
  if (!PRIVATE_KEY) missing.push('PRIVATE_KEY');
  if (!OFT_CONTRACT_ADDRESS) missing.push('OFT_CONTRACT_ADDRESS');
  if (!MULTISIG_ADDRESS) missing.push('MULTISIG_ADDRESS');

  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
  }

  // Validate watcher key
  const wallet = new ethers.Wallet(PRIVATE_KEY);
  console.log('Watcher address:', wallet.address);
  console.log('Multisig address:', MULTISIG_ADDRESS);

  // Validate addresses
  try {
    ethers.utils.getAddress(OFT_CONTRACT_ADDRESS);
  } catch (e) {
    throw new Error(`Invalid OFT_CONTRACT_ADDRESS: ${OFT_CONTRACT_ADDRESS}`);
  }

  try {
    ethers.utils.getAddress(MULTISIG_ADDRESS);
  } catch (e) {
    throw new Error(`Invalid MULTISIG_ADDRESS: ${MULTISIG_ADDRESS}`);
  }

  // Validate HTTPS for production
  if (TON_CHAIN === 'mainnet' && !BRIDGE_URL.startsWith('https://')) {
    console.warn('');
    console.warn('⚠️  WARNING: BRIDGE_URL is not HTTPS on mainnet!');
    console.warn('⚠️  Current URL:', BRIDGE_URL);
    console.warn('⚠️  Production deployments MUST use HTTPS for security.');
    console.warn('⚠️  Continuing in 5 seconds... Press Ctrl+C to abort.');
    console.warn('');

    // Give operator time to abort if this is unintentional
    await new Promise(resolve => setTimeout(resolve, 5000));
  }

  // Test bridge connectivity (non-blocking)
  (async () => {
    try {
      const response = await fetch(`${BRIDGE_URL}/health`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
      });
      if (response.ok) {
        const health = await response.json();
        console.log('✅ Bridge API is reachable:', health);
      } else {
        console.warn('⚠️ Bridge API returned non-OK status:', response.status);
      }
    } catch (e: any) {
      console.warn('⚠️ Could not reach Bridge API:', e.message);
      console.warn('   Ensure BRIDGE_URL is correct and the service is running');
    }
  })();
}

async function main() {
  console.log('=== TON -> BASE (BRIDGE AGGREGATOR) ===');
  console.log('TON_CHAIN:', TON_CHAIN);
  console.log('TON_VAULT:', TON_VAULT ? 'Set' : 'Missing');
  console.log('TON_JETTON_ROOT:', TON_JETTON_ROOT ? 'Set' : 'Missing');
  console.log('OFT_CONTRACT_ADDRESS:', OFT_CONTRACT_ADDRESS ? 'Set' : 'Missing');
  console.log('MULTISIG_ADDRESS:', MULTISIG_ADDRESS ? 'Set' : 'Missing');
  console.log('BRIDGE_URL:', BRIDGE_URL);
  console.log('ORIGIN_CHAIN_ID:', ORIGIN_CHAIN_ID);
  console.log('DESTINATION_CHAIN_ID:', DESTINATION_CHAIN_ID);
  console.log('TOKEN_DECIMALS:', TOKEN_DECIMALS);
  console.log('REQUIRE_MEMO_RECIPIENT:', REQUIRE_MEMO_RECIPIENT);
  console.log('EVENTS_PER_PAGE:', EVENTS_PER_PAGE);
  console.log('MAX_PAGES:', MAX_PAGES);

  await validateConfiguration();

  const st = getScanState();
  if (!st.lastTs) {
    console.log(`🆕 First run - will skip all old events and start monitoring from NOW`);
  }

  console.log('\n🚀 Starting paginated poller with Bridge Aggregator integration (SQLite + Retry Queue)...\n');

  let state = getScanState();

  while (true) {
    const t0 = Date.now();
    try {
      await pollOnce();
      state = getScanState(); // Refresh state
    } catch (e: any) {
      state.consecutiveErrors = (state.consecutiveErrors || 0) + 1;
      updateScanState({ consecutiveErrors: state.consecutiveErrors });

      // Log full error details including stack trace
      console.error(`\n❌ Poll error (#${state.consecutiveErrors}):`);
      console.error(`  Message: ${e?.message || String(e)}`);
      console.error(`  Code: ${e?.code || 'N/A'}`);
      console.error(`  Error Code: ${e?.error?.code || 'N/A'}`);
      if (e?.stack) {
        console.error(`  Stack trace:\n${e.stack}`);
      }
      console.error('');

      // Exponential backoff instead of exit
      if (state.consecutiveErrors > 10) {
        // Calculate backoff: 30s * 2^(errors - 10), max 16 hours
        const backoffMs = Math.min(
          MAX_BACKOFF_MS,
          BACKOFF_BASE_MS * Math.pow(2, state.consecutiveErrors - 10)
        );
        const backoffMinutes = (backoffMs / 60000).toFixed(1);
        const backoffHours = (backoffMs / 3600000).toFixed(2);

        console.error(`⏳ Too many consecutive errors. Entering exponential backoff mode.`);
        console.error(`   Waiting ${backoffMinutes} minutes (${backoffHours} hours) before retry...`);
        console.error(`   Watcher will NOT exit - will retry automatically after backoff.\n`);

        await sleep(backoffMs);
      }
    }
    const dt = Date.now() - t0;
    const wait = Math.max(500, POLL_INTERVAL_MS - dt);
    await new Promise((r) => setTimeout(r, wait));
  }
}

if (require.main === module) {
  main().catch((e) => {
    console.error('❌ FATAL:', e);
    process.exit(1);
  });
}
