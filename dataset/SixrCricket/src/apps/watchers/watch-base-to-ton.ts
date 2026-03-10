/**
 * @file watch-base-to-ton.ts
 * @notice Base → TON bridge watcher (EVM burn to TON mint)
 *
 * This watcher monitors the MOFT contract on Base for RedeemToTon events,
 * builds TON mint payloads with signatures, and submits them to the bridge aggregator.
 * The aggregator coordinates 2-of-3 signature quorum before the TON mint worker mints jettons.
 */

import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { ethers } from 'ethers';
import Database from 'better-sqlite3';
import axios from 'axios';
import {
  buildTonMintPayload,
  normalizeTonAddress,
  signTonMintPayload,
  buildDomain,
} from '../shared/payload';
import {
  hashMintPayload as hashTonMintPayloadTLB,
  TonMintPayload,
} from '../shared/ton-multisig/payload';
import {
  keypairFromSecretKeyHex,
  signPayload as signTonPayload,
  Ed25519Keypair,
} from '../shared/ton-multisig/signatures';

/* =========================
   Configuration
   ========================= */
const BASE_HTTP_URL = process.env.BASE_HTTP_URL || '';
const BASE_WS_URL = process.env.BASE_WS_URL || '';
const MOFT_ADDRESS = (process.env.OFT_CONTRACT_ADDRESS || '').trim();

const WATCHER_PRIVATE_KEY = process.env.PRIVATE_KEY || '';
const AGGREGATOR_URL = process.env.AGGREGATOR_URL || 'http://localhost:3000';
const MULTISIG_ADDRESS = process.env.MULTISIG_ADDRESS || '';
const BASE_CHAIN_ID = parseInt(process.env.BASE_CHAIN_ID || '8453', 10);

// TON Multisig Configuration
const TON_WATCHER_PUBLIC_KEY_HEX = process.env.TON_WATCHER_PUBLIC_KEY_HEX || '';
const TON_WATCHER_SECRET_KEY_HEX = process.env.TON_WATCHER_SECRET_KEY_HEX || '';
const TON_WATCHER_INDEX = parseInt(process.env.TON_WATCHER_INDEX || '0', 10);
const TON_MULTISIG_ADDRESS = process.env.TON_MULTISIG_ADDRESS || '';

// IMPORTANT: This value must match BASE_MIN_CONFIRMATIONS on the bridge (default: 5)
// If the watcher sends payloads before the bridge's minimum confirmations,
// submissions will be rejected with "400 Insufficient confirmations"
const CONFIRMATIONS = parseInt(process.env.CONFIRMATIONS || '5', 10);
const POLL_INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS || '15000', 10);
const CHUNK_BLOCKS = parseInt(process.env.CHUNK_BLOCKS || '2000', 10);
const MAX_PAGES = parseInt(process.env.MAX_PAGES || '20', 10);

// Validation
if (!BASE_HTTP_URL && !BASE_WS_URL) {
  throw new Error('BASE_HTTP_URL or BASE_WS_URL required');
}
if (!MOFT_ADDRESS) {
  throw new Error('OFT_CONTRACT_ADDRESS required');
}
if (!WATCHER_PRIVATE_KEY) {
  throw new Error('PRIVATE_KEY required for watcher signing');
}
if (!MULTISIG_ADDRESS) {
  throw new Error('MULTISIG_ADDRESS required for payload domain');
}

// TON Multisig validation
if (!TON_WATCHER_PUBLIC_KEY_HEX || !TON_WATCHER_SECRET_KEY_HEX) {
  throw new Error('TON_WATCHER_PUBLIC_KEY_HEX and TON_WATCHER_SECRET_KEY_HEX required for TON signing');
}
if (TON_WATCHER_INDEX < 0 || TON_WATCHER_INDEX > 2) {
  throw new Error('TON_WATCHER_INDEX must be 0, 1, or 2');
}
if (!TON_MULTISIG_ADDRESS) {
  throw new Error('TON_MULTISIG_ADDRESS required');
}

