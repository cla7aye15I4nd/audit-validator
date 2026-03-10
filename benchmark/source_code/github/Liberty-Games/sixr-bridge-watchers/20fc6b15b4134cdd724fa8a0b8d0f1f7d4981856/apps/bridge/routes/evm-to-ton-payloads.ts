/**
 * @file evm-to-ton-payloads.ts
 * @notice EVM -> TON payload submission handler
 *
 * This module handles EVM burn to TON mint payload submissions,
 * including burn proof validation and signature verification.
 */

import { Request, Response } from 'express';
import { z } from 'zod';
import { ethers } from 'ethers';
import { BridgeConfig } from '../config';
import { getLogger } from '../logger';
import {
  buildTonMintPayload,
  computeTonMintDigest,
  hashTonMintPayload,
  normalizeAddress,
  normalizeTonAddress,
  encodeTonAddressForPayload,
} from '../../shared/payload';
import { recoverSigner } from '../../shared/signature';
import { TonMintPayloadSubmissionInput } from '../../shared/types';
import {
  upsertPayload,
  getPayloadWithSignatures,
  checkAndUpdateReadyStatus,
} from '../store/payloads';
import { upsertSignature, getSignatureCount } from '../store/signatures';
import { transaction } from '../store/database';
import {
  hashMintPayload as hashTonMintPayloadTLB,
  TonMintPayload as TonMintPayloadTLB,
} from '../../shared/ton-multisig/payload';
import { verifySignature } from '../../shared/ton-multisig/signatures';
import { normalizeTonPublicKey } from '../../shared/ton';
import { toJsonPayload } from '../../shared/serializer';

/**
 * Zod schema for EVM -> TON payload submission
 */
export const TonMintPayloadSubmissionSchema = z.object({
  direction: z.literal('EVM_TO_TON'),
  originChainId: z.number().int().nonnegative(),
  token: z.string().regex(/^0x[a-fA-F0-9]{40}$/),
  tonRecipient: z.string().min(1),
  tonRecipientRaw: z.string().min(1).optional(),
  tonRecipientHash: z.string().regex(/^0x[a-fA-F0-9]{64}$/),
  amountRaw9: z.string().regex(/^\d+$/),
  amountRaw18: z.string().regex(/^\d+$/),
  nonce: z.string().regex(/^\d+$/),
  watcher: z.string().regex(/^0x[a-fA-F0-9]{40}$/),
  signature: z.string().regex(/^0x[a-fA-F0-9]{130}$/),
  // TON Multisig fields
  tonWatcherIndex: z.number().int().min(0).max(2),
  tonPublicKey: z.string().regex(/^(0x)?[0-9a-fA-F]{64}$/),
  tonSignature: z.string().regex(/^(0x)?[0-9a-fA-F]{128}$/),
  burnTxHash: z.string().regex(/^0x[a-fA-F0-9]{64}$/),
  burnBlockNumber: z.number().int().nonnegative(),
  burnRedeemLogIndex: z.number().int().nonnegative(),
  burnTransferLogIndex: z.number().int().nonnegative().optional(),
});

/**
 * Validates EVM burn proof by fetching the transaction receipt and verifying both
 * RedeemToTon and Transfer logs
 *
 * @param provider - Ethers provider
 * @param burnTxHash - Burn transaction hash
 * @param burnRedeemLogIndex - Expected RedeemToTon log index
 * @param burnTransferLogIndex - Optional Transfer log index (if known)
 * @param tokenAddress - Expected token address
 * @param expectedAmount - Expected amount (18 decimals)
 * @param expectedTonRecipient - Expected TON recipient address
 * @param minConfirmations - Minimum required confirmations
 * @param logger - Logger instance
 * @returns Validation result with confirmations, from address, and transfer log index
 */
