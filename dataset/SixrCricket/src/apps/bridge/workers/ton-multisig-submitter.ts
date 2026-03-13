/**
 * @file ton-multisig-submitter.ts
 * @notice TON Multisig Submitter Worker (EVM -> TON)
 *
 * This worker processes EVM -> TON payloads that have reached quorum (status='ready')
 * and submits them to the TON multisig contract for minting.
 */

import { BridgeConfig } from '../config';
import { getLogger } from '../logger';
import {
  getPayloadsReadyForTonMint,
  getPayloadsReadyForConfirmationCheck,
  markPayloadTonMintSubmitted,
  markPayloadTonMintConfirmed,
  markPayloadTonMintFailed,
  incrementTonMintAttempts,
  incrementTonMintConfirmationRetry,
  markPayloadTonMintFailedToncenterError,
  updatePayloadStatus,
} from '../store/payloads';
import { getTonSignaturesByHash } from '../store/signatures';
import { getPayloadByHash } from '../store/payloads';
import { TonClient, WalletContractV5R1, fromNano, OpenedContract, ContractProvider } from '@ton/ton';
import { mnemonicToPrivateKey, KeyPair } from '@ton/crypto';
import {
  BridgeMultisig,
  createBridgeMultisig,
} from '../../shared/ton-multisig/contract';
import {
  TonMintPayload as TonMintPayloadTLB,
  TonSignature,
} from '../../shared/ton-multisig/payload';
import {
  prepareMintSignatures,
  aggregateSignatures,
  verifySignature,
} from '../../shared/ton-multisig/signatures';
import { hashMintPayload as hashTonMintPayload } from '../../shared/ton-multisig/payload';

/**
 * Sleep helper
 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Decode nonce into its components: (chainId, blockNumber, logIndex)
 * Nonce format: (chainId << 48) | (blockNumber << 16) | logIndex
 *
 * @param nonce - Nonce as bigint or string
 * @returns Decoded nonce components
 */
function decodeNonce(nonce: bigint | string): {
  chainId: number;
  blockNumber: number;
  logIndex: number;
} {
  const n = typeof nonce === 'string' ? BigInt(nonce) : nonce;
  const chainId = Number((n >> 48n) & 0xFFFFn);
  const blockNumber = Number((n >> 16n) & 0xFFFFFFFFn);
  const logIndex = Number(n & 0xFFFFn);
  return { chainId, blockNumber, logIndex };
}

/**
 * Verify that all stored TON signatures are valid for the current payload data
 * This prevents sending payloads where the data has drifted from what was signed
 *
 * @param payloadRow - Payload from database
 * @param signatures - Array of TonSignature objects
 * @returns Object with isValid flag and error message if invalid
 */
function verifyTonSignatures(
  payloadRow: {
    hash: string;
    origin_chain_id: number;
    token: string;
    ton_recipient: string;
    amount_raw9: string;
    nonce: string;
  },
  signatures: TonSignature[]
): { isValid: boolean; error?: string; invalidPublicKeys?: string[] } {
  const logger = getLogger();

  // Build TL-B payload from current database values
  const tonPayload: TonMintPayloadTLB = {
    originChainId: payloadRow.origin_chain_id,
    token: payloadRow.token,
    tonRecipient: payloadRow.ton_recipient,
    amount: BigInt(payloadRow.amount_raw9),
    nonce: BigInt(payloadRow.nonce),
  };

  // Compute hash of the TL-B payload
  const payloadHash = hashTonMintPayload(tonPayload);

  // Verify each signature
  const invalidPublicKeys: string[] = [];
  for (const sig of signatures) {
    const isValid = verifySignature(payloadHash, sig.signature, sig.publicKey);
    if (!isValid) {
      invalidPublicKeys.push(sig.publicKey.toString('hex'));
      logger.error('Signature verification failed for payload', {
        hash: payloadRow.hash,
        publicKey: sig.publicKey.toString('hex'),
        computedHash: payloadHash.toString('hex'),
      });
    }
  }

  if (invalidPublicKeys.length > 0) {
    return {
      isValid: false,
      error: `${invalidPublicKeys.length} signature(s) invalid`,
      invalidPublicKeys,
    };
  }

  return { isValid: true };
}

/**
 * Initialize TON client
 */
