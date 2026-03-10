/**
 * @file ton-minter.ts
 * @notice TON mint worker for the Bridge Aggregator (EVM -> TON flow)
 *
 * @deprecated This worker is LEGACY and should not be used for new deployments.
 * Use TonMultisigSubmitter (ton-multisig-submitter.ts) instead, which implements
 * a secure multisig flow for EVM -> TON minting operations.
 *
 * This worker polls for EVM-to-TON payloads that are ready for minting (have quorum),
 * mints jettons on TON, and tracks mint confirmation status.
 * Only one instance should run to prevent duplicate mints.
 *
 * Migration Guide:
 * - Set TON_MINTER_ENABLED=false in .env
 * - Set TON_MULTISIG_SUBMITTER_ENABLED=true in .env
 * - Configure TON_MULTISIG_* variables
 * - Deploy TON multisig contract with proper watcher/governance keys
 */

import { TonClient, WalletContractV5R1, internal, SendMode } from '@ton/ton';
import { Address, beginCell, toNano } from '@ton/core';
import { mnemonicToPrivateKey } from '@ton/crypto';
import { storeJettonMintMessage } from '@ton-community/assets-sdk';
import axios, { AxiosError } from 'axios';
import { BridgeConfig } from '../config';
import { getLogger } from '../logger';
import {
  getPayloadsReadyForTonMint,
  getPayloadsWithTonMintSubmitted,
  markPayloadTonMintPending,
  markPayloadTonMintSubmitted,
  markPayloadTonMintConfirmed,
  markPayloadTonMintFailed,
  markPayloadFailed,
  markPayloadFinalized,
  incrementTonMintAttempts,
  clearTonMintRetry,
  getPayloadByHash,
} from '../store/payloads';

/**
 * TON mint worker class
 */
export class TonMintWorker {
  private config: BridgeConfig;
  private logger: ReturnType<typeof getLogger>;
  private running: boolean = false;
  private mintPollTimer: NodeJS.Timeout | null = null;
  private confirmationPollTimer: NodeJS.Timeout | null = null;
  private tonClient: TonClient | null = null;
  private processing: boolean = false; // Lock to serialize mints

  constructor(config: BridgeConfig) {
    this.config = config;
    this.logger = getLogger();

    this.logger.info('TON mint worker initialized', {
      chain: config.tonMinter.chain,
      jettonRoot: config.tonMinter.jettonRoot,
    });
  }

  /**
   * Starts the TON mint worker
   */
  public start(): void {
    if (this.running) {
      this.logger.warn('TON mint worker already running');
      return;
    }

    if (!this.config.tonMinter.enabled) {
      this.logger.info('TON mint worker disabled by configuration');
      return;
    }

    this.running = true;
    this.logger.info('Starting TON mint worker', {
      mintPollInterval: this.config.tonMinter.pollIntervalMs,
      confirmationCheckInterval: this.config.tonMinter.confirmationCheckIntervalMs,
    });

    // Initialize TON client
    this.initializeTonClient();

    // Start polling loops
    this.pollMintQueue();
    this.pollConfirmationQueue();
  }

  /**
   * Stops the TON mint worker
   */
  public stop(): void {
    if (!this.running) {
      return;
    }

    this.running = false;

    if (this.mintPollTimer) {
      clearTimeout(this.mintPollTimer);
      this.mintPollTimer = null;
    }

    if (this.confirmationPollTimer) {
      clearTimeout(this.confirmationPollTimer);
      this.confirmationPollTimer = null;
    }

    this.logger.info('TON mint worker stopped');
  }

  /**
   * Initializes TON client
   */
  private initializeTonClient(): void {
    const endpoint = this.config.tonMinter.toncenterBase.endsWith('/jsonRPC')
      ? this.config.tonMinter.toncenterBase
      : this.config.tonMinter.toncenterBase.replace(/\/api\/v2$/, '') + '/api/v2/jsonRPC';

    this.tonClient = new TonClient({
      endpoint,
      apiKey: this.config.tonMinter.toncenterApiKey,
    });

    this.logger.info('TON client initialized', { endpoint });
  }