async function validateBurnProof(
  provider: ethers.providers.Provider,
  burnTxHash: string,
  burnRedeemLogIndex: number,
  burnTransferLogIndex: number | undefined,
  tokenAddress: string,
  expectedAmount: string,
  expectedTonRecipient: string,
  minConfirmations: number,
  logger: ReturnType<typeof getLogger>
): Promise<{
  valid: boolean;
  error?: string;
  confirmations?: number;
  from?: string;
  transferLogIndex?: number;
}> {
  try {
    // Fetch transaction receipt
    const receipt = await provider.getTransactionReceipt(burnTxHash);

    if (!receipt) {
      return { valid: false, error: 'Transaction receipt not found' };
    }

    if (receipt.status !== 1) {
      return { valid: false, error: 'Transaction failed (status != 1)' };
    }

    // Get current block to calculate confirmations
    const currentBlock = await provider.getBlockNumber();
    const confirmations = currentBlock - receipt.blockNumber;

    // Check minimum confirmations
    if (confirmations < minConfirmations) {
      return {
        valid: false,
        error: `Insufficient confirmations (${confirmations}/${minConfirmations})`,
        confirmations,
      };
    }

    // Step 1: Find and validate RedeemToTon log at burnRedeemLogIndex
    const REDEEM_TOPIC0 = ethers.utils.id('RedeemToTon(address,string,uint256,uint256)');

    const redeemLog = receipt.logs.find(
      (log) =>
        log.address.toLowerCase() === tokenAddress.toLowerCase() &&
        log.topics[0] === REDEEM_TOPIC0 &&
        log.logIndex === burnRedeemLogIndex
    );

    if (!redeemLog) {
      return {
        valid: false,
        error: `No RedeemToTon log found at index ${burnRedeemLogIndex} for token ${tokenAddress}`,
        confirmations,
      };
    }

    // Decode RedeemToTon event
    const redeemIface = new ethers.utils.Interface([
      'event RedeemToTon(address indexed from, string tonRecipient, uint256 amount, uint256 fee)',
    ]);
    const redeemDecoded = redeemIface.parseLog(redeemLog);

    const redeemFrom = redeemDecoded.args.from as string;
    const redeemTonRecipient = redeemDecoded.args.tonRecipient as string;
    const redeemAmountLD = (redeemDecoded.args.amount as ethers.BigNumber).toString();

    // Verify RedeemToTon parameters - normalize both addresses before comparison
    const redeemTonRecipientNormalized = normalizeTonAddress(redeemTonRecipient);
    const expectedTonRecipientNormalized = normalizeTonAddress(expectedTonRecipient);

    if (redeemTonRecipientNormalized !== expectedTonRecipientNormalized) {
      return {
        valid: false,
        error: `TON recipient mismatch in RedeemToTon (expected ${expectedTonRecipient} [normalized: ${expectedTonRecipientNormalized}], got ${redeemTonRecipient} [normalized: ${redeemTonRecipientNormalized}])`,
        confirmations,
      };
    }

    if (redeemAmountLD !== expectedAmount) {
      return {
        valid: false,
        error: `Amount mismatch in RedeemToTon (expected ${expectedAmount}, got ${redeemAmountLD})`,
        confirmations,
      };
    }

    // Step 2: Find corresponding Transfer log (to = 0x0)
    const TRANSFER_TOPIC0 = ethers.utils.id('Transfer(address,address,uint256)');
    const ZERO_ADDRESS = ethers.constants.AddressZero;

    let transferLog = null;
    let foundTransferLogIndex = -1;

    // If burnTransferLogIndex is provided, check that first
    if (burnTransferLogIndex !== undefined) {
      const candidateLog = receipt.logs.find(
        (log) =>
          log.address.toLowerCase() === tokenAddress.toLowerCase() &&
          log.topics[0] === TRANSFER_TOPIC0 &&
          log.logIndex === burnTransferLogIndex
      );

      if (candidateLog) {
        transferLog = candidateLog;
        foundTransferLogIndex = burnTransferLogIndex;
      }
    }

    // If not found via explicit index, iterate through all Transfer logs
    if (!transferLog) {
      const transferLogs = receipt.logs.filter(
        (log) =>
          log.address.toLowerCase() === tokenAddress.toLowerCase() &&
          log.topics[0] === TRANSFER_TOPIC0
      );

      for (const log of transferLogs) {
        const transferIface = new ethers.utils.Interface([
          'event Transfer(address indexed from, address indexed to, uint256 value)',
        ]);
        const decoded = transferIface.parseLog(log);

        const from = decoded.args.from as string;
        const to = decoded.args.to as string;
        const value = (decoded.args.value as ethers.BigNumber).toString();

        // Check if this is the burn Transfer matching our RedeemToTon
        if (
          to.toLowerCase() === ZERO_ADDRESS.toLowerCase() &&
          from.toLowerCase() === redeemFrom.toLowerCase() &&
          value === expectedAmount
        ) {
          transferLog = log;
          foundTransferLogIndex = log.logIndex;
          break;
        }
      }
    }

    if (!transferLog) {
      return {
        valid: false,
        error: `No matching Transfer burn log found (to=0x0, from=${redeemFrom}, amount=${expectedAmount})`,
        confirmations,
      };
    }

    // Decode and verify Transfer log
    const transferIface = new ethers.utils.Interface([
      'event Transfer(address indexed from, address indexed to, uint256 value)',
    ]);
    const transferDecoded = transferIface.parseLog(transferLog);

    const transferFrom = transferDecoded.args.from as string;
    const transferTo = transferDecoded.args.to as string;
    const transferValue = (transferDecoded.args.value as ethers.BigNumber).toString();

    // Verify burn: to must be zero address
    if (transferTo.toLowerCase() !== ZERO_ADDRESS.toLowerCase()) {
      return {
        valid: false,
        error: `Transfer is not a burn (to=${transferTo}, expected ${ZERO_ADDRESS})`,
        confirmations,
      };
    }

    // Verify from matches between RedeemToTon and Transfer
    if (transferFrom.toLowerCase() !== redeemFrom.toLowerCase()) {
      return {
        valid: false,
        error: `Transfer from (${transferFrom}) does not match RedeemToTon from (${redeemFrom})`,
        confirmations,
      };
    }

    // Verify amount matches
    if (transferValue !== expectedAmount) {
      return {
        valid: false,
        error: `Transfer amount mismatch (expected ${expectedAmount}, got ${transferValue})`,
        confirmations,
      };
    }

    logger.info('Burn proof validated successfully', {
      burnTxHash,
      burnRedeemLogIndex,
      transferLogIndex: foundTransferLogIndex,
      from: transferFrom,
      tonRecipient: redeemTonRecipient,
      amount: transferValue,
      confirmations,
    });

    return {
      valid: true,
      confirmations,
      from: transferFrom,
      transferLogIndex: foundTransferLogIndex,
    };
  } catch (err) {
    logger.error('Burn proof validation failed', {
      burnTxHash,
      error: err instanceof Error ? err.message : String(err),
    });
    return {
      valid: false,
      error: `Burn proof validation error: ${err instanceof Error ? err.message : String(err)}`,
    };
  }
}

