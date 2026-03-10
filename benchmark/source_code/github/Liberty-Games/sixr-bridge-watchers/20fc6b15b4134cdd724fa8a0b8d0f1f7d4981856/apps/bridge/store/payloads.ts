/**
 * @file payloads.ts
 * @notice Payload persistence layer for the Bridge Aggregator
 *
 * This module provides CRUD operations for payloads in the SQLite database.
 */

import { getDatabase } from './database';
import { PayloadRow, PayloadInput, PayloadStatus, PayloadWithSignatures, BridgeDirection } from '../../shared/types';
import { getSignaturesByHash, getTonSignatureCount } from './signatures';

/**
 * Inserts a new payload into the database
 *
 * @param payload - Payload data
 * @throws Error if payload with same hash already exists
 */
export function insertPayload(payload: PayloadInput): void {
  const db = getDatabase();
  const now = Date.now();

  // Apply defaults for ton_mint retry fields
  const payloadWithDefaults = {
    ...payload,
    ton_mint_attempts: payload.ton_mint_attempts ?? 0n,
    ton_mint_next_retry: payload.ton_mint_next_retry ?? null,
  };

  const stmt = db.prepare(`
    INSERT INTO payloads (
      hash, origin_chain_id, token, recipient, amount, amount_raw9, nonce, ton_tx_id,
      status, created_at, updated_at, submitted_tx, error,
      direction,
      burn_tx_hash, burn_lt, burn_status, burn_timestamp,
      burn_chain_id, burn_block_number, burn_redeem_log_index, burn_transfer_log_index, burn_from_address, burn_confirmations,
      ton_recipient, ton_recipient_raw, ton_recipient_hash,
      ton_mint_tx_hash, ton_mint_lt, ton_mint_status, ton_mint_error, ton_mint_timestamp, ton_mint_attempts, ton_mint_next_retry,
      fee_amount
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  stmt.run(
    payloadWithDefaults.hash,
    payloadWithDefaults.origin_chain_id,
    payloadWithDefaults.token,
    payloadWithDefaults.recipient,
    payloadWithDefaults.amount,
    payloadWithDefaults.amount_raw9,
    payloadWithDefaults.nonce,
    payloadWithDefaults.ton_tx_id,
    payloadWithDefaults.status,
    now,
    now,
    payloadWithDefaults.submitted_tx,
    payloadWithDefaults.error,
    payloadWithDefaults.direction,
    payloadWithDefaults.burn_tx_hash,
    payloadWithDefaults.burn_lt,
    payloadWithDefaults.burn_status,
    payloadWithDefaults.burn_timestamp,
    payloadWithDefaults.burn_chain_id,
    payloadWithDefaults.burn_block_number,
    payloadWithDefaults.burn_redeem_log_index,
    payloadWithDefaults.burn_transfer_log_index,
    payloadWithDefaults.burn_from_address,
    payloadWithDefaults.burn_confirmations,
    payloadWithDefaults.ton_recipient,
    payloadWithDefaults.ton_recipient_raw,
    payloadWithDefaults.ton_recipient_hash,
    payloadWithDefaults.ton_mint_tx_hash,
    payloadWithDefaults.ton_mint_lt,
    payloadWithDefaults.ton_mint_status,
    payloadWithDefaults.ton_mint_error,
    payloadWithDefaults.ton_mint_timestamp,
    payloadWithDefaults.ton_mint_attempts,
    payloadWithDefaults.ton_mint_next_retry,
    payloadWithDefaults.fee_amount
  );
}

/**
 * Upserts a payload (insert or update if exists)
 *
 * IMPORTANT: If TON signatures exist for this payload, critical fields (amount_raw9, nonce, ton_recipient)
 * will NOT be updated. If you need to change these fields, you must first delete the TON signatures.
 *
 * @param payload - Payload data
 */
export function upsertPayload(payload: PayloadInput): void {
  const db = getDatabase();
  const now = Date.now();
  const existing = getPayloadByHash(payload.hash);

  // Apply defaults for ton_mint retry fields
  const payloadWithDefaults = {
    ...payload,
    ton_mint_attempts: payload.ton_mint_attempts ?? 0n,
    ton_mint_next_retry: payload.ton_mint_next_retry ?? null,
  };

  if (existing) {
    // Check if critical fields are changing when TON signatures exist
    const tonSigCount = getTonSignatureCount(payload.hash);
    const hasTonSignatures = tonSigCount > 0;

    if (hasTonSignatures) {
      // Detect if critical fields are changing
      const criticalFieldsChanged =
        (existing.amount_raw9 !== null && existing.amount_raw9 !== payloadWithDefaults.amount_raw9) ||
        (existing.nonce !== null && existing.nonce !== payloadWithDefaults.nonce) ||
        (existing.ton_recipient !== null && existing.ton_recipient !== payloadWithDefaults.ton_recipient);

      if (criticalFieldsChanged) {
        // CRITICAL: Prevent signature/payload mismatch by preserving original values
        // Log detailed warning for operators
        console.warn(
          `[PAYLOAD IMMUTABILITY] Attempted to update critical fields for payload ${payload.hash} ` +
          `that already has ${tonSigCount} TON signatures. Preserving original values to prevent ` +
          `SIGNATURE_PAYLOAD_MISMATCH. Original: { amount_raw9: ${existing.amount_raw9}, ` +
          `nonce: ${existing.nonce}, ton_recipient: ${existing.ton_recipient} }, ` +
          `Attempted: { amount_raw9: ${payloadWithDefaults.amount_raw9}, ` +
          `nonce: ${payloadWithDefaults.nonce}, ton_recipient: ${payloadWithDefaults.ton_recipient} }. ` +
          `To change these fields, first delete the TON signatures.`
        );

        // Preserve original values
        payloadWithDefaults.amount_raw9 = existing.amount_raw9;
        payloadWithDefaults.nonce = existing.nonce;
        payloadWithDefaults.ton_recipient = existing.ton_recipient;
      }
    }

    // Update existing payload
    const stmt = db.prepare(`
      UPDATE payloads
      SET origin_chain_id = ?,
          token = ?,
          recipient = ?,
          amount = ?,
          amount_raw9 = ?,
          nonce = ?,
          ton_tx_id = ?,
          status = ?,
          updated_at = ?,
          submitted_tx = ?,
          error = ?,
          direction = ?,
          burn_tx_hash = ?,
          burn_lt = ?,
          burn_status = ?,
          burn_timestamp = ?,
          burn_chain_id = ?,
          burn_block_number = ?,
          burn_redeem_log_index = ?,
          burn_transfer_log_index = ?,
          burn_from_address = ?,
          burn_confirmations = ?,
          ton_recipient = ?,
          ton_recipient_raw = ?,
          ton_recipient_hash = ?,
          ton_mint_tx_hash = ?,
          ton_mint_lt = ?,
          ton_mint_status = ?,
          ton_mint_error = ?,
          ton_mint_timestamp = ?,
          ton_mint_attempts = ?,
          ton_mint_next_retry = ?,
          fee_amount = ?
      WHERE hash = ?
    `);

    stmt.run(
      payloadWithDefaults.origin_chain_id,
      payloadWithDefaults.token,
      payloadWithDefaults.recipient,
      payloadWithDefaults.amount,
      payloadWithDefaults.amount_raw9,
      payloadWithDefaults.nonce,
      payloadWithDefaults.ton_tx_id,
      payloadWithDefaults.status,
      now,
      payloadWithDefaults.submitted_tx,
      payloadWithDefaults.error,
      payloadWithDefaults.direction,
      payloadWithDefaults.burn_tx_hash,
      payloadWithDefaults.burn_lt,
      payloadWithDefaults.burn_status,
      payloadWithDefaults.burn_timestamp,
      payloadWithDefaults.burn_chain_id,
      payloadWithDefaults.burn_block_number,
      payloadWithDefaults.burn_redeem_log_index,
      payloadWithDefaults.burn_transfer_log_index,
      payloadWithDefaults.burn_from_address,
      payloadWithDefaults.burn_confirmations,
      payloadWithDefaults.ton_recipient,
      payloadWithDefaults.ton_recipient_raw,
      payloadWithDefaults.ton_recipient_hash,
      payloadWithDefaults.ton_mint_tx_hash,
      payloadWithDefaults.ton_mint_lt,
      payloadWithDefaults.ton_mint_status,
      payloadWithDefaults.ton_mint_error,
      payloadWithDefaults.ton_mint_timestamp,
      payloadWithDefaults.ton_mint_attempts,
      payloadWithDefaults.ton_mint_next_retry,
      payloadWithDefaults.fee_amount,
      payloadWithDefaults.hash
    );
  } else {
    // Insert new payload
    insertPayload(payloadWithDefaults);
  }
}

/**
 * Gets a payload by hash
 *
 * @param hash - Payload hash
 * @returns Payload or null if not found
 */
export function getPayloadByHash(hash: string): PayloadRow | null {
  const db = getDatabase();
  const stmt = db.prepare('SELECT * FROM payloads WHERE hash = ?');
  const row = stmt.get(hash) as PayloadRow | undefined;
  return row ?? null;
}

/**
 * Gets a payload with signatures by hash
 *
 * @param hash - Payload hash
 * @returns Payload with signatures or null if not found
 */
export function getPayloadWithSignatures(hash: string): PayloadWithSignatures | null {
  const payload = getPayloadByHash(hash);
  if (!payload) {
    return null;
  }

  const signatures = getSignaturesByHash(hash);

  return {
    hash: payload.hash,
    originChainId: payload.origin_chain_id,
    token: payload.token,
    recipient: payload.recipient,
    amount: payload.amount,
    amountRaw9: payload.amount_raw9,
    nonce: payload.nonce.toString(),
    tonTxId: payload.ton_tx_id,
    status: payload.status,
    createdAt: payload.created_at,
    updatedAt: payload.updated_at,
    submittedTx: payload.submitted_tx,
    error: payload.error,
    direction: payload.direction,
    burnTxHash: payload.burn_tx_hash,
    burnLt: payload.burn_lt?.toString() ?? null,
    burnStatus: payload.burn_status,
    burnTimestamp: payload.burn_timestamp,
    burnChainId: payload.burn_chain_id,
    burnBlockNumber: payload.burn_block_number,
    burnRedeemLogIndex: payload.burn_redeem_log_index,
    burnTransferLogIndex: payload.burn_transfer_log_index,
    burnFromAddress: payload.burn_from_address,
    burnConfirmations: payload.burn_confirmations,
    tonRecipient: payload.ton_recipient,
    tonRecipientRaw: payload.ton_recipient_raw,
    tonRecipientHash: payload.ton_recipient_hash,
    tonMintTxHash: payload.ton_mint_tx_hash,
    tonMintLt: payload.ton_mint_lt?.toString() ?? null,
    tonMintStatus: payload.ton_mint_status,
    tonMintError: payload.ton_mint_error,
    tonMintTimestamp: payload.ton_mint_timestamp,
    tonMintAttempts: payload.ton_mint_attempts?.toString() ?? null,
    tonMintNextRetry: payload.ton_mint_next_retry,
    feeAmount: payload.fee_amount,
    signatures: signatures.map((sig) => ({
      watcher: sig.watcher,
      signature: sig.signature,
    })),
  };
}

/**
 * Gets all payloads with a specific status
 *
 * @param status - Payload status
 * @param limit - Maximum number of results
 * @returns Array of payloads
 */
export function getPayloadsByStatus(status: PayloadStatus, limit?: number): PayloadRow[] {
  const db = getDatabase();
  const sql = limit
    ? 'SELECT * FROM payloads WHERE status = ? ORDER BY nonce ASC LIMIT ?'
    : 'SELECT * FROM payloads WHERE status = ? ORDER BY nonce ASC';

  const stmt = db.prepare(sql);
  const rows = limit ? stmt.all(status, limit) : stmt.all(status);
  return rows as PayloadRow[];
}

/**
 * Updates a payload's status
 *
 * @param hash - Payload hash
 * @param status - New status
 */
export function updatePayloadStatus(hash: string, status: PayloadStatus): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare('UPDATE payloads SET status = ?, updated_at = ? WHERE hash = ?');
  stmt.run(status, now, hash);
}

/**
 * Updates a payload's submitted transaction hash
 *
 * @param hash - Payload hash
 * @param txHash - Transaction hash
 */
export function updatePayloadSubmittedTx(hash: string, txHash: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET submitted_tx = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run(txHash, now, hash);
}

/**
 * Updates a payload's error message
 *
 * @param hash - Payload hash
 * @param error - Error message
 */
export function updatePayloadError(hash: string, error: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare('UPDATE payloads SET error = ?, updated_at = ? WHERE hash = ?');
  stmt.run(error, now, hash);
}

/**
 * Updates a payload to submitted status with transaction hash
 *
 * @param hash - Payload hash
 * @param txHash - Transaction hash
 */
export function markPayloadSubmitted(hash: string, txHash: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET status = ?, submitted_tx = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run('submitted', txHash, now, hash);
}

/**
 * Updates a payload to finalized status
 *
 * @param hash - Payload hash
 */
export function markPayloadFinalized(hash: string): void {
  updatePayloadStatus(hash, 'finalized');
}

/**
 * Updates a payload to failed status with error message
 *
 * @param hash - Payload hash
 * @param error - Error message
 */
export function markPayloadFailed(hash: string, error: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET status = ?, error = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run('failed', error, now, hash);
}

/**
 * Checks if a payload should be marked as ready (has quorum)
 * and updates status if needed
 *
 * For EVM_TO_TON payloads: checks TON signature quorum (≥2 unique ton_public_key)
 * For TON_TO_EVM payloads: checks EVM signature quorum (≥2 unique watcher)
 *
 * @param hash - Payload hash
 * @param threshold - Signature threshold (default: 2)
 * @returns True if payload is now ready
 */
export function checkAndUpdateReadyStatus(hash: string, threshold: number = 2): boolean {
  const db = getDatabase();

  // Get current payload to determine direction
  const payload = getPayloadByHash(hash);
  if (!payload) {
    return false;
  }

  let signatureCount = 0;

  if (payload.direction === 'EVM_TO_TON') {
    // For EVM -> TON, check TON signatures (unique ton_public_key)
    signatureCount = getTonSignatureCount(hash);
  } else {
    // For TON -> EVM, check EVM signatures (unique watcher)
    const countStmt = db.prepare('SELECT COUNT(*) as count FROM payload_signatures WHERE hash = ?');
    const result = countStmt.get(hash) as { count: number };
    signatureCount = result.count;
  }

  // Update to ready if quorum met and status is pending
  if (signatureCount >= threshold && payload.status === 'pending') {
    updatePayloadStatus(hash, 'ready');
    return true;
  }

  return payload.status === 'ready';
}

/**
 * Gets count of payloads by status
 *
 * @returns Object with status counts
 */
export function getPayloadCounts(): Record<PayloadStatus, number> {
  const db = getDatabase();

  const counts: Record<PayloadStatus, number> = {
    pending: 0,
    ready: 0,
    burn_pending: 0,
    burn_submitted: 0,
    burn_confirmed: 0,
    ton_mint_pending: 0,
    ton_mint_submitted: 0,
    ton_mint_confirmed: 0,
    submitted: 0,
    finalized: 0,
    failed: 0,
  };

  const stmt = db.prepare('SELECT status, COUNT(*) as count FROM payloads GROUP BY status');
  const rows = stmt.all() as Array<{ status: PayloadStatus; count: number }>;

  for (const row of rows) {
    counts[row.status] = row.count;
  }

  return counts;
}

/**
 * Gets TON Multisig specific counts (EVM -> TON flow)
 *
 * @returns Object with TON multisig specific counts
 */
export function getTonMultisigCounts(): {
  ready: number;
  pending: number;
  submitted: number;
  confirmed: number;
  failed: number;
} {
  const db = getDatabase();

  // Count payloads ready for TON mint (direction = EVM_TO_TON, status = ready)
  const readyStmt = db.prepare(
    'SELECT COUNT(*) as count FROM payloads WHERE direction = ? AND status = ?'
  );
  const readyCount = (readyStmt.get('EVM_TO_TON', 'ready') as { count: number }).count;

  // Count payloads in ton_mint_pending status
  const pendingStmt = db.prepare('SELECT COUNT(*) as count FROM payloads WHERE status = ?');
  const pendingCount = (pendingStmt.get('ton_mint_pending') as { count: number }).count;

  // Count payloads in ton_mint_submitted status
  const submittedStmt = db.prepare('SELECT COUNT(*) as count FROM payloads WHERE status = ?');
  const submittedCount = (submittedStmt.get('ton_mint_submitted') as { count: number }).count;

  // Count payloads in ton_mint_confirmed status
  const confirmedStmt = db.prepare('SELECT COUNT(*) as count FROM payloads WHERE status = ?');
  const confirmedCount = (confirmedStmt.get('ton_mint_confirmed') as { count: number }).count;

  // Count failed payloads in EVM_TO_TON direction
  const failedStmt = db.prepare(
    'SELECT COUNT(*) as count FROM payloads WHERE direction = ? AND status = ?'
  );
  const failedCount = (failedStmt.get('EVM_TO_TON', 'failed') as { count: number }).count;

  return {
    ready: readyCount,
    pending: pendingCount,
    submitted: submittedCount,
    confirmed: confirmedCount,
    failed: failedCount,
  };
}

/**
 * Gets the oldest pending payload age in milliseconds
 *
 * @returns Age in milliseconds or null if no pending payloads
 */
export function getOldestPendingAge(): number | null {
  const db = getDatabase();

  const stmt = db.prepare(
    "SELECT MIN(created_at) as oldest FROM payloads WHERE status IN ('pending', 'ready')"
  );
  const row = stmt.get() as { oldest: number | null };

  if (!row.oldest) {
    return null;
  }

  return Date.now() - row.oldest;
}

/**
 * Gets payloads that need retry (failed with backoff expired)
 * Only returns TON_TO_EVM payloads for submission worker
 *
 * @param backoffMs - Minimum time since last update before retry
 * @param limit - Maximum number of results
 * @returns Array of failed payloads ready for retry
 */
export function getRetryablePayloads(backoffMs: number, limit?: number): PayloadRow[] {
  const db = getDatabase();
  const cutoff = Date.now() - backoffMs;

  const sql = limit
    ? 'SELECT * FROM payloads WHERE status = ? AND direction = ? AND updated_at <= ? ORDER BY updated_at ASC LIMIT ?'
    : 'SELECT * FROM payloads WHERE status = ? AND direction = ? AND updated_at <= ? ORDER BY updated_at ASC';

  const stmt = db.prepare(sql);
  const rows = limit
    ? stmt.all('failed', 'TON_TO_EVM', cutoff, limit)
    : stmt.all('failed', 'TON_TO_EVM', cutoff);
  return rows as PayloadRow[];
}

/**
 * Deletes a payload and its signatures
 *
 * @param hash - Payload hash
 */
export function deletePayload(hash: string): void {
  const db = getDatabase();

  // Foreign key cascade will delete signatures
  const stmt = db.prepare('DELETE FROM payloads WHERE hash = ?');
  stmt.run(hash);
}

/**
 * Gets all payloads (with pagination)
 *
 * @param limit - Maximum number of results
 * @param offset - Offset for pagination
 * @returns Array of payloads
 */
export function getAllPayloads(limit?: number, offset?: number): PayloadRow[] {
  const db = getDatabase();

  let sql = 'SELECT * FROM payloads ORDER BY created_at DESC';
  const params: number[] = [];

  if (limit !== undefined) {
    sql += ' LIMIT ?';
    params.push(limit);
  }

  if (offset !== undefined) {
    sql += ' OFFSET ?';
    params.push(offset);
  }

  const stmt = db.prepare(sql);
  const rows = stmt.all(...params);
  return rows as PayloadRow[];
}

/**
 * Updates payload burn transaction hash and status
 *
 * @param hash - Payload hash
 * @param burnTxHash - TON burn transaction hash
 * @param burnStatus - Burn status
 */
export function updatePayloadBurn(
  hash: string,
  burnTxHash: string,
  burnStatus: 'pending' | 'submitted' | 'confirmed' | 'failed'
): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET burn_tx_hash = ?, burn_status = ?, burn_timestamp = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run(burnTxHash, burnStatus, now, now, hash);
}

/**
 * Updates payload burn logical time (lt)
 *
 * @param hash - Payload hash
 * @param burnLt - TON logical time
 */
export function updatePayloadBurnLt(hash: string, burnLt: bigint): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare('UPDATE payloads SET burn_lt = ?, updated_at = ? WHERE hash = ?');
  stmt.run(burnLt, now, hash);
}

/**
 * Marks a payload as burn pending
 *
 * @param hash - Payload hash
 */
export function markPayloadBurnPending(hash: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET status = ?, burn_status = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run('burn_pending', 'pending', now, hash);
}

/**
 * Marks a payload burn as submitted
 *
 * @param hash - Payload hash
 * @param burnTxHash - TON burn transaction hash
 */
export function markPayloadBurnSubmitted(hash: string, burnTxHash: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET status = ?, burn_tx_hash = ?, burn_status = ?, burn_timestamp = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run('burn_submitted', burnTxHash, 'submitted', now, now, hash);
}

/**
 * Marks a payload burn as confirmed
 *
 * @param hash - Payload hash
 * @param burnLt - TON logical time (optional)
 */
export function markPayloadBurnConfirmed(hash: string, burnLt?: bigint): void {
  const db = getDatabase();
  const now = Date.now();

  if (burnLt !== undefined) {
    const stmt = db.prepare(
      'UPDATE payloads SET status = ?, burn_status = ?, burn_lt = ?, updated_at = ? WHERE hash = ?'
    );
    stmt.run('burn_confirmed', 'confirmed', burnLt, now, hash);
  } else {
    const stmt = db.prepare(
      'UPDATE payloads SET status = ?, burn_status = ?, updated_at = ? WHERE hash = ?'
    );
    stmt.run('burn_confirmed', 'confirmed', now, hash);
  }
}

/**
 * Marks a payload burn as failed
 *
 * @param hash - Payload hash
 * @param error - Error message
 */
export function markPayloadBurnFailed(hash: string, error: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET burn_status = ?, error = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run('failed', error, now, hash);
}

/**
 * Gets payloads that are ready for burn (status = 'ready')
 *
 * @param limit - Maximum number of results
 * @returns Array of payloads ready for burn
 */
export function getPayloadsReadyForBurn(limit?: number): PayloadRow[] {
  return getPayloadsByStatus('ready', limit);
}

/**
 * Gets payloads that have burn submitted and need confirmation check
 *
 * @param limit - Maximum number of results
 * @returns Array of payloads with burn submitted
 */
export function getPayloadsWithBurnSubmitted(limit?: number): PayloadRow[] {
  return getPayloadsByStatus('burn_submitted', limit);
}

/**
 * Gets payloads with burn confirmed, ready for EVM submission
 *
 * @param limit - Maximum number of results
 * @returns Array of payloads with burn confirmed
 */
export function getPayloadsWithBurnConfirmed(limit?: number): PayloadRow[] {
  return getPayloadsByStatus('burn_confirmed', limit);
}

/**
 * Gets payloads ready for EVM submission (burn confirmed, TON_TO_EVM direction only)
 *
 * @param limit - Maximum number of results
 * @returns Array of payloads ready for EVM submission
 */
export function getPayloadsReadyForSubmission(limit?: number): PayloadRow[] {
  const db = getDatabase();
  const sql = limit
    ? 'SELECT * FROM payloads WHERE status = ? AND direction = ? ORDER BY nonce ASC LIMIT ?'
    : 'SELECT * FROM payloads WHERE status = ? AND direction = ? ORDER BY nonce ASC';

  const stmt = db.prepare(sql);
  const rows = limit
    ? stmt.all('burn_confirmed', 'TON_TO_EVM', limit)
    : stmt.all('burn_confirmed', 'TON_TO_EVM');
  return rows as PayloadRow[];
}

/* ============================================================================
 * TON Mint Functions (EVM -> TON)
 * ========================================================================== */

/**
 * Gets payloads ready for TON mint (direction = EVM_TO_TON, status = ready)
 *
 * @param limit - Maximum number of results
 * @returns Array of payloads ready for TON mint
 */
export function getPayloadsReadyForTonMint(limit?: number): PayloadRow[] {
  const db = getDatabase();
  const sql = limit
    ? 'SELECT * FROM payloads WHERE direction = ? AND status = ? ORDER BY nonce ASC LIMIT ?'
    : 'SELECT * FROM payloads WHERE direction = ? AND status = ? ORDER BY nonce ASC';

  const stmt = db.prepare(sql);
  const rows = limit ? stmt.all('EVM_TO_TON', 'ready', limit) : stmt.all('EVM_TO_TON', 'ready');
  return rows as PayloadRow[];
}

/**
 * Gets payloads with TON mint submitted, awaiting confirmation
 *
 * @param limit - Maximum number of results
 * @returns Array of payloads with TON mint submitted
 */
export function getPayloadsWithTonMintSubmitted(limit?: number): PayloadRow[] {
  return getPayloadsByStatus('ton_mint_submitted', limit);
}

/**
 * Marks a payload as TON mint pending
 *
 * @param hash - Payload hash
 */
export function markPayloadTonMintPending(hash: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET status = ?, ton_mint_status = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run('ton_mint_pending', 'pending', now, hash);
}

/**
 * Marks a payload TON mint as submitted
 *
 * @param hash - Payload hash
 * @param tonMintTxHash - TON mint transaction hash/identifier
 */
export function markPayloadTonMintSubmitted(hash: string, tonMintTxHash: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET status = ?, ton_mint_tx_hash = ?, ton_mint_status = ?, ton_mint_timestamp = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run('ton_mint_submitted', tonMintTxHash, 'submitted', now, now, hash);
}

/**
 * Marks a payload TON mint as confirmed
 *
 * @param hash - Payload hash
 * @param tonMintLt - TON logical time (optional)
 */
export function markPayloadTonMintConfirmed(hash: string, tonMintLt?: bigint): void {
  const db = getDatabase();
  const now = Date.now();

  if (tonMintLt !== undefined) {
    const stmt = db.prepare(
      'UPDATE payloads SET status = ?, ton_mint_status = ?, ton_mint_lt = ?, updated_at = ? WHERE hash = ?'
    );
    stmt.run('ton_mint_confirmed', 'confirmed', tonMintLt, now, hash);
  } else {
    const stmt = db.prepare(
      'UPDATE payloads SET status = ?, ton_mint_status = ?, updated_at = ? WHERE hash = ?'
    );
    stmt.run('ton_mint_confirmed', 'confirmed', now, hash);
  }
}

/**
 * Marks a payload TON mint as failed
 *
 * @param hash - Payload hash
 * @param error - Error message
 */
export function markPayloadTonMintFailed(hash: string, error: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET ton_mint_status = ?, ton_mint_error = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run('failed', error, now, hash);
}

/**
 * Updates payload TON mint transaction details
 *
 * @param hash - Payload hash
 * @param tonMintTxHash - TON mint transaction hash
 * @param tonMintLt - TON logical time
 * @param tonMintStatus - Mint status
 */
export function updatePayloadTonMint(
  hash: string,
  tonMintTxHash: string,
  tonMintLt: bigint | null,
  tonMintStatus: string
): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET ton_mint_tx_hash = ?, ton_mint_lt = ?, ton_mint_status = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run(tonMintTxHash, tonMintLt, tonMintStatus, now, hash);
}

/**
 * Gets payloads by direction
 *
 * @param direction - Bridge direction
 * @param limit - Maximum number of results
 * @returns Array of payloads
 */
export function getPayloadsByDirection(direction: BridgeDirection, limit?: number): PayloadRow[] {
  const db = getDatabase();
  const sql = limit
    ? 'SELECT * FROM payloads WHERE direction = ? ORDER BY created_at DESC LIMIT ?'
    : 'SELECT * FROM payloads WHERE direction = ? ORDER BY created_at DESC';

  const stmt = db.prepare(sql);
  const rows = limit ? stmt.all(direction, limit) : stmt.all(direction);
  return rows as PayloadRow[];
}

/**
 * Gets payloads by direction and status
 *
 * @param direction - Bridge direction
 * @param status - Payload status
 * @param limit - Maximum number of results
 * @returns Array of payloads
 */
export function getPayloadsByDirectionAndStatus(
  direction: BridgeDirection,
  status: PayloadStatus,
  limit?: number
): PayloadRow[] {
  const db = getDatabase();
  const sql = limit
    ? 'SELECT * FROM payloads WHERE direction = ? AND status = ? ORDER BY nonce ASC LIMIT ?'
    : 'SELECT * FROM payloads WHERE direction = ? AND status = ? ORDER BY nonce ASC';

  const stmt = db.prepare(sql);
  const rows = limit ? stmt.all(direction, status, limit) : stmt.all(direction, status);
  return rows as PayloadRow[];
}

/* ============================================================================
 * TON Mint Retry Functions
 * ========================================================================== */

/**
 * Updates TON mint retry metadata
 *
 * @param hash - Payload hash
 * @param attempts - Number of mint attempts
 * @param nextRetry - Timestamp when next retry is allowed
 */
export function updateTonMintRetry(hash: string, attempts: bigint, nextRetry: number | null): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET ton_mint_attempts = ?, ton_mint_next_retry = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run(attempts, nextRetry, now, hash);
}

/**
 * Increments TON mint attempts and sets next retry time with exponential backoff
 *
 * @param hash - Payload hash
 * @param baseBackoffMs - Base backoff time in milliseconds (default: 5000ms = 5s)
 * @param maxBackoffMs - Maximum backoff time in milliseconds (default: 300000ms = 5min)
 */
export function incrementTonMintAttempts(
  hash: string,
  baseBackoffMs: number = 5000,
  maxBackoffMs: number = 300000
): void {
  const db = getDatabase();
  const payload = getPayloadByHash(hash);
  if (!payload) {
    throw new Error(`Payload not found: ${hash}`);
  }

  const attempts = (payload.ton_mint_attempts || 0n) + 1n;
  const attemptsNum = Number(attempts);
  const backoff = Math.min(baseBackoffMs * Math.pow(2, attemptsNum - 1), maxBackoffMs);
  const nextRetry = Date.now() + backoff;

  updateTonMintRetry(hash, attempts, nextRetry);
}

/**
 * Clears TON mint retry metadata (resets attempts and next retry time)
 *
 * @param hash - Payload hash
 */
export function clearTonMintRetry(hash: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET ton_mint_attempts = 0, ton_mint_next_retry = NULL, updated_at = ? WHERE hash = ?'
  );
  stmt.run(now, hash);
}

/**
 * Increments TON mint confirmation retry attempts with exponential backoff
 * Used for Toncenter API failures (5xx, 429) during confirmation checks
 *
 * @param hash - Payload hash
 * @param baseBackoffMs - Base backoff time in milliseconds (default: 15000ms = 15s)
 * @param multiplier - Backoff multiplier (default: 2.0)
 * @param maxBackoffMs - Maximum backoff time in milliseconds (default: 300000ms = 5min)
 */
export function incrementTonMintConfirmationRetry(
  hash: string,
  baseBackoffMs: number = 15000,
  multiplier: number = 2.0,
  maxBackoffMs: number = 300000
): void {
  const db = getDatabase();
  const payload = getPayloadByHash(hash);
  if (!payload) {
    throw new Error(`Payload not found: ${hash}`);
  }

  const attempts = (payload.ton_mint_attempts || 0n) + 1n;
  const attemptsNum = Number(attempts);
  const backoff = Math.min(baseBackoffMs * Math.pow(multiplier, attemptsNum - 1), maxBackoffMs);
  const nextRetry = Date.now() + backoff;

  updateTonMintRetry(hash, attempts, nextRetry);
}

/**
 * Marks a payload as failed due to Toncenter HTTP errors
 *
 * @param hash - Payload hash
 * @param error - Error message
 */
export function markPayloadTonMintFailedToncenterError(hash: string, error: string): void {
  const db = getDatabase();
  const now = Date.now();

  const stmt = db.prepare(
    'UPDATE payloads SET status = ?, ton_mint_status = ?, ton_mint_error = ?, updated_at = ? WHERE hash = ?'
  );
  stmt.run('failed', 'failed', error, now, hash);
}

/**
 * Gets payloads with TON mint submitted that are ready for confirmation check
 * (respects ton_mint_next_retry backoff)
 *
 * @param limit - Maximum number of results
 * @returns Array of payloads ready for confirmation check
 */
export function getPayloadsReadyForConfirmationCheck(limit?: number): PayloadRow[] {
  const db = getDatabase();
  const now = Date.now();

  const sql = limit
    ? 'SELECT * FROM payloads WHERE status = ? AND (ton_mint_next_retry IS NULL OR ton_mint_next_retry <= ?) ORDER BY created_at ASC LIMIT ?'
    : 'SELECT * FROM payloads WHERE status = ? AND (ton_mint_next_retry IS NULL OR ton_mint_next_retry <= ?) ORDER BY created_at ASC';

  const stmt = db.prepare(sql);
  const rows = limit
    ? stmt.all('ton_mint_submitted', now, limit)
    : stmt.all('ton_mint_submitted', now);
  return rows as PayloadRow[];
}