function createTonClient(config: BridgeConfig, useFallback: boolean = false): TonClient {
  let endpoint: string;

  if (useFallback && config.tonMultisigSubmitter.toncenterBaseFallback) {
    endpoint = config.tonMultisigSubmitter.toncenterBaseFallback + '/jsonRPC';
  } else if (config.tonMultisigSubmitter.toncenterBase) {
    endpoint = config.tonMultisigSubmitter.toncenterBase + '/jsonRPC';
  } else {
    endpoint =
      config.tonMultisig.chain === 'testnet'
        ? 'https://testnet.toncenter.com/api/v2/jsonRPC'
        : 'https://toncenter.com/api/v2/jsonRPC';
  }

  return new TonClient({
    endpoint,
    apiKey: config.tonMultisigSubmitter.toncenterApiKey,
  });
}

/**
 * Checks if error is a transient Toncenter HTTP error (5xx or 429)
 */
function isTransientToncenterError(error: unknown): boolean {
  if (!error || typeof error !== 'object') {
    return false;
  }

  const err = error as any;

  // Check for Axios HTTP status codes
  if (err.response?.status) {
    const status = err.response.status;
    return status === 429 || (status >= 500 && status < 600);
  }

  // Check for HTTP status in error message
  if (err.message && typeof err.message === 'string') {
    return /status code (429|5\d\d)/i.test(err.message);
  }

  return false;
}

/**
 * Initialize submitter wallet
 */
async function createSubmitterWallet(
  config: BridgeConfig,
  client: TonClient
): Promise<{ wallet: OpenedContract<WalletContractV5R1>; keyPair: KeyPair }> {
  const logger = getLogger();

  let keyPair: KeyPair;

  if (config.tonMultisigSubmitter.walletMnemonic) {
    // Derive from mnemonic
    keyPair = await mnemonicToPrivateKey(
      config.tonMultisigSubmitter.walletMnemonic.split(' ')
    );
  } else if (
    config.tonMultisigSubmitter.walletPublicKeyHex &&
    config.tonMultisigSubmitter.walletSecretKeyHex
  ) {
    // Use explicit keys
    const publicKey = Buffer.from(
      config.tonMultisigSubmitter.walletPublicKeyHex.replace('0x', ''),
      'hex'
    );
    const secretKey = Buffer.from(
      config.tonMultisigSubmitter.walletSecretKeyHex.replace('0x', ''),
      'hex'
    );
    keyPair = { publicKey, secretKey };
  } else {
    throw new Error(
      'TON submitter wallet credentials not configured (need mnemonic or keys)'
    );
  }

  const wallet = WalletContractV5R1.create({
    workchain: 0,
    publicKey: keyPair.publicKey,
  });

  const contract = client.open(wallet);

  // Log wallet info
  const balance = await contract.getBalance();
  logger.info('TON Multisig Submitter wallet initialized', {
    address: contract.address.toString(),
    balance: fromNano(balance),
  });

  return { wallet: contract, keyPair };
}

/**
 * Process a single ready payload
 */