const DATA_DIR = process.env.DATA_DIR || process.cwd();
const DB_FILE = path.join(DATA_DIR, 'base-to-ton-watcher.db');

/* =========================
   Database setup
   ========================= */
const db = new Database(DB_FILE);
db.pragma('journal_mode = WAL');

// Create tables
db.exec(`
  CREATE TABLE IF NOT EXISTS state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    last_block INTEGER NOT NULL DEFAULT 0,
    consecutive_errors INTEGER NOT NULL DEFAULT 0,
    max_range INTEGER NOT NULL DEFAULT ${CHUNK_BLOCKS},
    in_catchup_mode INTEGER NOT NULL DEFAULT 0
  );

  CREATE TABLE IF NOT EXISTS processed (
    event_id TEXT PRIMARY KEY,
    tx_hash TEXT NOT NULL,
    log_index INTEGER NOT NULL,
    processed_at INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS pending_submissions (
    event_id TEXT PRIMARY KEY,
    tx_hash TEXT NOT NULL,
    log_index INTEGER NOT NULL,
    block_number INTEGER NOT NULL,
    from_address TEXT NOT NULL,
    ton_recipient TEXT NOT NULL,
    amount_ld TEXT NOT NULL,
    amount_raw9 TEXT NOT NULL,
    first_attempt_at INTEGER NOT NULL,
    last_attempt_at INTEGER NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_processed_tx ON processed(tx_hash);
  CREATE INDEX IF NOT EXISTS idx_processed_at ON processed(processed_at);
  CREATE INDEX IF NOT EXISTS idx_pending_last_attempt ON pending_submissions(last_attempt_at);

  INSERT OR IGNORE INTO state (id, last_block) VALUES (1, 0);
`);

// Migration: Add in_catchup_mode column if it doesn't exist
try {
  db.prepare('SELECT in_catchup_mode FROM state LIMIT 1').get();
} catch (e) {
  console.log('Migrating database: adding in_catchup_mode column...');
  db.prepare('ALTER TABLE state ADD COLUMN in_catchup_mode INTEGER NOT NULL DEFAULT 0').run();
  console.log('Migration complete.');
}

interface WatcherState {
  lastBlock: number;
  consecutiveErrors: number;
  maxRange: number;
  inCatchupMode: boolean;
}

function getState(): WatcherState {
  const row = db.prepare('SELECT * FROM state WHERE id = 1').get() as any;
  return {
    lastBlock: row.last_block,
    consecutiveErrors: row.consecutive_errors,
    maxRange: row.max_range,
    inCatchupMode: Boolean(row.in_catchup_mode),
  };
}

function updateState(state: Partial<WatcherState>): void {
  const updates: string[] = [];
  const values: any[] = [];

  if (state.lastBlock !== undefined) {
    updates.push('last_block = ?');
    values.push(state.lastBlock);
  }
  if (state.consecutiveErrors !== undefined) {
    updates.push('consecutive_errors = ?');
    values.push(state.consecutiveErrors);
  }
  if (state.maxRange !== undefined) {
    updates.push('max_range = ?');
    values.push(state.maxRange);
  }
  if (state.inCatchupMode !== undefined) {
    updates.push('in_catchup_mode = ?');
    values.push(state.inCatchupMode ? 1 : 0);
  }

  if (updates.length > 0) {
    db.prepare(`UPDATE state SET ${updates.join(', ')} WHERE id = 1`).run(...values);
  }
}

function isProcessed(eventId: string): boolean {
  const row = db.prepare('SELECT 1 FROM processed WHERE event_id = ?').get(eventId);
  return !!row;
}

function markProcessed(eventId: string, txHash: string, logIndex: number): void {
  db.prepare(
    'INSERT OR IGNORE INTO processed (event_id, tx_hash, log_index, processed_at) VALUES (?, ?, ?, ?)'
  ).run(eventId, txHash, logIndex, Date.now());
}

/* =========================
   Pending Submissions Queue
   ========================= */
interface PendingSubmission {
  eventId: string;
  txHash: string;
  logIndex: number;
  blockNumber: number;
  fromAddress: string;
  tonRecipient: string;
  amountLD: string;
  amountRaw9: string;
  firstAttemptAt: number;
  lastAttemptAt: number;
  attemptCount: number;
  lastError: string | null;
}

