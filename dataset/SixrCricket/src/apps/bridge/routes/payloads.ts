/**
 * @file payloads.ts
 * @notice REST API routes for payload management
 */

import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { BridgeConfig } from '../config';
import { getLogger } from '../logger';
import {
  buildPayload,
  computeDigest,
  buildDomain,
  hashMintPayload,
  normalizeAddress,
} from '../../shared/payload';
import { validateWatcherSignature } from '../../shared/signature';
import { PayloadSubmissionInput } from '../../shared/types';
import {
  upsertPayload,
  getPayloadWithSignatures,
  updatePayloadStatus,
  checkAndUpdateReadyStatus,
} from '../store/payloads';
import { upsertSignature, getSignatureCount } from '../store/signatures';
import { transaction } from '../store/database';
import { handleEvmToTonSubmission } from './evm-to-ton-payloads';
import { toJsonPayload } from '../../shared/serializer';

/**
 * Zod schema for payload submission
 */
const PayloadSubmissionSchema = z.object({
  originChainId: z.number().int().nonnegative(),
  token: z.string().regex(/^0x[a-fA-F0-9]{40}$/),
  recipient: z.string().regex(/^0x[a-fA-F0-9]{40}$/),
  amountRaw9: z.string().regex(/^\d+$/),
  nonce: z.string().regex(/^\d+$/),
  watcher: z.string().regex(/^0x[a-fA-F0-9]{40}$/),
  signature: z.string().regex(/^0x[a-fA-F0-9]{130}$/),
  tonTxId: z.string().min(1),
  feeAmount: z.string().regex(/^\d+$/).optional(),
});

/**
 * Creates the payloads router
 *
 * @param config - Bridge configuration
 * @returns Express router
 */