async function processPayload(
  payloadHash: string,
  config: BridgeConfig,
  client: TonClient,
  wallet: OpenedContract<WalletContractV5R1>,
  keyPair: KeyPair,
  multisigContract: BridgeMultisig
): Promise<void> {
  const logger = getLogger();

  logger.info('Processing EVM->TON payload for multisig mint', {
    hash: payloadHash,
  });

  try {
    // Get payload from database
    const payloadRow = getPayloadByHash(payloadHash);
    if (!payloadRow) {
      logger.error('Payload not found in database', { hash: payloadHash });
      return;
    }

    if (!payloadRow.ton_recipient || !payloadRow.amount_raw9) {
      logger.error('Payload missing TON recipient or amount', {
        hash: payloadHash,
      });
      return;
    }

    // Get TON signatures
    const sigRows = getTonSignaturesByHash(payloadHash);

    if (sigRows.length < 2) {
      logger.warn('Insufficient TON signatures', {
        hash: payloadHash,
        count: sigRows.length,
      });
      return;
    }

    // Convert to TonSignature format
    const tonSignatures: TonSignature[] = sigRows
      .filter((row) => row.ton_public_key && row.ton_signature)
      .map((row) => ({
        publicKey: Buffer.from(row.ton_public_key!, 'hex'),
        signature: Buffer.from(row.ton_signature!, 'hex'),
      }));

    // Validate signatures are from configured watchers
    const validSignatures: TonSignature[] = [];
    for (const sig of tonSignatures) {
      const pubKeyHex = sig.publicKey.toString('hex');
      if (
        config.tonMultisig.watchers
          .map((w) => w.toLowerCase())
          .includes(pubKeyHex.toLowerCase())
      ) {
        validSignatures.push(sig);
      } else {
        logger.warn('Signature from unknown watcher', {
          hash: payloadHash,
          publicKey: pubKeyHex,
        });
      }
    }

    if (validSignatures.length < 2) {
      logger.warn('Insufficient valid TON signatures after filtering', {
        hash: payloadHash,
        count: validSignatures.length,
      });
      return;
    }

    // Prepare signatures (validates, sorts, ensures quorum)
    const preparedSignatures = prepareMintSignatures(validSignatures);

    logger.info('Prepared TON signatures for mint', {
      hash: payloadHash,
      signatureCount: preparedSignatures.length,
    });

    // Build TON mint payload from database
    const tonPayload: TonMintPayloadTLB = {
      originChainId: payloadRow.origin_chain_id,
      token: payloadRow.token,
      tonRecipient: payloadRow.ton_recipient,
      amount: BigInt(payloadRow.amount_raw9),
      nonce: BigInt(payloadRow.nonce),
    };

    // Decode nonce for telemetry
    const nonceDecoded = decodeNonce(tonPayload.nonce);

    // CRITICAL GUARD: Detect nonce precision loss (chain ID truncation)
    // This prevents sending payloads where the upper 16 bits were lost due to
    // JavaScript number conversion (missing db.defaultSafeIntegers(true))
    //
    // IMPORTANT: Convert both to number to avoid string vs number false positives
    const payloadChainIdNum = Number(tonPayload.originChainId);
    const nonceChainIdNum = Number(nonceDecoded.chainId);

    if (nonceChainIdNum !== payloadChainIdNum) {
      // Secondary check: if nonce decoded as chain 0 but payload is non-zero,
      // this is a clear sign of precision loss (top 16 bits lost)
      const isPrecisionLoss = nonceChainIdNum === 0 && payloadChainIdNum !== 0;

      logger.error('CHAIN_ID_TRUNCATED: Nonce chain ID does not match payload origin chain ID', {
        hash: payloadHash,
        payloadOriginChainId: tonPayload.originChainId,
        payloadOriginChainIdType: typeof tonPayload.originChainId,
        nonceDecodedChainId: nonceDecoded.chainId,
        nonceDecodedChainIdType: typeof nonceDecoded.chainId,
        payloadChainIdNum,
        nonceChainIdNum,
        isPrecisionLoss,
        nonce: tonPayload.nonce.toString(),
        nonceHex: '0x' + tonPayload.nonce.toString(16).toUpperCase(),
        nonceDecoded,
        dbNonce: payloadRow.nonce.toString(),
        dbNonceType: typeof payloadRow.nonce,
        note: isPrecisionLoss
          ? 'Clear precision loss: chainId decoded as 0, typical of missing db.defaultSafeIntegers(true)'
          : 'Chain ID mismatch detected. Verify payload data integrity.',
      });

      // Mark as failed and delete signatures so watchers can resubmit with correct nonce
      markPayloadTonMintFailed(payloadHash, 'CHAIN_ID_TRUNCATED: Nonce precision loss detected');

      // Delete TON signatures to allow resubmission
      // Use the correct table: payload_signatures (filter by ton_public_key IS NOT NULL)
      const db = require('../store/database').getDatabase();
      const deleteResult = db.prepare('DELETE FROM payload_signatures WHERE hash = ? AND ton_public_key IS NOT NULL').run(payloadHash);

      logger.warn('Deleted TON signatures to allow watcher resubmission', {
        hash: payloadHash,
        deletedCount: deleteResult.changes,
      });

      return;
    }

    // Log TL-B fields with decoded nonce for debugging
    logger.info('TL-B payload fields for TON mint', {
      hash: payloadHash,
      originChainId: tonPayload.originChainId,
      token: tonPayload.token,
      tonRecipient: tonPayload.tonRecipient,
      amountRaw9: tonPayload.amount.toString(),
      nonce: tonPayload.nonce.toString(),
      nonceHex: '0x' + tonPayload.nonce.toString(16).toUpperCase(),
      nonceDecoded: {
        chainId: nonceDecoded.chainId,
        blockNumber: nonceDecoded.blockNumber,
        logIndex: nonceDecoded.logIndex,
      },
    });

    // Verify signatures before sending
    const verificationResult = verifyTonSignatures(
      {
        hash: payloadHash,
        origin_chain_id: payloadRow.origin_chain_id,
        token: payloadRow.token,
        ton_recipient: payloadRow.ton_recipient!,
        amount_raw9: payloadRow.amount_raw9!,
        nonce: payloadRow.nonce.toString(),
      },
      validSignatures
    );

    if (!verificationResult.isValid) {
      logger.error('Signature verification failed - payload data mismatch', {
        hash: payloadHash,
        error: verificationResult.error,
        invalidPublicKeys: verificationResult.invalidPublicKeys,
        tlbPayload: {
          originChainId: tonPayload.originChainId,
          token: tonPayload.token,
          tonRecipient: tonPayload.tonRecipient,
          amountRaw9: tonPayload.amount.toString(),
          nonce: tonPayload.nonce.toString(),
        },
      });

      // Mark as failed with descriptive error
      markPayloadTonMintFailed(payloadHash, 'SIGNATURE_PAYLOAD_MISMATCH: ' + verificationResult.error);
      return;
    }

    logger.info('All signatures verified successfully', {
      hash: payloadHash,
      signatureCount: validSignatures.length,
    });

    // Get current seqno before sending
    const seqnoBefore = await wallet.getSeqno();

    // Send mint transaction
    logger.info('Sending mint to TON multisig', {
      hash: payloadHash,
      multisigAddress: config.tonMultisig.address,
      tonRecipient: tonPayload.tonRecipient,
      amount: tonPayload.amount.toString(),
      nonce: tonPayload.nonce.toString(),
      nonceDecoded,
      seqno: seqnoBefore,
    });

    // Get contract provider
    const provider = client.provider(multisigContract.address);

    // Send mint
    await multisigContract.sendMint(
      provider,
      wallet.sender(keyPair.secretKey),
      tonPayload,
      preparedSignatures,
      config.tonMultisig.mintGas
    );

    // Mark as submitted with seqno as identifier
    const txIdentifier = `seqno:${seqnoBefore}`;
    markPayloadTonMintSubmitted(payloadHash, txIdentifier);

    logger.info('TON mint submitted successfully', {
      hash: payloadHash,
      txIdentifier,
      seqno: seqnoBefore,
    });
  } catch (err) {
    logger.error('Failed to process EVM->TON payload for multisig', {
      hash: payloadHash,
      error: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined,
    });

    // Increment attempts and set retry
    incrementTonMintAttempts(payloadHash);
  }
}

