/**
 * @file submitter.ts
 * @notice Submission worker for the Bridge Aggregator
 *
 * This worker polls for ready payloads, submits them to the BridgeMultisig contract,
 * and tracks transaction status with retry logic.
 */

import { ethers } from 'ethers';
import { BridgeConfig } from '../config';
import { getLogger } from '../logger';
import {
  getPayloadsByStatus,
  markPayloadSubmitted,
  markPayloadFinalized,
  markPayloadFailed,
  getPayloadByHash,
  getRetryablePayloads,
} from '../store/payloads';
import { getWatcherSignatures } from '../store/signatures';
import { normalizeAddress, toChainPayload } from '../../shared/payload';

/**
 * Submission worker class
 */
export class SubmissionWorker {
  private config: BridgeConfig;
  private logger: ReturnType<typeof getLogger>;
  private baseProvider: ethers.providers.Provider | null = null;
  private bscProvider: ethers.providers.Provider | null = null;
  private baseWallet: ethers.Wallet | null = null;
  private bscWallet: ethers.Wallet | null = null;
  private baseMultisig: ethers.Contract | null = null;
  private bscMultisig: ethers.Contract | null = null;
  private running: boolean = false;
  private pollTimer: NodeJS.Timeout | null = null;

  constructor(config: BridgeConfig) {
    this.config = config;
    this.logger = getLogger();

    const multisigAbi = [
      'function executeMint((uint256 originChainId, address token, address recipient, uint256 amount, uint64 nonce) payload, bytes[] signatures) external',
      'event MintExecuted(bytes32 indexed payloadHash, uint256 originChainId, address indexed token, address indexed recipient, uint256 amount, uint64 nonce)',
    ];

    const logInfo: Record<string, unknown> = {};

    // Initialize Base chain (if configured)
    if (config.base) {
      this.baseProvider = new ethers.providers.JsonRpcProvider(config.base.rpcUrl);
      this.baseWallet = new ethers.Wallet(config.base.privateKey, this.baseProvider);
      this.baseMultisig = new ethers.Contract(config.base.multisigAddress, multisigAbi, this.baseWallet);
      logInfo.baseMultisig = config.base.multisigAddress;
      logInfo.baseWallet = this.baseWallet.address;
      logInfo.baseChainId = config.base.chainId;
    }

    // Initialize BSC chain (if configured)
    if (config.bsc) {
      this.bscProvider = new ethers.providers.JsonRpcProvider(config.bsc.rpcUrl);
      this.bscWallet = new ethers.Wallet(config.bsc.privateKey, this.bscProvider);
      this.bscMultisig = new ethers.Contract(config.bsc.multisigAddress, multisigAbi, this.bscWallet);
      logInfo.bscMultisig = config.bsc.multisigAddress;
      logInfo.bscWallet = this.bscWallet.address;
      logInfo.bscChainId = config.bsc.chainId;
    }

    this.logger.info('Submission worker initialized', logInfo);
  }

  /**
   * Starts the submission worker
   */
  public start(): void {
    if (this.running) {
      this.logger.warn('Submission worker already running');
      return;
    }

    if (!this.config.worker.enabled) {
      this.logger.info('Submission worker disabled by configuration');
      return;
    }

    this.running = true;
    this.logger.info('Starting submission worker', {
      pollInterval: this.config.worker.pollIntervalMs,
      maxRetries: this.config.worker.maxRetries,
      retryBackoff: this.config.worker.retryBackoffMs,
    });

    // Start polling
    this.poll();
  }

  /**
   * Stops the submission worker
   */
  public stop(): void {
    if (!this.running) {
      return;
    }

    this.running = false;

    if (this.pollTimer) {
      clearTimeout(this.pollTimer);
      this.pollTimer = null;
    }

    this.logger.info('Submission worker stopped');
  }

