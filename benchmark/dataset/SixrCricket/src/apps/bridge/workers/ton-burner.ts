/**
 * @file ton-burner.ts
 * @notice TON burn worker for the Bridge Aggregator
 *
 * This worker polls for payloads that are ready for burning (have quorum),
 * burns the jettons on TON, and tracks burn confirmation status.
 * Only one instance should run to prevent duplicate burns.
 */

import { BridgeConfig } from '../config';
import { getLogger } from '../logger';
import {
  getPayloadsReadyForBurn,
  getPayloadsWithBurnSubmitted,
  markPayloadBurnPending,
  markPayloadBurnSubmitted,
  markPayloadBurnConfirmed,
  markPayloadBurnFailed,
  markPayloadFailed,
} from '../store/payloads';
import { burnOnTon, TonBurnConfig, validateTonConfig } from '../../shared/ton';

/**
 * TON burn worker class
 */
export class TonBurnWorker {
  private config: BridgeConfig;
  private logger: ReturnType<typeof getLogger>;
  private tonConfig: TonBurnConfig;
  private running: boolean = false;
  private burnPollTimer: NodeJS.Timeout | null = null;
  private confirmationPollTimer: NodeJS.Timeout | null = null;

  constructor(config: BridgeConfig) {
    this.config = config;
    this.logger = getLogger();

    // Build TON configuration
    this.tonConfig = {
      chain: config.tonBurner.chain,
      vault: config.tonBurner.vault,
      jettonRoot: config.tonBurner.jettonRoot,
      jettonRootRaw: config.tonBurner.jettonRootRaw,
      publicKeyHex: config.tonBurner.publicKeyHex,
      secretKeyHex: config.tonBurner.secretKeyHex,
      toncenterApiKey: config.tonBurner.toncenterApiKey,
      gasTonBurn: config.tonBurner.gasTonBurn,
    };

    // Validate TON configuration
    validateTonConfig(this.tonConfig);

    this.logger.info('TON burn worker initialized', {
      chain: this.tonConfig.chain,
      vault: this.tonConfig.vault,
      jettonRoot: this.tonConfig.jettonRoot,
    });
  }

  /**
   * Starts the TON burn worker
   */
  public start(): void {
    if (this.running) {
      this.logger.warn('TON burn worker already running');
      return;
    }

    if (!this.config.tonBurner.enabled) {
      this.logger.info('TON burn worker disabled by configuration');
      return;
    }

    this.running = true;
    this.logger.info('Starting TON burn worker', {
      burnPollInterval: this.config.tonBurner.pollIntervalMs,
      confirmationCheckInterval: this.config.tonBurner.confirmationCheckIntervalMs,
    });

    // Start polling loops
    this.pollBurnQueue();
    this.pollConfirmationQueue();
  }

  /**
   * Stops the TON burn worker
   */
  public stop(): void {
    if (!this.running) {
      return;
    }

    this.running = false;

    if (this.burnPollTimer) {
      clearTimeout(this.burnPollTimer);
      this.burnPollTimer = null;
    }

    if (this.confirmationPollTimer) {
      clearTimeout(this.confirmationPollTimer);
      this.confirmationPollTimer = null;
    }

    this.logger.info('TON burn worker stopped');
  }

  /**
   * Poll loop for burning payloads
   */
  private pollBurnQueue(): void {
    if (!this.running) {
      return;
    }

    this.processReadyPayloads()
      .catch((err) => {
        this.logger.error('Burn poll cycle error', {
          error: err instanceof Error ? err.message : String(err),
          stack: err instanceof Error ? err.stack : undefined,
        });
      })
      .finally(() => {
        if (this.running) {
          this.burnPollTimer = setTimeout(
            () => this.pollBurnQueue(),
            this.config.tonBurner.pollIntervalMs
          );
        }
      });
  }