// Retry configuration
const RETRY_MIN_DELAY_MS = 10000; // Wait at least 10s between retries for same submission
const RETRY_MAX_ATTEMPTS = 100; // Give up after 100 attempts

// Error backoff configuration
const BACKOFF_BASE_MS = 30000; // Start with 30s delay after 10 errors
const MAX_BACKOFF_MS = 16 * 60 * 60 * 1000; // Maximum 16 hours backoff

function addPendingSubmission(
  eventId: string,
  txHash: string,
  logIndex: number,
  blockNumber: number,
  fromAddress: string,
  tonRecipient: string,
  amountLD: string,
  amountRaw9: string,
  error: string
): void {
  const now = Date.now();

  db.prepare(`
    INSERT INTO pending_submissions (
      event_id, tx_hash, log_index, block_number, from_address, ton_recipient,
      amount_ld, amount_raw9, first_attempt_at, last_attempt_at, attempt_count, last_error
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
    ON CONFLICT(event_id) DO UPDATE SET
      last_attempt_at = ?,
      attempt_count = attempt_count + 1,
      last_error = ?
  `).run(
    eventId, txHash, logIndex, blockNumber, fromAddress, tonRecipient,
    amountLD, amountRaw9, now, now, error,
    now, error
  );
}

function getPendingSubmissions(): PendingSubmission[] {
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
    eventId: row.event_id,
    txHash: row.tx_hash,
    logIndex: row.log_index,
    blockNumber: row.block_number,
    fromAddress: row.from_address,
    tonRecipient: row.ton_recipient,
    amountLD: row.amount_ld,
    amountRaw9: row.amount_raw9,
    firstAttemptAt: row.first_attempt_at,
    lastAttemptAt: row.last_attempt_at,
    attemptCount: row.attempt_count,
    lastError: row.last_error,
  }));
}

function markSubmissionSuccess(eventId: string): void {
  db.prepare('DELETE FROM pending_submissions WHERE event_id = ?').run(eventId);
}

function updateSubmissionAttempt(eventId: string, error: string): void {
  const now = Date.now();
  db.prepare(`
    UPDATE pending_submissions
    SET last_attempt_at = ?,
        attempt_count = attempt_count + 1,
        last_error = ?
    WHERE event_id = ?
  `).run(now, error, eventId);
}

function getPendingCount(): number {
  const row = db.prepare('SELECT COUNT(*) as count FROM pending_submissions').get() as any;
  return row.count;
}

/* =========================
   EVM provider & ABI
   ========================= */
function makeEvmProvider(): ethers.providers.Provider {
  // Always create fresh provider for each poll cycle
  // Don't cache - ensures clean state after errors
  if (BASE_WS_URL) {
    return new ethers.providers.WebSocketProvider(BASE_WS_URL);
  }
  return new ethers.providers.JsonRpcProvider(BASE_HTTP_URL);
}

/**
 * Cleanup provider connections (important for WebSocket)
 */
function cleanupProvider(provider: ethers.providers.Provider): void {
  try {
    if (provider instanceof ethers.providers.WebSocketProvider) {
      provider.destroy();
    }
  } catch (e) {
    // Ignore cleanup errors
  }
}

const MOFT_ABI = [
  'event RedeemToTon(address indexed from, string tonRecipient, uint256 amount, uint256 fee)',
];

/* =========================
   Helper functions
   ========================= */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isFriendlyTon(addr: string): boolean {
  return /^[EU]Q[0-9A-Za-z\-_]{46}$/.test(addr);
}

/* =========================
   Event fetching
   ========================= */
async function fetchRedeemsInRange(
  provider: ethers.providers.Provider,
  fromBlock: number,
  toBlock: number
): Promise<ethers.Event[]> {
  const moft = new ethers.Contract(MOFT_ADDRESS, MOFT_ABI, provider);
  const filter = moft.filters.RedeemToTon();
  const logs = await moft.queryFilter(filter, fromBlock, toBlock);
  logs.sort((a, b) => (a.blockNumber - b.blockNumber) || (a.logIndex - b.logIndex));
  return logs;
}