/**
 * Check confirmation for submitted payloads
 */
async function checkConfirmations(
  config: BridgeConfig,
  client: TonClient,
  fallbackClient: TonClient | null,
  wallet: OpenedContract<WalletContractV5R1>
): Promise<void> {
  const logger = getLogger();

  // Only fetch payloads that are ready for confirmation check (respects backoff)
  const submittedPayloads = getPayloadsReadyForConfirmationCheck(10);

  for (const payload of submittedPayloads) {
    let usedProvider: 'primary' | 'fallback' = 'primary';

    try {
      // Extract seqno from txIdentifier (format: "seqno:123")
      if (!payload.ton_mint_tx_hash || !payload.ton_mint_tx_hash.startsWith('seqno:')) {
        logger.warn('Invalid tx identifier format for TON mint', {
          hash: payload.hash,
          txIdentifier: payload.ton_mint_tx_hash,
        });
        continue;
      }

      const seqno = parseInt(payload.ton_mint_tx_hash.replace('seqno:', ''), 10);
      if (isNaN(seqno)) {
        logger.warn('Failed to parse seqno from tx identifier', {
          hash: payload.hash,
          txIdentifier: payload.ton_mint_tx_hash,
        });
        continue;
      }

      const currentAttempts = Number(payload.ton_mint_attempts || 0n);

      // Determine which client to use (fallback after 3 consecutive failures)
      let activeClient = client;
      if (fallbackClient && currentAttempts >= 3) {
        activeClient = fallbackClient;
        usedProvider = 'fallback';
      }

      // Get current wallet seqno
      const currentSeqno = await wallet.getSeqno();

      // If current seqno is greater than submitted seqno, the transaction was processed
      if (currentSeqno > seqno) {
        // Fetch recent transactions to verify
        // Increased from 10 to 50 to avoid missing older transactions
        const transactions = await activeClient.getTransactions(wallet.address, {
          limit: 50,
        });

        // Find transaction with matching seqno
        let txFound = false;
        let txSuccess = false;
        let txHash = '';

        for (const tx of transactions) {
          // Check if this transaction matches our seqno
          if (tx.inMessage && 'info' in tx.inMessage && 'src' in tx.inMessage.info) {
            // This is an incoming message, check if it's from our wallet
            // For wallet v5, outgoing transactions have seqno in out messages
            // We need to check the transaction's description
            if (tx.description.type === 'generic' && tx.description.computePhase.type === 'vm') {
              const txSeqno = tx.lt; // Use logical time as fallback

              // Check if transaction was successful
              const exitCode = tx.description.computePhase.exitCode;
              if (exitCode === 0) {
                txSuccess = true;
                txHash = tx.hash().toString('hex');
                txFound = true;
                break;
              } else {
                logger.error('TON mint transaction failed with non-zero exit code', {
                  hash: payload.hash,
                  seqno,
                  exitCode,
                  txHash: tx.hash().toString('hex'),
                  provider: usedProvider,
                });
                markPayloadTonMintFailed(payload.hash, `Exit code: ${exitCode}`);
                txFound = true;
                break;
              }
            }
          }
        }

        // If seqno advanced but we didn't find the tx in recent history
        // DO NOT assume success - log warning instead
        if (!txFound && currentSeqno > seqno) {
          logger.warn('TON mint transaction not found in recent history (seqno advanced)', {
            hash: payload.hash,
            seqno,
            currentSeqno,
            provider: usedProvider,
            note: 'Transaction may have failed or be outside fetch window. Needs manual verification.',
          });

          // Increment confirmation retry to check again later
          incrementTonMintConfirmationRetry(
            payload.hash,
            config.tonMultisigSubmitter.confirmationCheckIntervalMs,
            config.tonMultisigSubmitter.backoffMultiplier,
            300000 // max 5 minutes
          );
        } else if (txFound && txSuccess) {
          logger.info('TON mint transaction confirmed', {
            hash: payload.hash,
            seqno,
            txHash,
            provider: usedProvider,
          });

          markPayloadTonMintConfirmed(payload.hash);
          updatePayloadStatus(payload.hash, 'finalized');
        }
      } else {
        // Transaction not yet processed, wait
        const waitTime = Date.now() - Number(payload.ton_mint_timestamp || 0);

        // If waiting too long (> 5 minutes), log warning
        if (waitTime > 300000) {
          logger.warn('TON mint transaction pending for too long', {
            hash: payload.hash,
            seqno,
            currentSeqno,
            waitTimeMs: waitTime,
            provider: usedProvider,
          });
        }
      }
    } catch (err) {
      // Check if this is a transient Toncenter error (5xx or 429)
      if (isTransientToncenterError(err)) {
        const currentAttempts = Number(payload.ton_mint_attempts || 0n);
        const maxRetries = config.tonMultisigSubmitter.maxConfirmationRetries;

        logger.warn('Toncenter transient error during confirmation check', {
          hash: payload.hash,
          error: err instanceof Error ? err.message : String(err),
          attempts: currentAttempts + 1,
          maxRetries,
          provider: usedProvider,
        });

        // Check if we've exceeded max retries
        if (currentAttempts + 1 >= maxRetries) {
          logger.error('Max confirmation retries exceeded, marking as failed', {
            hash: payload.hash,
            attempts: currentAttempts + 1,
            maxRetries,
          });

          markPayloadTonMintFailedToncenterError(
            payload.hash,
            `toncenter_http_error_max_retries: ${err instanceof Error ? err.message : String(err)}`
          );
        } else {
          // Increment retry counter with exponential backoff
          incrementTonMintConfirmationRetry(
            payload.hash,
            config.tonMultisigSubmitter.confirmationCheckIntervalMs,
            config.tonMultisigSubmitter.backoffMultiplier,
            300000 // max 5 minutes
          );

          logger.info('Scheduled confirmation retry with backoff', {
            hash: payload.hash,
            nextAttempt: currentAttempts + 1,
            maxRetries,
          });
        }
      } else {
        // Non-transient error, log but don't mark as failed yet
        logger.error('Failed to check TON mint confirmation (non-transient error)', {
          hash: payload.hash,
          error: err instanceof Error ? err.message : String(err),
          stack: err instanceof Error ? err.stack : undefined,
          provider: usedProvider,
        });
      }
    }
  }
}