/**
 * Gets EVM chain configuration based on origin chain ID
 *
 * @param originChainId - Origin chain ID
 * @param config - Bridge configuration
 * @returns Chain configuration (RPC URL, multisig address, min confirmations)
 */
function getChainConfig(originChainId: number, config: BridgeConfig): {
  rpcUrl: string;
  multisigAddress: string;
  minConfirmations: number;
  tokenAddress: string;
} {
  // Base chain
  if (config.base && originChainId === config.base.chainId) {
    return {
      rpcUrl: config.base.rpcUrl,
      multisigAddress: config.base.multisigAddress,
      minConfirmations: config.base.minConfirmations,
      tokenAddress: config.base.oftAddress,
    };
  }

  // BSC chain
  if (config.bsc && originChainId === config.bsc.chainId) {
    return {
      rpcUrl: config.bsc.rpcUrl,
      multisigAddress: config.bsc.multisigAddress,
      minConfirmations: config.bsc.minConfirmations,
      tokenAddress: config.bsc.oftAddress,
    };
  }

  throw new Error(`Unsupported origin chain ID: ${originChainId}`);
}

/**
 * Handles EVM -> TON payload submission
 *
 * @param req - Express request
 * @param res - Express response
 * @param config - Bridge configuration
 * @returns Express response
 */