async function fetchAllRedeemEvents(
  provider: ethers.providers.Provider,
  fromBlock: number,
  toBlock: number,
  state: WatcherState,
  maxPages: number = MAX_PAGES
): Promise<{ events: ethers.Event[], lastScannedBlock: number }> {
  const allEvents: ethers.Event[] = [];
  let currentFrom = fromBlock;
  let pagesProcessed = 0;
  let maxRange = state.maxRange;
  let lastScannedBlock = fromBlock - 1; // Start before the range

  while (currentFrom <= toBlock && pagesProcessed < maxPages) {
    const chunkSize = Math.min(maxRange, toBlock - currentFrom + 1);
    const currentTo = currentFrom + chunkSize - 1;

    try {
      const events = await fetchRedeemsInRange(provider, currentFrom, currentTo);
      allEvents.push(...events);

      lastScannedBlock = currentTo; // Update to last successfully scanned block
      currentFrom = currentTo + 1;
      pagesProcessed++;

      await sleep(200);
    } catch (e: any) {
      const msg = String(e?.message || e);
      if (msg.includes('eth_getLogs') && msg.includes('10 block range')) {
        console.warn('Range limit detected, shrinking to 10 blocks permanently');
        maxRange = 10;
        updateState({ maxRange: 10 });
        continue;
      }
      throw e;
    }
  }

  if (allEvents.length > 0) {
    console.log(`Fetched ${allEvents.length} events (${pagesProcessed} pages)`);
  }

  if (pagesProcessed >= maxPages && currentFrom <= toBlock) {
    console.warn(`Reached MAX_PAGES (${maxPages}), will continue from block ${lastScannedBlock + 1} on next poll`);
  }

  return { events: allEvents, lastScannedBlock };
}

/* =========================
   Aggregator submission
   ========================= */