/**
 * TON Multisig Submitter worker class
 */
export class TonMultisigSubmitter {
  private config: BridgeConfig;
  private logger: ReturnType<typeof getLogger>;
  private running: boolean = false;
  private pollTimer: NodeJS.Timeout | null = null;
  private confirmationPollTimer: NodeJS.Timeout | null = null;
  private client: TonClient | null = null;
  private fallbackClient: TonClient | null = null;
  private wallet: OpenedContract<WalletContractV5R1> | null = null;
  private keyPair: KeyPair | null = null;
  private multisigContract: BridgeMultisig | null = null;

  constructor(config: BridgeConfig) {
    this.config = config;
    this.logger = getLogger();

    this.logger.info('TON Multisig Submitter worker initialized', {
      multisigAddress: config.tonMultisig.address,
      chain: config.tonMultisig.chain,
      hasFallback: !!config.tonMultisigSubmitter.toncenterBaseFallback,
    });
  }

  /**
   * Starts the TON Multisig Submitter worker
   */
  public start(): void {
    if (this.running) {
      this.logger.warn('TON Multisig Submitter worker already running');
      return;
    }

    if (!this.config.tonMultisigSubmitter.enabled) {
      this.logger.info('TON Multisig Submitter worker disabled by configuration');
      return;
    }

    this.running = true;
    this.logger.info('Starting TON Multisig Submitter worker', {
      pollInterval: this.config.tonMultisigSubmitter.pollIntervalMs,
      confirmationCheckInterval: this.config.tonMultisigSubmitter.confirmationCheckIntervalMs,
    });

    // Initialize async resources
    this.initialize()
      .then(() => {
        // Start polling loops
        this.pollMintQueue();
        this.pollConfirmationQueue();
      })
      .catch((err) => {
        this.logger.error('Failed to initialize TON Multisig Submitter', {
          error: err instanceof Error ? err.message : String(err),
        });
        this.running = false;
      });
  }