export async function handleEvmToTonSubmission(
  req: Request,
  res: Response,
  config: BridgeConfig
): Promise<Response> {
  const logger = getLogger();

  try {
    // Validate request body
    const input = TonMintPayloadSubmissionSchema.parse(req.body) as TonMintPayloadSubmissionInput;

    logger.info('Received EVM->TON payload submission', {
      watcher: input.watcher,
      burnTxHash: input.burnTxHash,
      originChainId: input.originChainId,
    });

    // Get chain configuration based on origin chain ID
    let chainConfig;
    try {
      chainConfig = getChainConfig(input.originChainId, config);
    } catch (err) {
      logger.warn('Unsupported chain', {
        originChainId: input.originChainId,
        error: err instanceof Error ? err.message : String(err),
      });

      return res.status(400).json({
        error: 'Unsupported chain',
        message: err instanceof Error ? err.message : String(err),
      });
    }

    // Normalize TON recipient and verify hash matches
    const normalizedTonRecipient = normalizeTonAddress(input.tonRecipient);
    const computedTonRecipientHash = encodeTonAddressForPayload(normalizedTonRecipient);

    // Log when raw and canonical addresses differ (for audit purposes)
    if (input.tonRecipientRaw && input.tonRecipientRaw !== normalizedTonRecipient) {
      logger.info('TON recipient normalized', {
        raw: input.tonRecipientRaw,
        canonical: normalizedTonRecipient,
        burnTxHash: input.burnTxHash,
      });
    }

    if (computedTonRecipientHash.toLowerCase() !== input.tonRecipientHash.toLowerCase()) {
      logger.warn('TON recipient hash mismatch', {
        provided: input.tonRecipientHash,
        computed: computedTonRecipientHash,
        tonRecipient: input.tonRecipient,
      });

      return res.status(400).json({
        error: 'TON recipient hash mismatch',
        message: `Provided hash ${input.tonRecipientHash} does not match computed hash ${computedTonRecipientHash}`,
      });
    }

    // Build canonical payload
    const payload = buildTonMintPayload(
      input.originChainId,
      input.token,
      normalizedTonRecipient,
      input.amountRaw9,
      input.burnBlockNumber,
      input.burnRedeemLogIndex,
      input.burnTxHash
    );

    // Compute payload hash using aggregator domain (chain-specific)
    const domain = {
      name: 'BridgeMultisig',
      version: '1',
      chainId: input.originChainId,
      verifyingContract: chainConfig.multisigAddress,
    };

    const structHash = hashTonMintPayload(payload);
    const digest = computeTonMintDigest(payload, domain);

    logger.info('Computed TON mint payload digest', {
      hash: digest,
      structHash,
      originChainId: input.originChainId,
      token: input.token,
      tonRecipient: normalizedTonRecipient,
      tonRecipientHash: payload.tonRecipientHash,
      amount: payload.amount,
      nonce: payload.nonce,
      burnTxHash: payload.burnTxHash,
    });

    // Validate signature
    let signerAddress: string;
    try {
      signerAddress = recoverSigner(digest, input.signature);
    } catch (err) {
      logger.warn('Failed to recover signer', {
        hash: digest,
        watcher: input.watcher,
        error: err instanceof Error ? err.message : String(err),
      });

      return res.status(400).json({
        error: 'Invalid signature',
        message: err instanceof Error ? err.message : String(err),
      });
    }

    // Verify signer is a known watcher
    const normalizedWatchers = config.watchers.addresses.map((w) => normalizeAddress(w, 'watcher'));
    if (!normalizedWatchers.includes(signerAddress)) {
      logger.warn('Unknown watcher', {
        hash: digest,
        signer: signerAddress,
        watchers: normalizedWatchers,
      });

      return res.status(400).json({
        error: 'Unknown watcher',
        message: `Signer ${signerAddress} is not in the configured watcher set`,
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

    // Validate burn proof via JSON-RPC (use chain-specific RPC URL)
    const provider = new ethers.providers.JsonRpcProvider(chainConfig.rpcUrl);

    const burnProofResult = await validateBurnProof(
      provider,
      input.burnTxHash,
      input.burnRedeemLogIndex,
      input.burnTransferLogIndex,
      input.token,
      input.amountRaw18,
      input.tonRecipient,
      chainConfig.minConfirmations,
      logger
    );

    if (!burnProofResult.valid) {
      logger.warn('Burn proof validation failed', {
        hash: digest,
        burnTxHash: input.burnTxHash,
        error: burnProofResult.error,
      });

      return res.status(400).json({
        error: 'Invalid burn proof',
        message: burnProofResult.error,
      });
    }

    logger.info('Burn proof validated', {
      hash: digest,
      burnTxHash: input.burnTxHash,
      from: burnProofResult.from,
      transferLogIndex: burnProofResult.transferLogIndex,
      confirmations: burnProofResult.confirmations,
    });

    // Validate TON multisig signature
    if (!config.tonMultisig.enabled) {
      logger.error('TON multisig not enabled', { hash: digest });
      return res.status(500).json({
        error: 'Configuration error',
        message: 'TON multisig is not enabled',
      });
    }

    // Check that tonWatcherIndex matches configured watchers
    if (input.tonWatcherIndex < 0 || input.tonWatcherIndex >= config.tonMultisig.watchers.length) {
      logger.warn('Invalid TON watcher index', {
        hash: digest,
        tonWatcherIndex: input.tonWatcherIndex,
        maxIndex: config.tonMultisig.watchers.length - 1,
      });

      return res.status(400).json({
        error: 'Invalid TON watcher index',
        message: `TON watcher index ${input.tonWatcherIndex} is out of range (0-${config.tonMultisig.watchers.length - 1})`,
      });
    }

    // Get expected public key for this watcher index
    const expectedTonPublicKey = config.tonMultisig.watchers[input.tonWatcherIndex];

    // Normalize keys before comparison (strip 0x prefix if present)
    let normalizedProvidedKey: string;
    let normalizedExpectedKey: string;
    try {
      normalizedProvidedKey = normalizeTonPublicKey(input.tonPublicKey);
      normalizedExpectedKey = normalizeTonPublicKey(expectedTonPublicKey);
    } catch (err) {
      logger.warn('Invalid TON public key format', {
        hash: digest,
        tonWatcherIndex: input.tonWatcherIndex,
        providedKey: input.tonPublicKey,
        expectedKey: expectedTonPublicKey,
        error: err instanceof Error ? err.message : String(err),
      });

      return res.status(400).json({
        error: 'Invalid TON public key format',
        message: err instanceof Error ? err.message : String(err),
      });
    }

    // Verify TON public key matches expected watcher
    if (normalizedProvidedKey !== normalizedExpectedKey) {
      logger.warn('TON public key mismatch', {
        hash: digest,
        tonWatcherIndex: input.tonWatcherIndex,
        providedKey: input.tonPublicKey,
        expectedKey: expectedTonPublicKey,
      });

      return res.status(400).json({
        error: 'TON public key mismatch',
        message: `TON public key does not match watcher index ${input.tonWatcherIndex}`,
      });
    }

    // Build TON mint payload for signature verification
    const tonPayload: TonMintPayloadTLB = {
      originChainId: input.originChainId,
      token: input.token,
      tonRecipient: normalizedTonRecipient,
      amount: BigInt(input.amountRaw9),
      nonce: BigInt(payload.nonce),
    };

    // Hash the TON payload using TL-B schema
    const tonPayloadHash = hashTonMintPayloadTLB(tonPayload);

    // Verify TON signature - normalize keys to strip 0x prefix if present
    const normalizedTonSignature = input.tonSignature.startsWith('0x')
      ? input.tonSignature.slice(2)
      : input.tonSignature;
    const tonPublicKeyBuffer = Buffer.from(normalizedProvidedKey, 'hex');
    const tonSignatureBuffer = Buffer.from(normalizedTonSignature, 'hex');

    // Note: verifySignature currently returns true (placeholder)
    // In production, should use proper Ed25519 verification library
    const tonSignatureValid = verifySignature(
      tonPayloadHash,
      tonSignatureBuffer,
      tonPublicKeyBuffer
    );

    if (!tonSignatureValid) {
      logger.warn('Invalid TON signature', {
        hash: digest,
        tonPublicKey: normalizedProvidedKey,
        tonWatcherIndex: input.tonWatcherIndex,
      });

      return res.status(400).json({
        error: 'Invalid TON signature',
        message: 'TON signature verification failed',
      });
    }

    logger.info('TON signature validated', {
      hash: digest,
      tonPublicKey: normalizedProvidedKey,
      tonWatcherIndex: input.tonWatcherIndex,
    });

    // Store payload and signature in transaction
    transaction(() => {
      // Upsert payload
      upsertPayload({
        hash: digest,
        origin_chain_id: input.originChainId,
        token: payload.token,
        recipient: '', // Not used for EVM -> TON
        amount: payload.amount,
        amount_raw9: input.amountRaw9,
        nonce: BigInt(payload.nonce),
        ton_tx_id: '', // Not used for EVM -> TON
        status: 'pending',
        submitted_tx: null,
        error: null,
        direction: 'EVM_TO_TON',
        burn_tx_hash: null, // This is for TON burns
        burn_lt: null,
        burn_status: null,
        burn_timestamp: null,
        // EVM burn fields
        burn_chain_id: input.originChainId,
        burn_block_number: input.burnBlockNumber,
        burn_redeem_log_index: input.burnRedeemLogIndex,
        burn_transfer_log_index: burnProofResult.transferLogIndex ?? null,
        burn_from_address: burnProofResult.from ?? null,
        burn_confirmations: burnProofResult.confirmations || 0,
        // TON recipient fields
        ton_recipient: normalizedTonRecipient,
        ton_recipient_raw: input.tonRecipientRaw ?? null,
        ton_recipient_hash: payload.tonRecipientHash,
        // TON mint tracking
        ton_mint_tx_hash: null,
        ton_mint_lt: null,
        ton_mint_status: null,
        ton_mint_error: null,
        ton_mint_timestamp: null,
        ton_mint_attempts: 0n,
        ton_mint_next_retry: null,
        fee_amount: null,
      });

      // Upsert signature with TON signature data (store normalized keys without 0x prefix)
      upsertSignature(digest, signerAddress, input.signature, normalizedProvidedKey, normalizedTonSignature);

      logger.info('Stored EVM->TON payload and signatures', {
        hash: digest,
        watcher: signerAddress,
        tonPublicKey: normalizedProvidedKey,
        tonWatcherIndex: input.tonWatcherIndex,
        burnTxHash: input.burnTxHash,
      });
    });

    // Check if quorum is met and update status
    const isReady = checkAndUpdateReadyStatus(digest, config.watchers.threshold);

    if (isReady) {
      logger.info('EVM->TON payload reached quorum', {
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

    logger.info('EVM->TON payload submission successful', {
      hash: digest,
      status: result.status,
      signatureCount: result.signatures.length,
    });

    return res.status(200).json({
      success: true,
      payload: toJsonPayload(result),
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      logger.warn('Invalid EVM->TON payload submission input', {
        errors: err.errors,
      });

      return res.status(400).json({
        error: 'Validation error',
        details: err.errors,
      });
    }

    logger.error('EVM->TON payload submission failed', {
      error: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined,
    });

    return res.status(500).json({
      error: 'Internal error',
      message: err instanceof Error ? err.message : String(err),
    });
  }
}