  /**
   * Poll loop for checking burn confirmations
   */
  private pollConfirmationQueue(): void {
    if (!this.running) {
      return;
    }

    this.processSubmittedBurns()
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
            this.config.tonBurner.confirmationCheckIntervalMs
          );
        }
      });
  }

  /**
   * Processes payloads that are ready for burn
   */
  private async processReadyPayloads(): Promise<void> {
    const payloads = getPayloadsReadyForBurn(10); // Process up to 10 at a time

    if (payloads.length === 0) {
      return;
    }

    this.logger.info('Processing payloads ready for burn', { count: payloads.length });

    for (const payload of payloads) {
      if (!this.running) {
        break;
      }

      try {
        // Check if amount_raw9 is available
        if (!payload.amount_raw9) {
          this.logger.error('Payload missing amount_raw9, cannot burn', {
            hash: payload.hash,
            amount: payload.amount,
          });
          markPayloadBurnFailed(
            payload.hash,
            'Missing amount_raw9 field - payload was created before migration'
          );
          markPayloadFailed(
            payload.hash,
            'Cannot burn: missing amount_raw9 field'
          );
          continue;
        }

        await this.burnPayload(payload.hash, payload.amount_raw9);
      } catch (err) {
        this.logger.error('Failed to burn payload', {
          hash: payload.hash,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  /**
   * Processes payloads with burn submitted, checking for confirmation
   */
  private async processSubmittedBurns(): Promise<void> {
    const payloads = getPayloadsWithBurnSubmitted(10); // Check up to 10 at a time

    if (payloads.length === 0) {
      return;
    }

    this.logger.info('Checking burn confirmations', { count: payloads.length });

    for (const payload of payloads) {
      if (!this.running) {
        break;
      }

      try {
        await this.checkBurnConfirmation(payload.hash, payload.burn_timestamp);
      } catch (err) {
        this.logger.error('Failed to check burn confirmation', {
          hash: payload.hash,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  /**
   * Burns jettons for a specific payload
   *
   * @param hash - Payload hash
   * @param amountRaw9 - Amount to burn in raw 9-decimal format
   */
  private async burnPayload(hash: string, amountRaw9: string): Promise<void> {
    this.logger.info('Burning payload', { hash, amount: amountRaw9 });

    try {
      // Mark as burn pending
      markPayloadBurnPending(hash);

      // Execute burn on TON
      const burnResult = await burnOnTon(this.tonConfig, amountRaw9);

      this.logger.info('Burn transaction submitted', {
        hash,
        burnTxHash: burnResult.txHash,
        explorerUrl: burnResult.explorerUrl,
      });

      // Mark as burn submitted
      markPayloadBurnSubmitted(hash, burnResult.txHash);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);

      this.logger.error('Burn failed', {
        hash,
        error: errorMessage,
        stack: err instanceof Error ? err.stack : undefined,
      });

      // Mark burn as failed
      markPayloadBurnFailed(hash, errorMessage);

      // Also mark overall payload as failed since burn is required
      markPayloadFailed(hash, `TON burn failed: ${errorMessage}`);
    }
  }

  /**
   * Checks if a burn transaction has been confirmed on TON
   *
   * In a production implementation, this would query TON blockchain
   * to verify the burn transaction has been confirmed.
   *
   * For now, we use a simple time-based confirmation (30 seconds).
   *
   * @param hash - Payload hash
   * @param burnTimestamp - Timestamp when burn was submitted
   */
  private async checkBurnConfirmation(hash: string, burnTimestamp: number | null): Promise<void> {
    if (!burnTimestamp) {
      this.logger.warn('Burn timestamp missing for payload', { hash });
      return;
    }

    const now = Date.now();
    const elapsedMs = now - burnTimestamp;
    const CONFIRMATION_THRESHOLD_MS = 30000; // 30 seconds

    // Simple time-based confirmation
    // TODO: Replace with actual TON blockchain confirmation check
    if (elapsedMs >= CONFIRMATION_THRESHOLD_MS) {
      this.logger.info('Burn confirmed (time-based)', {
        hash,
        elapsedMs,
        threshold: CONFIRMATION_THRESHOLD_MS,
      });

      // Mark as burn confirmed
      markPayloadBurnConfirmed(hash);
    } else {
      this.logger.debug('Burn still pending confirmation', {
        hash,
        elapsedMs,
        remaining: CONFIRMATION_THRESHOLD_MS - elapsedMs,
      });
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
    chain: string;
    vault: string;
    jettonRoot: string;
  } {
    return {
      running: this.running,
      chain: this.tonConfig.chain,
      vault: this.tonConfig.vault,
      jettonRoot: this.tonConfig.jettonRoot,
    };
  }
}