async function submitToAggregator(
  wallet: ethers.Wallet,
  tonKeypair: Ed25519Keypair,
  event: {
    txHash: string;
    logIndex: number;
    blockNumber: number;
    from: string;
    tonRecipient: string;
    tonRecipientRaw?: string;
    amountLD: ethers.BigNumber;
  }
): Promise<void> {
  console.log('\n=== Submitting to Aggregator ===');
  console.log(`TX: ${event.txHash}`);
  console.log(`From: ${event.from}`);
  console.log(`TON Recipient (submitted): ${event.tonRecipient}`);
  console.log(`Amount (18 dec): ${ethers.utils.formatUnits(event.amountLD, 18)}`);

  // Validate TON address
  if (!isFriendlyTon(event.tonRecipient)) {
    throw new Error(`Invalid TON address format: ${event.tonRecipient}`);
  }

  const normalizedTonRecipient = normalizeTonAddress(event.tonRecipient);
  if (normalizedTonRecipient !== event.tonRecipient) {
    console.log(`TON Recipient (canonical): ${normalizedTonRecipient}`);
  }

  // Convert 18 -> 9 decimals
  const amount18 = BigInt(event.amountLD.toString());
  const amount9 = amount18 / BigInt(10 ** 9);
  const amountRaw9 = amount9.toString();

  console.log(`Amount (9 dec): ${amountRaw9}`);

  // Build canonical TON mint payload (for EVM EIP-712 signature)
  const payload = buildTonMintPayload(
    BASE_CHAIN_ID,
    MOFT_ADDRESS,
    normalizedTonRecipient,
    amountRaw9,
    event.blockNumber,
    event.logIndex,
    event.txHash
  );

  // Build domain for EVM signing
  const domain = buildDomain(BASE_CHAIN_ID, MULTISIG_ADDRESS);

  // Sign with EVM key (for legacy compatibility/dual signature support)
  const evmSignature = await signTonMintPayload(wallet, payload, domain);

  // Build TON mint payload for TON multisig signing (TL-B format)
  const tonPayload: TonMintPayload = {
    originChainId: BASE_CHAIN_ID,
    token: MOFT_ADDRESS,
    tonRecipient: normalizedTonRecipient,
    amount: BigInt(amountRaw9),
    nonce: BigInt(payload.nonce),
  };

  // Hash the TON payload using TL-B schema
  const tonPayloadHash = hashTonMintPayloadTLB(tonPayload);

  // Sign with TON ed25519 key
  const tonSignatureObj = signTonPayload(tonPayloadHash, tonKeypair);

  // Convert to hex strings for submission
  const tonPublicKey = tonKeypair.publicKey.toString('hex');
  const tonSignature = tonSignatureObj.signature.toString('hex');

  console.log(`Payload hash (EVM): ${JSON.stringify(payload, null, 2)}`);
  console.log(`EVM Signature: ${evmSignature}`);
  console.log(`TON Public Key: ${tonPublicKey}`);
  console.log(`TON Signature: ${tonSignature}`);
  console.log(`TON Watcher Index: ${TON_WATCHER_INDEX}`);

  // Prepare submission with both EVM and TON signatures
  const submission = {
    direction: 'EVM_TO_TON',
    originChainId: BASE_CHAIN_ID,
    token: payload.token,
    tonRecipient: normalizedTonRecipient,
    tonRecipientRaw: event.tonRecipientRaw,
    tonRecipientHash: payload.tonRecipientHash,
    amountRaw9: payload.amount,
    amountRaw18: event.amountLD.toString(),
    nonce: payload.nonce,
    watcher: wallet.address,
    signature: evmSignature,
    // TON Multisig fields
    tonWatcherIndex: TON_WATCHER_INDEX,
    tonPublicKey,
    tonSignature,
    burnTxHash: payload.burnTxHash,
    burnBlockNumber: event.blockNumber,
    burnRedeemLogIndex: event.logIndex,
    // burnTransferLogIndex is optional - can be calculated later if needed
  };

  // Submit to aggregator
  const response = await axios.post(`${AGGREGATOR_URL}/payloads`, submission, {
    headers: { 'Content-Type': 'application/json' },
    timeout: 10000,
  });

  if (response.status !== 200) {
    throw new Error(`Aggregator returned status ${response.status}: ${JSON.stringify(response.data)}`);
  }

  console.log('Aggregator response:', JSON.stringify(response.data, null, 2));
  console.log('=== Submission Complete ===\n');
}

/* =========================
   Event processing
   ========================= */
async function handleRedeemEvent(
  wallet: ethers.Wallet,
  tonKeypair: Ed25519Keypair,
  event: ethers.Event
): Promise<void> {
  const { args, transactionHash, logIndex, blockNumber } = event;
  if (!args || !transactionHash || logIndex === undefined || !blockNumber) {
    console.error('Event missing required fields');
    return;
  }

  const eventId = `${transactionHash}:${logIndex}`;

  if (isProcessed(eventId)) {
    return;
  }

  const from = args[0] as string;
  const tonRecipientRaw = args[1] as string;
  const amountLD = args[2] as ethers.BigNumber;
  const fee = args[3] as ethers.BigNumber | undefined;

  let tonRecipient: string;
  try {
    tonRecipient = normalizeTonAddress(tonRecipientRaw);
  } catch (err) {
    console.error(`Invalid TON address returned in event: ${tonRecipientRaw}`, err);
    return;
  }

  console.log(`\nRedeemToTon detected: ${eventId}`);
  console.log(`  From: ${from}`);
  console.log(`  TON (raw): ${tonRecipientRaw}`);
  if (tonRecipient !== tonRecipientRaw) {
    console.log(`  TON (canonical): ${tonRecipient}`);
  }
  console.log(`  Amount: ${ethers.utils.formatUnits(amountLD, 18)}`);
  if (fee) {
    console.log(`  Fee: ${ethers.utils.formatUnits(fee, 18)}`);
  }

  try {
    await submitToAggregator(wallet, tonKeypair, {
      txHash: transactionHash,
      logIndex,
      blockNumber,
      from,
      tonRecipient,
      tonRecipientRaw,
      amountLD,
    });

    markProcessed(eventId, transactionHash, logIndex);
    markSubmissionSuccess(eventId); // Remove from pending queue if it was there
    console.log(`Processed: ${eventId}`);
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    console.error(`Failed to process ${eventId}: ${errorMsg}`);

    // Add to pending queue for retry
    addPendingSubmission(
      eventId,
      transactionHash,
      logIndex,
      blockNumber,
      from,
      tonRecipient,
      amountLD.toString(),
      '', // amountRaw9 will be calculated on retry
      errorMsg
    );
    console.log(`Added ${eventId} to retry queue (will retry in ${RETRY_MIN_DELAY_MS / 1000}s)`);
  }
}