export function createPayloadsRouter(config: BridgeConfig): Router {
  const router = Router();
  const logger = getLogger();

  /**
   * POST /payloads
   * Submits a new payload with watcher signature
   * Supports both TON -> EVM and EVM -> TON directions
   */
  router.post('/', async (req: Request, res: Response) => {
    try {
      // Check direction and route to appropriate handler
      if (req.body.direction === 'EVM_TO_TON') {
        return await handleEvmToTonSubmission(req, res, config);
      }

      // TON -> EVM flow (existing logic)
      // Validate request body
      const input = PayloadSubmissionSchema.parse(req.body) as PayloadSubmissionInput;

      logger.info('Received payload submission', {
        hash: 'computing...',
        watcher: input.watcher,
        tonTxId: input.tonTxId,
      });

      // Build canonical payload
      const payload = buildPayload(
        input.originChainId,
        input.token,
        input.recipient,
        input.amountRaw9,
        input.nonce,
        config.token.decimals
      );

      // Compute payload hash
      const structHash = hashMintPayload(payload);

      // Detect target chain based on token address
      const normalizedToken = normalizeAddress(input.token, 'token');
      let targetChain: 'base' | 'bsc';
      let chainConfig: NonNullable<typeof config.base>;

      if (config.base && normalizedToken === config.base.oftAddress) {
        targetChain = 'base';
        chainConfig = config.base;
      } else if (config.bsc && normalizedToken === config.bsc.oftAddress) {
        targetChain = 'bsc';
        chainConfig = config.bsc;
      } else {
        const expectedTokens: string[] = [];
        if (config.base) expectedTokens.push(`${config.base.oftAddress} (Base)`);
        if (config.bsc) expectedTokens.push(`${config.bsc.oftAddress} (BSC)`);
        return res.status(400).json({
          error: 'Invalid token',
          message: `Token ${normalizedToken} is not recognized. Expected: ${expectedTokens.join(' or ')}`,
        });
      }

      // Build domain for the target chain
      const domain = buildDomain(chainConfig.chainId, chainConfig.multisigAddress);

      // Compute digest
      const digest = computeDigest(payload, domain);

      logger.info('Computed payload digest', {
        hash: digest,
        structHash,
        originChainId: input.originChainId,
        token: input.token,
        recipient: input.recipient,
        amount: payload.amount,
        nonce: input.nonce,
      });

      // Validate signature
      let signerAddress: string;
      try {
        signerAddress = validateWatcherSignature(
          payload,
          domain,
          input.signature,
          config.watchers.addresses
        );
      } catch (err) {
        logger.warn('Invalid watcher signature', {
          hash: digest,
          watcher: input.watcher,
          error: err instanceof Error ? err.message : String(err),
        });

        return res.status(400).json({
          error: 'Invalid signature',
          message: err instanceof Error ? err.message : String(err),
        });
      }

      // Verify claimed watcher matches signer
      const normalizedWatcher = normalizeAddress(input.watcher, 'watcher');
      if (signerAddress !== normalizedWatcher) {
        logger.warn('Watcher mismatch', {
          hash: digest,
          claimed: normalizedWatcher,
          recovered: signerAddress,
        });

        return res.status(400).json({
          error: 'Watcher mismatch',
          message: `Claimed watcher ${normalizedWatcher} does not match signature signer ${signerAddress}`,
        });
      }

      // Store payload and signature in transaction
      transaction(() => {
        // Upsert payload (TON -> EVM)
        upsertPayload({
          hash: digest,
          origin_chain_id: input.originChainId,
          token: payload.token,
          recipient: payload.recipient,
          amount: payload.amount,
          amount_raw9: input.amountRaw9,
          nonce: BigInt(input.nonce),
          ton_tx_id: input.tonTxId,
          status: 'pending',
          submitted_tx: null,
          error: null,
          direction: 'TON_TO_EVM',
          burn_tx_hash: null,
          burn_lt: null,
          burn_status: null,
          burn_timestamp: null,
          burn_chain_id: null,
          burn_block_number: null,
          burn_redeem_log_index: null,
          burn_transfer_log_index: null,
          burn_from_address: null,
          burn_confirmations: null,
          ton_recipient: null,
          ton_recipient_raw: null,
          ton_recipient_hash: null,
          ton_mint_tx_hash: null,
          ton_mint_lt: null,
          ton_mint_status: null,
          ton_mint_error: null,
          ton_mint_timestamp: null,
          ton_mint_attempts: 0n,
          ton_mint_next_retry: null,
          fee_amount: input.feeAmount ?? null,
        });

        // Upsert signature
        upsertSignature(digest, signerAddress, input.signature);

        logger.info('Stored payload and signature', {
          hash: digest,
          watcher: signerAddress,
          tonTxId: input.tonTxId,
        });
      });

      // Check if quorum is met and update status
      const isReady = checkAndUpdateReadyStatus(digest, config.watchers.threshold);

      if (isReady) {
        logger.info('Payload reached quorum', {
          hash: digest,
          signatureCount: getSignatureCount(digest),
          threshold: config.watchers.threshold,
        });
      }

      // Fetch and return payload with signatures
      const result = getPayloadWithSignatures(digest);

      if (!result) {
        logger.error('Failed to fetch payload after insert', { hash: digest });
        return res.status(500).json({
          error: 'Internal error',
          message: 'Failed to fetch payload after insert',
        });
      }

      logger.info('Payload submission successful', {
        hash: digest,
        status: result.status,
        signatureCount: result.signatures.length,
      });

      // Return payload directly for backward compatibility with watchers
      return res.status(200).json(toJsonPayload(result));
    } catch (err) {
      if (err instanceof z.ZodError) {
        logger.warn('Invalid payload submission input', {
          errors: err.errors,
        });

        return res.status(400).json({
          error: 'Validation error',
          details: err.errors,
        });
      }

      logger.error('Payload submission failed', {
        error: err instanceof Error ? err.message : String(err),
        stack: err instanceof Error ? err.stack : undefined,
      });

      return res.status(500).json({
        error: 'Internal error',
        message: err instanceof Error ? err.message : String(err),
      });
    }
  });

  /**
   * GET /payloads/:hash
   * Gets a payload by hash with all signatures
   */
  router.get('/:hash', (req: Request, res: Response) => {
    try {
      const { hash } = req.params;

      logger.debug('Fetching payload', { hash });

      const payload = getPayloadWithSignatures(hash);

      if (!payload) {
        logger.warn('Payload not found', { hash });
        return res.status(404).json({
          error: 'Not found',
          message: `Payload with hash ${hash} not found`,
        });
      }

      logger.debug('Payload fetched', { hash, status: payload.status });

      return res.status(200).json({
        success: true,
        payload: toJsonPayload(payload),
      });
    } catch (err) {
      logger.error('Failed to fetch payload', {
        hash: req.params.hash,
        error: err instanceof Error ? err.message : String(err),
      });

      return res.status(500).json({
        error: 'Internal error',
        message: err instanceof Error ? err.message : String(err),
      });
    }
  });

  /**
   * POST /payloads/:hash/retry
   * Manually retry a failed payload
   */
  router.post('/:hash/retry', (req: Request, res: Response) => {
    try {
      const { hash } = req.params;

      logger.info('Manual retry requested', { hash });

      const payload = getPayloadWithSignatures(hash);

      if (!payload) {
        logger.warn('Payload not found for retry', { hash });
        return res.status(404).json({
          error: 'Not found',
          message: `Payload with hash ${hash} not found`,
        });
      }

      if (payload.status !== 'failed') {
        logger.warn('Cannot retry non-failed payload', {
          hash,
          status: payload.status,
        });
        return res.status(400).json({
          error: 'Invalid status',
          message: `Cannot retry payload with status ${payload.status}. Only failed payloads can be retried.`,
        });
      }

      // Reset to ready status for worker to pick up
      updatePayloadStatus(hash, 'ready');

      logger.info('Payload marked for retry', { hash });

      const updated = getPayloadWithSignatures(hash);

      return res.status(200).json({
        success: true,
        message: 'Payload marked for retry',
        payload: updated ? toJsonPayload(updated) : null,
      });
    } catch (err) {
      logger.error('Failed to retry payload', {
        hash: req.params.hash,
        error: err instanceof Error ? err.message : String(err),
      });

      return res.status(500).json({
        error: 'Internal error',
        message: err instanceof Error ? err.message : String(err),
      });
    }
  });

  return router;
}