  /**
   * Poll loop
   */
  private poll(): void {
    if (!this.running) {
      return;
    }

    this.processReadyPayloads()
      .then(() => this.processRetryablePayloads())
      .catch((err) => {
        this.logger.error('Poll cycle error', {
          error: err instanceof Error ? err.message : String(err),
          stack: err instanceof Error ? err.stack : undefined,
        });
      })
      .finally(() => {
        if (this.running) {
          this.pollTimer = setTimeout(() => this.poll(), this.config.worker.pollIntervalMs);
        }
      });
  }

  /**
   * Processes payloads ready for EVM submission
   * Only handles TON_TO_EVM direction - EVM_TO_TON is handled by TON mint worker
   *
   * For TON→EVM flow:
   * - If TON_BURNER_ENABLED=true: processes 'burn_confirmed' payloads
   * - If TON_BURNER_ENABLED=false: processes 'ready' payloads (user already burned on-chain)
   */
  private async processReadyPayloads(): Promise<void> {
    // If TON burner is disabled, process 'ready' status directly
    // (user already burned tokens by sending to vault with memo)
    // If TON burner is enabled, wait for 'burn_confirmed' status
    const targetStatus = this.config.tonBurner.enabled ? 'burn_confirmed' : 'ready';
    const payloads = getPayloadsByStatus(targetStatus, 10); // Process up to 10 at a time

    if (payloads.length === 0) {
      return;
    }

    this.logger.info(`Processing ${targetStatus} payloads for EVM submission`, { count: payloads.length });

    for (const payload of payloads) {
      if (!this.running) {
        break;
      }

      // GUARD: Only process TON_TO_EVM payloads
      // EVM_TO_TON payloads should never reach burn_confirmed status,
      // but we guard against misconfiguration
      if (payload.direction !== 'TON_TO_EVM') {
        this.logger.warn('Submission worker encountered non-TON_TO_EVM payload, skipping', {
          hash: payload.hash,
          direction: payload.direction,
          status: payload.status,
        });
        continue;
      }

      try {
        await this.submitPayload(payload.hash);
      } catch (err) {
        this.logger.error('Failed to submit payload', {
          hash: payload.hash,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  /**
   * Processes retryable failed payloads
   */
  private async processRetryablePayloads(): Promise<void> {
    const payloads = getRetryablePayloads(this.config.worker.retryBackoffMs, 5); // Retry up to 5 at a time

    if (payloads.length === 0) {
      return;
    }

    this.logger.info('Processing retryable payloads', { count: payloads.length });

    for (const payload of payloads) {
      if (!this.running) {
        break;
      }

      // GUARD: Only process TON_TO_EVM payloads
      // EVM_TO_TON payloads are handled by TON mint worker
      if (payload.direction !== 'TON_TO_EVM') {
        this.logger.warn('Submission worker skipping non-TON_TO_EVM retryable payload', {
          hash: payload.hash,
          direction: payload.direction,
          status: payload.status,
        });
        continue;
      }

      try {
        await this.submitPayload(payload.hash);
      } catch (err) {
        this.logger.error('Failed to retry payload', {
          hash: payload.hash,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  /**
   * Submits a payload to the multisig contract
   *
   * @param hash - Payload hash
   */
  private async submitPayload(hash: string): Promise<void> {
    this.logger.info('Submitting payload', { hash });

    // Get payload
    const payloadRow = getPayloadByHash(hash);
    if (!payloadRow) {
      this.logger.error('Payload not found', { hash });
      return;
    }

    // Get signatures
    const signatures = getWatcherSignatures(hash);

    if (signatures.length < this.config.watchers.threshold) {
      this.logger.warn('Insufficient signatures', {
        hash,
        count: signatures.length,
        threshold: this.config.watchers.threshold,
      });
      return;
    }

    // Build payload struct for contract
    const payload = toChainPayload({
      originChainId: payloadRow.origin_chain_id.toString(),
      token: payloadRow.token,
      recipient: payloadRow.recipient,
      amount: payloadRow.amount,
      nonce: payloadRow.nonce.toString(),
    });

    // Extract signature strings
    const signatureArray = signatures.map((sig) => sig.signature);

    // Detect target chain based on token address
    const normalizedToken = normalizeAddress(payloadRow.token, 'token');
    let multisig: ethers.Contract;
    let chainName: string;

    if (this.config.base && normalizedToken === this.config.base.oftAddress) {
      if (!this.baseMultisig) throw new Error('Base chain not initialized');
      multisig = this.baseMultisig;
      chainName = 'Base';
    } else if (this.config.bsc && normalizedToken === this.config.bsc.oftAddress) {
      if (!this.bscMultisig) throw new Error('BSC chain not initialized');
      multisig = this.bscMultisig;
      chainName = 'BSC';
    } else {
      const expectedTokens: string[] = [];
      if (this.config.base) expectedTokens.push(`${this.config.base.oftAddress} (Base)`);
      if (this.config.bsc) expectedTokens.push(`${this.config.bsc.oftAddress} (BSC)`);
      throw new Error(
        `Unknown token ${normalizedToken}. Expected: ${expectedTokens.join(' or ')}`
      );
    }

    this.logger.info('Executing mint transaction', {
      hash,
      payload,
      signatureCount: signatureArray.length,
      chain: chainName,
    });

    try {
      // Submit transaction
      const tx = await multisig.executeMint(payload, signatureArray, {
        gasLimit: 500000, // Explicit gas limit
      });

      this.logger.info('Transaction submitted', {
        hash,
        txHash: tx.hash,
      });

      // Mark as submitted
      markPayloadSubmitted(hash, tx.hash);

      // Wait for confirmation
      const receipt = await tx.wait();

      if (receipt.status === 1) {
        this.logger.info('Transaction confirmed', {
          hash,
          txHash: tx.hash,
          blockNumber: receipt.blockNumber,
          gasUsed: receipt.gasUsed.toString(),
        });

        // Mark as finalized
        markPayloadFinalized(hash);
      } else {
        this.logger.error('Transaction reverted', {
          hash,
          txHash: tx.hash,
          blockNumber: receipt.blockNumber,
        });

        markPayloadFailed(hash, 'Transaction reverted on-chain');
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);

      this.logger.error('Transaction failed', {
        hash,
        error: errorMessage,
        stack: err instanceof Error ? err.stack : undefined,
      });

      // Parse error for specific failure reasons
      let parsedError = errorMessage;

      if (errorMessage.includes('already executed')) {
        parsedError = 'Payload already executed';
      } else if (errorMessage.includes('token not allowed')) {
        parsedError = 'Token not allowed in BridgeMultisig';
      } else if (errorMessage.includes('insufficient signatures')) {
        parsedError = 'Insufficient or invalid signatures';
      } else if (errorMessage.includes('nonce')) {
        parsedError = 'Invalid nonce';
      }

      markPayloadFailed(hash, parsedError);
    }
  }

  /**
   * Checks if worker is running
   *
   * @returns True if running
   */
  public isRunning(): boolean {
    return this.running;
  }

  /**
   * Gets worker status
   *
   * @returns Worker status
   */
  public getStatus(): {
    running: boolean;
    base: {
      wallet: string;
      multisig: string;
      chainId: number;
    } | null;
    bsc: {
      wallet: string;
      multisig: string;
      chainId: number;
    } | null;
  } {
    return {
      running: this.running,
      base: this.config.base && this.baseWallet ? {
        wallet: this.baseWallet.address,
        multisig: this.config.base.multisigAddress,
        chainId: this.config.base.chainId,
      } : null,
      bsc: this.config.bsc && this.bscWallet ? {
        wallet: this.bscWallet.address,
        multisig: this.config.bsc.multisigAddress,
        chainId: this.config.bsc.chainId,
      } : null,
    };
  }
}