/**
 * Retry a pending submission from the database
 */
async function retryPendingSubmission(
  wallet: ethers.Wallet,
  tonKeypair: Ed25519Keypair,
  pending: PendingSubmission
): Promise<void> {
  console.log(`\n[RETRY #${pending.attemptCount}] ${pending.eventId}`);
  console.log(`  First attempt: ${new Date(pending.firstAttemptAt).toISOString()}`);
  console.log(`  Last error: ${pending.lastError}`);

  try {
    await submitToAggregator(wallet, tonKeypair, {
      txHash: pending.txHash,
      logIndex: pending.logIndex,
      blockNumber: pending.blockNumber,
      from: pending.fromAddress,
      tonRecipient: pending.tonRecipient,
      amountLD: ethers.BigNumber.from(pending.amountLD),
    });

    markProcessed(pending.eventId, pending.txHash, pending.logIndex);
    markSubmissionSuccess(pending.eventId);
    console.log(`[RETRY SUCCESS] ${pending.eventId}`);
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    console.error(`[RETRY FAILED] ${pending.eventId}: ${errorMsg}`);
    updateSubmissionAttempt(pending.eventId, errorMsg);

    if (pending.attemptCount + 1 >= RETRY_MAX_ATTEMPTS) {
      console.error(`[GIVING UP] ${pending.eventId} after ${RETRY_MAX_ATTEMPTS} attempts`);
    }
  }
}

/* =========================
   Main polling loop
   ========================= */