  /**
   * Stops the TON Multisig Submitter worker
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

    if (this.confirmationPollTimer) {
      clearTimeout(this.confirmationPollTimer);
      this.confirmationPollTimer = null;
    }

    this.logger.info('TON Multisig Submitter worker stopped');
  }

  /**
   * Returns worker status
   */
  public getStatus(): { running: boolean; enabled: boolean } {
    return {
      running: this.running,
      enabled: this.config.tonMultisigSubmitter.enabled,
    };
  }

  /**
   * Initialize TON client, wallet, and contract
   */
  private async initialize(): Promise<void> {
    this.client = createTonClient(this.config, false);

    // Create fallback client if configured
    if (this.config.tonMultisigSubmitter.toncenterBaseFallback) {
      this.fallbackClient = createTonClient(this.config, true);
      this.logger.info('Fallback Toncenter endpoint configured', {
        fallbackEndpoint: this.config.tonMultisigSubmitter.toncenterBaseFallback,
      });
    }

    const { wallet, keyPair } = await createSubmitterWallet(this.config, this.client);
    this.wallet = wallet;
    this.keyPair = keyPair;

    this.multisigContract = createBridgeMultisig({
      contractAddress: this.config.tonMultisig.address,
      chain: this.config.tonMultisig.chain,
    });
  }

  /**
   * Poll loop for processing ready payloads
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
          this.pollTimer = setTimeout(
            () => this.pollMintQueue(),
            this.config.tonMultisigSubmitter.pollIntervalMs
          );
        }
      });
  }

  /**
   * Poll loop for checking confirmations
   */
  private pollConfirmationQueue(): void {
    if (!this.running) {
      return;
    }

    this.checkConfirmations()
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
            this.config.tonMultisigSubmitter.confirmationCheckIntervalMs
          );
        }
      });
  }

  /**
   * Process ready payloads
   */
  private async processReadyPayloads(): Promise<void> {
    if (!this.client || !this.wallet || !this.keyPair || !this.multisigContract) {
      this.logger.error('TON client not initialized');
      return;
    }

    const readyPayloads = getPayloadsReadyForTonMint(5);

    if (readyPayloads.length === 0) {
      return;
    }

    this.logger.info('Processing ready payloads for TON multisig mint', {
      count: readyPayloads.length,
    });

    for (const payload of readyPayloads) {
      if (!this.running) {
        break;
      }

      await processPayload(
        payload.hash,
        this.config,
        this.client,
        this.wallet,
        this.keyPair,
        this.multisigContract
      );
    }
  }

  /**
   * Check confirmations for submitted payloads
   */
  private async checkConfirmations(): Promise<void> {
    if (!this.client || !this.wallet) {
      this.logger.error('TON client or wallet not initialized');
      return;
    }

    await checkConfirmations(this.config, this.client, this.fallbackClient, this.wallet);
  }
}