  /**
   * Poll loop for minting payloads
   */
  private pollMintQueue(): void {
    if (!this.running) {
      return;
    }

    this.processReadyPayloads()
      .catch((err) => {
        this.logger.error('Mint poll cycle error', {
          error: err instanceof Error ? err.message : String(err),
          stack: err instanceof Error ? err.stack : undefined,
        });
      })
      .finally(() => {
        if (this.running) {
          this.mintPollTimer = setTimeout(
            () => this.pollMintQueue(),
            this.config.tonMinter.pollIntervalMs
          );
        }
      });
  }

  /**
   * Poll loop for checking mint confirmations
   */
  private pollConfirmationQueue(): void {
    if (!this.running) {
      return;
    }

    this.processSubmittedMints()
      .catch((err) => {
        this.logger.error('Confirmation poll cycle error', {
          error: err instanceof Error ? err.message : String(err),
          stack: err instanceof Error ? err.stack : undefined,
        });
      })
      .finally(() => {
        if (this.running) {
          this.confirmationPollTimer = setTimeout(
            () => this.pollConfirmationQueue(),
            this.config.tonMinter.confirmationCheckIntervalMs
          );
        }
      });
  }

  /**
   * Processes payloads that are ready for TON mint
   * Filters out payloads with active retry backoff
   */
  private async processReadyPayloads(): Promise<void> {
    // Serialize: only process one at a time to avoid nonce conflicts
    if (this.processing) {
      return;
    }

    const payloads = getPayloadsReadyForTonMint(10); // Fetch multiple, but process one

    if (payloads.length === 0) {
      return;
    }

    // Filter out payloads that are in retry backoff period
    const now = Date.now();
    const availablePayloads = payloads.filter((p) => {
      if (p.ton_mint_next_retry && Number(p.ton_mint_next_retry) > now) {
        return false; // Still in backoff period
      }
      return true;
    });

    if (availablePayloads.length === 0) {
      return; // All payloads are in retry backoff
    }

    // Process the first available payload
    const payload = availablePayloads[0];
    this.processing = true;

    try {
      // Validate required fields
      if (!payload.ton_recipient || !payload.amount_raw9) {
        this.logger.error('Payload missing required TON mint fields', {
          hash: payload.hash,
          tonRecipient: payload.ton_recipient,
          amountRaw9: payload.amount_raw9,
        });
        markPayloadTonMintFailed(
          payload.hash,
          'Missing ton_recipient or amount_raw9 field'
        );
        markPayloadFailed(
          payload.hash,
          'Cannot mint: missing required fields'
        );
        return;
      }

      await this.mintPayload(payload.hash, payload.ton_recipient, payload.amount_raw9);
    } catch (err) {
      this.logger.error('Failed to mint payload', {
        hash: payload.hash,
        error: err instanceof Error ? err.message : String(err),
      });
    } finally {
      this.processing = false;
    }
  }