async function pollOnce(
  wallet: ethers.Wallet,
  tonKeypair: Ed25519Keypair,
  state: WatcherState
): Promise<void> {
  // First, try to process pending submissions (failed submissions that need retry)
  const pending = getPendingSubmissions();
  if (pending.length > 0) {
    const totalPending = getPendingCount();
    console.log(`\n[RETRY QUEUE] Processing ${pending.length} of ${totalPending} pending submissions...`);

    for (const p of pending) {
      await retryPendingSubmission(wallet, tonKeypair, p);
    }
  }

  const provider = makeEvmProvider();

  try {
    const latest = await provider.getBlockNumber();
    const safeTo = latest - Math.max(0, CONFIRMATIONS);

    if (state.lastBlock === 0) {
      updateState({ lastBlock: safeTo });
      console.log(`First run - cursor set to block ${safeTo} (skipping old events)`);
      console.log('Will start monitoring from this point forward\n');
      return;
    }

    if (safeTo <= state.lastBlock) {
      return;
    }

    const from = state.lastBlock + 1;
    const blocksBehind = safeTo - state.lastBlock;
    const shouldEnterCatchUpMode = blocksBehind > 100;

    // Enter catch-up mode if significantly behind
    if (shouldEnterCatchUpMode && !state.inCatchupMode) {
      updateState({ inCatchupMode: true });
      state.inCatchupMode = true; // Update local copy
    }

    // Log catch-up status if in catch-up mode
    if (state.inCatchupMode) {
      console.log(`\n[CATCH-UP MODE] ${blocksBehind.toLocaleString()} blocks behind (${from} → ${safeTo})`);
    }

    const result = await fetchAllRedeemEvents(provider, from, safeTo, state, MAX_PAGES);

    // If no events found and we scanned all the way to safeTo, update to safeTo
    if (result.events.length === 0 && result.lastScannedBlock >= safeTo) {
      // Check if we just completed catch-up
      const wasCatchingUp = state.inCatchupMode;
      updateState({ lastBlock: safeTo, inCatchupMode: false });

      if (wasCatchingUp) {
        console.log(`\n✅ [CAUGHT UP] Now monitoring live blocks.`);
      }
      return;
    }

    // If we have events, process them
    if (result.events.length > 0) {
      result.events.sort((a, b) => (a.blockNumber - b.blockNumber) || (a.logIndex - b.logIndex));

      console.log(`Processing ${result.events.length} RedeemToTon events`);

      for (const ev of result.events) {
        await handleRedeemEvent(wallet, tonKeypair, ev);
      }
    }

    // CRITICAL FIX: Update lastBlock only to what we actually scanned, not to safeTo
    // This ensures we don't skip blocks if we hit MAX_PAGES limit
    const previousBlock = state.lastBlock;
    const blocksScanned = result.lastScannedBlock - previousBlock;
    const blocksRemaining = safeTo - result.lastScannedBlock;

    // Check if we completed catch-up in this poll
    const wasCatchingUp = state.inCatchupMode;
    const caughtUp = blocksRemaining === 0;

    updateState({
      lastBlock: result.lastScannedBlock,
      consecutiveErrors: 0,
      inCatchupMode: caughtUp ? false : state.inCatchupMode
    });

    // Log progress if in catch-up mode
    if (state.inCatchupMode && blocksRemaining > 0) {
      const progress = ((blocksBehind - blocksRemaining) / blocksBehind * 100).toFixed(1);
      console.log(`[PROGRESS] Scanned ${blocksScanned.toLocaleString()} blocks. ${blocksRemaining.toLocaleString()} remaining (${progress}% done)`);
    } else if (wasCatchingUp && caughtUp) {
      console.log(`\n✅ [CAUGHT UP] Now monitoring live blocks.`);
    }
  } finally {
    // Always cleanup provider after poll
    cleanupProvider(provider);
  }
}

async function main(): Promise<void> {
  console.log('Base → TON Watcher (via Aggregator with TON Multisig)');
  console.log('======================================================');
  console.log(`HTTP:                 ${BASE_HTTP_URL || '(ws used)'}`);
  console.log(`WS:                   ${BASE_WS_URL || '(http used)'}`);
  console.log(`MOFT:                 ${MOFT_ADDRESS}`);
  console.log(`Aggregator:           ${AGGREGATOR_URL}`);
  console.log(`Multisig (EVM):       ${MULTISIG_ADDRESS}`);
  console.log(`TON Multisig:         ${TON_MULTISIG_ADDRESS}`);
  console.log(`Chain ID:             ${BASE_CHAIN_ID}`);
  console.log(`Confirmations:        ${CONFIRMATIONS}`);
  console.log(`Poll Interval:        ${POLL_INTERVAL_MS}ms`);
  console.log(`Chunk Blocks:         ${CHUNK_BLOCKS}`);
  console.log(`TON Watcher Index:    ${TON_WATCHER_INDEX}`);
  console.log('======================================================\n');

  const wallet = new ethers.Wallet(WATCHER_PRIVATE_KEY);
  console.log(`Watcher EVM address:  ${wallet.address}`);

  // Initialize TON keypair
  const tonKeypair = keypairFromSecretKeyHex(TON_WATCHER_SECRET_KEY_HEX);
  console.log(`TON Public Key:       ${tonKeypair.publicKey.toString('hex')}\n`);

  let state = getState();

  for (;;) {
    const startTs = Date.now();
    try {
      await pollOnce(wallet, tonKeypair, state);
      state = getState(); // Refresh state
    } catch (e: any) {
      state.consecutiveErrors = (state.consecutiveErrors || 0) + 1;
      updateState({ consecutiveErrors: state.consecutiveErrors });

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

    const elapsed = Date.now() - startTs;
    const wait = Math.max(500, POLL_INTERVAL_MS - elapsed);
    await sleep(wait);
  }
}

if (require.main === module) {
  main().catch((e) => {
    console.error('Fatal:', e);
    process.exit(1);
  });
}