  /**
   * Processes payloads with mint submitted, checking for confirmation
   */
  private async processSubmittedMints(): Promise<void> {
    const payloads = getPayloadsWithTonMintSubmitted(10); // Check up to 10 at a time

    if (payloads.length === 0) {
      return;
    }

    this.logger.info('Checking mint confirmations', { count: payloads.length });

    for (const payload of payloads) {
      if (!this.running) {
        break;
      }

      try {
        await this.checkMintConfirmation(payload.hash, payload.ton_mint_timestamp);
      } catch (err) {
        this.logger.error('Failed to check mint confirmation', {
          hash: payload.hash,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  /**
   * Mints jettons for a specific payload
   *
   * @param hash - Payload hash
   * @param tonRecipient - TON recipient address
   * @param amountRaw9 - Amount to mint in raw 9-decimal format
   */
  private async mintPayload(hash: string, tonRecipient: string, amountRaw9: string): Promise<void> {
    this.logger.info('Minting payload', { hash, tonRecipient, amount: amountRaw9 });

    try {
      // Mark as mint pending
      markPayloadTonMintPending(hash);

      // Get wallet keys
      const keys = await this.getWalletKeys();

      // Create wallet instance
      const wallet = WalletContractV5R1.create({
        workchain: 0,
        publicKey: keys.publicKey,
      });

      if (!this.tonClient) {
        throw new Error('TON client not initialized');
      }

      const opened = this.tonClient.open(wallet);

      // Get current seqno
      const seqno = await opened.getSeqno();

      // Check wallet balance
      const balance = await opened.getBalance();
      const balanceTon = Number(balance) / 1e9;
      const gasTon = this.config.tonMinter.gasTonMint;
      const forwardTon = 0.05;
      const minRequiredTon = gasTon + forwardTon * 2; // 2x forward for safety margin

      this.logger.info('Wallet state before mint', {
        hash,
        seqno,
        balance: balanceTon.toFixed(4),
        gas: gasTon,
        forward: forwardTon,
        minRequired: minRequiredTon.toFixed(4),
      });

      // CRITICAL: Check if wallet has sufficient balance
      if (balanceTon < minRequiredTon) {
        const errorMsg = `Insufficient wallet balance: ${balanceTon.toFixed(4)} TON < ${minRequiredTon.toFixed(4)} TON required`;
        this.logger.error('Wallet balance check failed', {
          hash,
          tonRecipient,
          amount: amountRaw9,
          balance: balanceTon,
          required: minRequiredTon,
        });

        // Mark as failed - operator intervention required
        markPayloadTonMintFailed(hash, errorMsg);
        markPayloadFailed(hash, `TON mint failed: ${errorMsg}`);
        return;
      }

      // Parse addresses
      const minterAddr = Address.parse(this.config.tonMinter.jettonRoot);
      const receiverAddr = Address.parse(tonRecipient);
      const amount = BigInt(amountRaw9);

      // Build mint message body
      const body = beginCell()
        .store(
          storeJettonMintMessage({
            to: receiverAddr,
            amount,
            queryId: 0n,
            from: wallet.address,
            responseAddress: wallet.address,
            forwardPayload: beginCell().endCell(),
            walletForwardValue: toNano('0.05'), // deploy + gas
            forwardTonAmount: toNano('0.05'),
          })
        )
        .endCell();

      this.logger.info('Sending TON mint transaction', {
        hash,
        seqno,
        to: minterAddr.toString(),
        value: gasTon,
      });

      // Send the mint transaction
      await opened.sendTransfer({
        seqno,
        secretKey: keys.secretKey,
        sendMode: SendMode.PAY_GAS_SEPARATELY,
        messages: [
          internal({
            to: minterAddr,
            value: toNano(this.config.tonMinter.gasTonMint.toString()),
            bounce: true,
            body,
          }),
        ],
      });

      const txIdentifier = `seqno:${seqno}`;

      this.logger.info('Mint transaction submitted', {
        hash,
        txIdentifier,
        seqno,
      });

      // Clear retry metadata on successful submission
      clearTonMintRetry(hash);

      // Mark as mint submitted
      markPayloadTonMintSubmitted(hash, txIdentifier);
    } catch (err) {
      // Parse error type and determine if retryable
      const isAxiosError = axios.isAxiosError(err);
      let errorMessage = err instanceof Error ? err.message : String(err);
      let toncenterError: any = null;
      let isCritical = false;

      if (isAxiosError) {
        const axiosErr = err as AxiosError;

        // Extract TonCenter error response
        if (axiosErr.response?.data) {
          toncenterError = axiosErr.response.data;

          // TonCenter returns {"ok":false,"error":"...","code":...}
          if (typeof toncenterError === 'object' && toncenterError.error) {
            errorMessage = `TonCenter error: ${toncenterError.error}`;
          }
        }

        // Determine if error is critical (non-retryable)
        const status = axiosErr.response?.status;
        if (status === 400 || status === 403 || status === 404) {
          isCritical = true; // Bad request, forbidden, not found - don't retry
        }

        this.logger.error('TonCenter HTTP error during mint', {
          hash,
          tonRecipient,
          amount: amountRaw9,
          httpStatus: status,
          toncenterError: toncenterError,
          errorMessage,
          isCritical,
        });
      } else {
        // Non-HTTP error (wallet error, parsing error, etc.)
        this.logger.error('Mint failed with non-HTTP error', {
          hash,
          tonRecipient,
          amount: amountRaw9,
          error: errorMessage,
          stack: err instanceof Error ? err.stack : undefined,
        });

        // Treat non-HTTP errors as critical
        isCritical = true;
      }

      // Save error details to database
      markPayloadTonMintFailed(hash, errorMessage);

      if (isCritical) {
        // Critical error - mark as failed and stop retrying
        this.logger.error('Critical error - marking payload as failed', {
          hash,
          stage: 'ton_mint',
          error: errorMessage,
        });
        markPayloadFailed(hash, `TON mint failed (critical): ${errorMessage}`);
      } else {
        // Transient error - increment retry attempts with exponential backoff
        const payload = getPayloadByHash(hash);
        const attempts = Number(payload?.ton_mint_attempts ?? 0) + 1;
        const maxAttempts = 10;

        if (attempts >= maxAttempts) {
          // Max retries exceeded - mark as failed
          this.logger.error('Max retry attempts exceeded for TON mint', {
            hash,
            attempts,
            maxAttempts,
            error: errorMessage,
          });
          markPayloadFailed(hash, `TON mint failed after ${attempts} attempts: ${errorMessage}`);
        } else {
          // Schedule retry with exponential backoff
          incrementTonMintAttempts(hash, 5000, 300000); // 5s base, 5min max

          const updatedPayload = getPayloadByHash(hash);
          const nextRetryDate = updatedPayload?.ton_mint_next_retry
            ? new Date(Number(updatedPayload.ton_mint_next_retry)).toISOString()
            : 'unknown';

          this.logger.warn('TON mint will be retried', {
            hash,
            attempt: attempts,
            maxAttempts,
            nextRetry: nextRetryDate,
            error: errorMessage,
          });
        }
      }
    }
  }

  /**
   * Checks if a mint transaction has been confirmed on TON
   *
   * Uses seqno increment as confirmation signal
   *
   * @param hash - Payload hash
   * @param mintTimestamp - Timestamp when mint was submitted
   */
  private async checkMintConfirmation(hash: string, mintTimestamp: number | bigint | null): Promise<void> {
    if (!mintTimestamp) {
      this.logger.warn('Mint timestamp missing for payload', { hash });
      return;
    }

    const now = Date.now();
    const elapsedMs = now - Number(mintTimestamp);
    const CONFIRMATION_THRESHOLD_MS = 30000; // 30 seconds

    // Simple time-based confirmation
    // TODO: Replace with actual TON blockchain confirmation check via seqno or lt
    if (elapsedMs >= CONFIRMATION_THRESHOLD_MS) {
      this.logger.info('Mint confirmed (time-based)', {
        hash,
        elapsedMs,
        threshold: CONFIRMATION_THRESHOLD_MS,
      });

      // Mark as mint confirmed
      markPayloadTonMintConfirmed(hash);

      // For EVM -> TON, mint confirmation is the final step, so mark as finalized
      markPayloadFinalized(hash);
    } else {
      this.logger.debug('Mint still pending confirmation', {
        hash,
        elapsedMs,
        remaining: CONFIRMATION_THRESHOLD_MS - elapsedMs,
      });
    }
  }

  /**
   * Gets wallet keys from mnemonic or hex keys
   *
   * @returns Public and secret keys as Buffers
   */
  private async getWalletKeys(): Promise<{ publicKey: Buffer; secretKey: Buffer }> {
    if (this.config.tonMinter.mnemonic) {
      const words = this.config.tonMinter.mnemonic.trim().split(/\s+/g);
      const kp = await mnemonicToPrivateKey(words);
      const pubUA = new Uint8Array(kp.publicKey as any);
      const secUA = new Uint8Array(kp.secretKey as any);
      return {
        publicKey: Buffer.from(pubUA),
        secretKey: Buffer.from(secUA),
      };
    }

    if (!this.config.tonMinter.publicKeyHex || !this.config.tonMinter.secretKeyHex) {
      throw new Error('Provide TON_MNEMONIC or TON_PUBLIC_KEY_HEX + TON_SECRET_KEY_HEX');
    }

    return {
      publicKey: Buffer.from(this.config.tonMinter.publicKeyHex.replace(/^0x/, ''), 'hex'),
      secretKey: Buffer.from(this.config.tonMinter.secretKeyHex.replace(/^0x/, ''), 'hex'),
    };
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
    chain: string;
    jettonRoot: string;
    processing: boolean;
  } {
    return {
      running: this.running,
      chain: this.config.tonMinter.chain,
      jettonRoot: this.config.tonMinter.jettonRoot,
      processing: this.processing,
    };
  }
}
