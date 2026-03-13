/**
 * @file config.ts
 * @notice Configuration management for the Bridge Aggregator
 *
 * This module loads and validates all configuration from environment variables
 * and provides a typed configuration object for use across the application.
 */

import 'dotenv/config';
import { parseWatcherSet, normalizeAddress } from '../shared/signature';
import { normalizeTonPublicKey } from '../shared/ton';

/**
 * Bridge Aggregator configuration
 */
export interface BridgeConfig {
  // Database
  database: {
    path: string;
    verbose: boolean;
  };

  // Network
  network: {
    port: number;
    host: string;
  };

  // Base Chain (optional)
  base: {
    enabled: boolean;
    rpcUrl: string;
    chainId: number;
    privateKey: string;
    multisigAddress: string;
    oftAddress: string;
    minConfirmations: number;
  } | null;

  // BSC Chain (optional)
  bsc: {
    enabled: boolean;
    rpcUrl: string;
    chainId: number;
    privateKey: string;
    multisigAddress: string;
    oftAddress: string;
    minConfirmations: number;
  } | null;

  // Watcher Set
  watchers: {
    addresses: string[];
    threshold: number;
  };

  // Worker Settings
  worker: {
    pollIntervalMs: number;
    maxRetries: number;
    retryBackoffMs: number;
    enabled: boolean;
  };

  // TON Burn Worker Settings (TON -> EVM)
  tonBurner: {
    enabled: boolean;
    chain: 'mainnet' | 'testnet';
    vault: string;
    jettonRoot: string;
    jettonRootRaw: string;
    publicKeyHex: string;
    secretKeyHex: string;
    toncenterApiKey: string;
    gasTonBurn: number;
    pollIntervalMs: number;
    confirmationCheckIntervalMs: number;
  };

  // TON Mint Worker Settings (EVM -> TON) - LEGACY
  tonMinter: {
    enabled: boolean;
    chain: 'mainnet' | 'testnet';
    jettonRoot: string;
    mnemonic: string;
    publicKeyHex: string;
    secretKeyHex: string;
    toncenterBase: string;
    toncenterApiKey: string;
    gasTonMint: number;
    pollIntervalMs: number;
    confirmationCheckIntervalMs: number;
  };

  // TON Multisig Contract Configuration (EVM -> TON)
  tonMultisig: {
    enabled: boolean;
    address: string;
    chain: 'mainnet' | 'testnet';
    watchers: string[];
    governance: string[];
    jettonRoot: string;
    mintGas: number; // Gas in TON for mint operations
    governanceGas: number; // Gas in TON for governance operations
  };

  // TON Multisig Submitter Worker Settings (EVM -> TON)
  tonMultisigSubmitter: {
    enabled: boolean;
    walletMnemonic: string;
    walletPublicKeyHex: string;
    walletSecretKeyHex: string;
    toncenterBase: string;
    toncenterBaseFallback: string;
    toncenterApiKey: string;
    sendAmount: string;
    pollIntervalMs: number;
    confirmationCheckIntervalMs: number;
    maxConfirmationRetries: number;
    backoffMultiplier: number;
  };

  // Token Configuration
  token: {
    decimals: number;
  };

  // Logging
  logging: {
    level: string;
    format: 'json' | 'text';
  };

  // Security
  security: {
    apiKey: string | null; // If set, requires X-API-Key header for /payloads routes
  };
}

/**
 * Validates and loads configuration from environment variables
 *
 * @returns Validated configuration
 * @throws Error if required configuration is missing or invalid
 */
export function loadConfig(): BridgeConfig {
  // Database
  const databasePath = process.env.BRIDGE_DB_PATH || './data/bridge.db';
  const databaseVerbose = process.env.BRIDGE_DB_VERBOSE === 'true';

  // Network
  const port = parseInt(process.env.BRIDGE_PORT || '3000', 10);
  const host = process.env.BRIDGE_HOST || '0.0.0.0';

  if (isNaN(port) || port < 1 || port > 65535) {
    throw new Error(`Invalid BRIDGE_PORT: ${process.env.BRIDGE_PORT}. Must be between 1 and 65535.`);
  }

  // Base Chain (optional)
  let baseConfig: BridgeConfig['base'] = null;
  const rpcUrl = process.env.RPC_URL_BASE;
  const privateKey = process.env.PRIVATE_KEY;
  const multisigAddress = process.env.MULTISIG_ADDRESS;
  const oftAddress = process.env.OFT_CONTRACT_ADDRESS;

  if (rpcUrl && privateKey && multisigAddress && oftAddress) {
    const chainId = parseInt(process.env.BASE_CHAIN_ID || '8453', 10);
    if (isNaN(chainId)) {
      throw new Error(`Invalid BASE_CHAIN_ID: ${process.env.BASE_CHAIN_ID}`);
    }

    if (!privateKey.startsWith('0x') || privateKey.length !== 66) {
      throw new Error('PRIVATE_KEY must be a 32-byte hex string starting with 0x');
    }

    const baseMinConfirmations = parseInt(process.env.BASE_MIN_CONFIRMATIONS || '5', 10);
    if (isNaN(baseMinConfirmations) || baseMinConfirmations < 0) {
      throw new Error(`Invalid BASE_MIN_CONFIRMATIONS: ${process.env.BASE_MIN_CONFIRMATIONS}. Must be non-negative.`);
    }

    let normalizedMultisig: string;
    let normalizedOft: string;

    try {
      normalizedMultisig = normalizeAddress(multisigAddress, 'MULTISIG_ADDRESS');
    } catch (err) {
      throw new Error(
        `Invalid MULTISIG_ADDRESS: ${multisigAddress}. ${err instanceof Error ? err.message : ''}`
      );
    }

    try {
      normalizedOft = normalizeAddress(oftAddress, 'OFT_CONTRACT_ADDRESS');
    } catch (err) {
      throw new Error(
        `Invalid OFT_CONTRACT_ADDRESS: ${oftAddress}. ${err instanceof Error ? err.message : ''}`
      );
    }

    baseConfig = {
      enabled: true,
      rpcUrl,
      chainId,
      privateKey,
      multisigAddress: normalizedMultisig,
      oftAddress: normalizedOft,
      minConfirmations: baseMinConfirmations,
    };
  }

  // BSC Chain (optional)
  let bscConfig: BridgeConfig['bsc'] = null;
  const rpcUrlBsc = process.env.RPC_URL_BSC;
  const privateKeyBsc = process.env.PRIVATE_KEY_BSC || privateKey;
  const multisigAddressBsc = process.env.MULTISIG_ADDRESS_BSC;
  const oftAddressBsc = process.env.OFT_CONTRACT_ADDRESS_BSC;

  if (rpcUrlBsc && privateKeyBsc && multisigAddressBsc && oftAddressBsc) {
    const chainIdBsc = parseInt(process.env.BSC_CHAIN_ID || '56', 10);
    if (isNaN(chainIdBsc)) {
      throw new Error(`Invalid BSC_CHAIN_ID: ${process.env.BSC_CHAIN_ID}`);
    }

    if (!privateKeyBsc.startsWith('0x') || privateKeyBsc.length !== 66) {
      throw new Error('PRIVATE_KEY_BSC must be a 32-byte hex string starting with 0x');
    }

    const bscMinConfirmations = parseInt(process.env.BSC_MIN_CONFIRMATIONS || '5', 10);
    if (isNaN(bscMinConfirmations) || bscMinConfirmations < 0) {
      throw new Error(`Invalid BSC_MIN_CONFIRMATIONS: ${process.env.BSC_MIN_CONFIRMATIONS}. Must be non-negative.`);
    }

    let normalizedMultisigBsc: string;
    let normalizedOftBsc: string;

    try {
      normalizedMultisigBsc = normalizeAddress(multisigAddressBsc, 'MULTISIG_ADDRESS_BSC');
    } catch (err) {
      throw new Error(
        `Invalid MULTISIG_ADDRESS_BSC: ${multisigAddressBsc}. ${err instanceof Error ? err.message : ''}`
      );
    }

    try {
      normalizedOftBsc = normalizeAddress(oftAddressBsc, 'OFT_CONTRACT_ADDRESS_BSC');
    } catch (err) {
      throw new Error(
        `Invalid OFT_CONTRACT_ADDRESS_BSC: ${oftAddressBsc}. ${err instanceof Error ? err.message : ''}`
      );
    }

    bscConfig = {
      enabled: true,
      rpcUrl: rpcUrlBsc,
      chainId: chainIdBsc,
      privateKey: privateKeyBsc,
      multisigAddress: normalizedMultisigBsc,
      oftAddress: normalizedOftBsc,
      minConfirmations: bscMinConfirmations,
    };
  }

  // At least one chain must be configured
  if (!baseConfig && !bscConfig) {
    throw new Error('At least one EVM chain must be configured (Base or BSC). Set RPC_URL_BASE/PRIVATE_KEY/MULTISIG_ADDRESS/OFT_CONTRACT_ADDRESS or their BSC equivalents.');
  }

  // Watcher Set
  const watcherAddresses = parseWatcherSet(process.env.MULTISIG_WATCHERS);
  const watcherThreshold = parseInt(process.env.WATCHER_THRESHOLD || '3', 10);

  if (isNaN(watcherThreshold) || watcherThreshold < 1) {
    throw new Error(`Invalid WATCHER_THRESHOLD: ${process.env.WATCHER_THRESHOLD}. Must be at least 1.`);
  }

  if (watcherThreshold > watcherAddresses.length) {
    throw new Error(
      `WATCHER_THRESHOLD (${watcherThreshold}) cannot exceed number of watchers (${watcherAddresses.length})`
    );
  }

  // Worker Settings
  const pollIntervalMs = parseInt(process.env.WORKER_POLL_INTERVAL_MS || '10000', 10);
  const maxRetries = parseInt(process.env.WORKER_MAX_RETRIES || '5', 10);
  const retryBackoffMs = parseInt(process.env.WORKER_RETRY_BACKOFF_MS || '30000', 10);
  const workerEnabled = process.env.WORKER_ENABLED !== 'false';

  if (isNaN(pollIntervalMs) || pollIntervalMs < 1000) {
    throw new Error(
      `Invalid WORKER_POLL_INTERVAL_MS: ${process.env.WORKER_POLL_INTERVAL_MS}. Must be at least 1000ms.`
    );
  }

  if (isNaN(maxRetries) || maxRetries < 0) {
    throw new Error(`Invalid WORKER_MAX_RETRIES: ${process.env.WORKER_MAX_RETRIES}. Must be non-negative.`);
  }

  if (isNaN(retryBackoffMs) || retryBackoffMs < 0) {
    throw new Error(
      `Invalid WORKER_RETRY_BACKOFF_MS: ${process.env.WORKER_RETRY_BACKOFF_MS}. Must be non-negative.`
    );
  }

  // TON Burn Worker Settings
  const tonBurnerEnabled = process.env.TON_BURNER_ENABLED === 'true';
  const tonChain = (process.env.TON_CHAIN || 'mainnet') as 'mainnet' | 'testnet';
  const tonVault = process.env.TON_VAULT || '';
  const tonJettonRoot = process.env.TON_JETTON_ROOT || '';
  const tonJettonRootRaw = process.env.TON_JETTON_ROOT_RAW || '';
  const tonPublicKeyHex = process.env.TON_PUBLIC_KEY_HEX || '';
  const tonSecretKeyHex = process.env.TON_SECRET_KEY_HEX || '';
  const tonToncenterApiKey = process.env.TONCENTER_API_KEY || '';
  const tonGasBurn = parseFloat(process.env.GAS_TON_BURN || '0.2');
  const tonBurnerPollIntervalMs = parseInt(process.env.TON_BURNER_POLL_INTERVAL_MS || '10000', 10);
  const tonBurnerConfirmationCheckIntervalMs = parseInt(
    process.env.TON_BURNER_CONFIRMATION_CHECK_INTERVAL_MS || '15000',
    10
  );

  if (tonBurnerEnabled) {
    if (!tonVault) {
      throw new Error('TON_VAULT is required when TON_BURNER_ENABLED=true');
    }
    if (!tonJettonRoot) {
      throw new Error('TON_JETTON_ROOT is required when TON_BURNER_ENABLED=true');
    }
    if (!tonPublicKeyHex) {
      throw new Error('TON_PUBLIC_KEY_HEX is required when TON_BURNER_ENABLED=true');
    }
    if (!tonSecretKeyHex) {
      throw new Error('TON_SECRET_KEY_HEX is required when TON_BURNER_ENABLED=true');
    }
    if (!tonToncenterApiKey) {
      throw new Error('TONCENTER_API_KEY is required when TON_BURNER_ENABLED=true');
    }
    if (isNaN(tonGasBurn) || tonGasBurn <= 0) {
      throw new Error('GAS_TON_BURN must be a positive number');
    }
  }

  if (isNaN(tonBurnerPollIntervalMs) || tonBurnerPollIntervalMs < 1000) {
    throw new Error(
      `Invalid TON_BURNER_POLL_INTERVAL_MS: ${process.env.TON_BURNER_POLL_INTERVAL_MS}. Must be at least 1000ms.`
    );
  }

  if (isNaN(tonBurnerConfirmationCheckIntervalMs) || tonBurnerConfirmationCheckIntervalMs < 1000) {
    throw new Error(
      `Invalid TON_BURNER_CONFIRMATION_CHECK_INTERVAL_MS: ${process.env.TON_BURNER_CONFIRMATION_CHECK_INTERVAL_MS}. Must be at least 1000ms.`
    );
  }

  // TON Mint Worker Settings (EVM -> TON)
  const tonMinterEnabled = process.env.TON_MINTER_ENABLED === 'true';
  const tonMinterChain = (process.env.TON_CHAIN || 'mainnet') as 'mainnet' | 'testnet';
  const tonMinterJettonRoot = process.env.TON_JETTON_ROOT || '';
  const tonMinterMnemonic = process.env.TON_MNEMONIC || '';
  const tonMinterPublicKeyHex = process.env.TON_PUBLIC_KEY_HEX || '';
  const tonMinterSecretKeyHex = process.env.TON_SECRET_KEY_HEX || '';
  const tonMinterToncenterBase = process.env.TONCENTER_BASE || (tonMinterChain === 'testnet'
    ? 'https://testnet.toncenter.com/api/v2'
    : 'https://toncenter.com/api/v2');
  const tonMinterToncenterApiKey = process.env.TONCENTER_API_KEY || '';
  const tonMinterGasMint = parseFloat(process.env.GAS_TON_MINT || '0.25');
  const tonMinterPollIntervalMs = parseInt(process.env.TON_MINTER_POLL_INTERVAL_MS || '10000', 10);
  const tonMinterConfirmationCheckIntervalMs = parseInt(
    process.env.TON_MINTER_CONFIRMATION_CHECK_INTERVAL_MS || '15000',
    10
  );

  if (tonMinterEnabled) {
    if (!tonMinterJettonRoot) {
      throw new Error('TON_JETTON_ROOT is required when TON_MINTER_ENABLED=true');
    }
    if (!tonMinterMnemonic && (!tonMinterPublicKeyHex || !tonMinterSecretKeyHex)) {
      throw new Error('TON_MNEMONIC or (TON_PUBLIC_KEY_HEX + TON_SECRET_KEY_HEX) required when TON_MINTER_ENABLED=true');
    }
    if (!tonMinterToncenterApiKey) {
      throw new Error('TONCENTER_API_KEY is required when TON_MINTER_ENABLED=true');
    }
    if (isNaN(tonMinterGasMint) || tonMinterGasMint <= 0) {
      throw new Error('GAS_TON_MINT must be a positive number');
    }
  }

  if (isNaN(tonMinterPollIntervalMs) || tonMinterPollIntervalMs < 1000) {
    throw new Error(
      `Invalid TON_MINTER_POLL_INTERVAL_MS: ${process.env.TON_MINTER_POLL_INTERVAL_MS}. Must be at least 1000ms.`
    );
  }

  if (isNaN(tonMinterConfirmationCheckIntervalMs) || tonMinterConfirmationCheckIntervalMs < 1000) {
    throw new Error(
      `Invalid TON_MINTER_CONFIRMATION_CHECK_INTERVAL_MS: ${process.env.TON_MINTER_CONFIRMATION_CHECK_INTERVAL_MS}. Must be at least 1000ms.`
    );
  }

  // Token Configuration
  const tokenDecimals = parseInt(process.env.TOKEN_DECIMALS || '18', 10);
  if (isNaN(tokenDecimals) || tokenDecimals < 0 || tokenDecimals > 77) {
    throw new Error(
      `Invalid TOKEN_DECIMALS: ${process.env.TOKEN_DECIMALS}. Must be between 0 and 77.`
    );
  }

  // TON Multisig Contract Configuration
  const tonMultisigEnabled = process.env.TON_MULTISIG_ENABLED === 'true';
  const tonMultisigAddress = process.env.TON_MULTISIG_ADDRESS || '';
  const tonMultisigChain = (process.env.TON_MULTISIG_CHAIN || tonChain) as 'mainnet' | 'testnet';
  const tonMultisigWatchersStr = process.env.TON_MULTISIG_WATCHERS || '';
  const tonMultisigGovernanceStr = process.env.TON_MULTISIG_GOVERNANCE || '';
  const tonMultisigJettonRoot = process.env.TON_MULTISIG_JETTON_ROOT || tonJettonRoot;
  const tonMultisigMintGas = parseFloat(process.env.TON_MULTISIG_MINT_GAS || '0.26');
  const tonMultisigGovernanceGas = parseFloat(process.env.TON_MULTISIG_GOVERNANCE_GAS || '0.05');

  // Parse and normalize TON multisig watchers (strip 0x prefix if present)
  const tonMultisigWatchers = tonMultisigWatchersStr
    ? tonMultisigWatchersStr.split(',').map((s) => {
        const trimmed = s.trim();
        if (!trimmed) return '';
        try {
          return normalizeTonPublicKey(trimmed);
        } catch (err) {
          throw new Error(
            `Invalid TON_MULTISIG_WATCHERS key: ${trimmed}. ${err instanceof Error ? err.message : ''}`
          );
        }
      }).filter(Boolean)
    : [];

  // Parse and normalize TON multisig governance keys (strip 0x prefix if present)
  const tonMultisigGovernance = tonMultisigGovernanceStr
    ? tonMultisigGovernanceStr.split(',').map((s) => {
        const trimmed = s.trim();
        if (!trimmed) return '';
        try {
          return normalizeTonPublicKey(trimmed);
        } catch (err) {
          throw new Error(
            `Invalid TON_MULTISIG_GOVERNANCE key: ${trimmed}. ${err instanceof Error ? err.message : ''}`
          );
        }
      }).filter(Boolean)
    : [];

  if (tonMultisigEnabled) {
    if (!tonMultisigAddress) {
      throw new Error('TON_MULTISIG_ADDRESS is required when TON_MULTISIG_ENABLED=true');
    }
    if (tonMultisigWatchers.length !== 5) {
      throw new Error(
        `TON_MULTISIG_WATCHERS must have exactly 5 public keys (got ${tonMultisigWatchers.length})`
      );
    }
    if (tonMultisigGovernance.length !== 5) {
      throw new Error(
        `TON_MULTISIG_GOVERNANCE must have exactly 5 public keys (got ${tonMultisigGovernance.length})`
      );
    }
    if (!tonMultisigJettonRoot) {
      throw new Error('TON_MULTISIG_JETTON_ROOT is required when TON_MULTISIG_ENABLED=true');
    }
    if (isNaN(tonMultisigMintGas) || tonMultisigMintGas <= 0) {
      throw new Error('TON_MULTISIG_MINT_GAS must be a positive number');
    }
    if (isNaN(tonMultisigGovernanceGas) || tonMultisigGovernanceGas <= 0) {
      throw new Error('TON_MULTISIG_GOVERNANCE_GAS must be a positive number');
    }
  }

  // TON Multisig Submitter Worker Settings
  const tonMultisigSubmitterEnabled = process.env.TON_MULTISIG_SUBMITTER_ENABLED === 'true';
  const tonMultisigSubmitterMnemonic = process.env.TON_MULTISIG_SUBMITTER_MNEMONIC || '';
  const tonMultisigSubmitterPublicKeyHex = process.env.TON_MULTISIG_SUBMITTER_PUBLIC_KEY_HEX || '';
  const tonMultisigSubmitterSecretKeyHex = process.env.TON_MULTISIG_SUBMITTER_SECRET_KEY_HEX || '';
  const tonMultisigSubmitterToncenterBase = process.env.TON_MULTISIG_SUBMITTER_TONCENTER_BASE || tonMinterToncenterBase;
  const tonMultisigSubmitterToncenterBaseFallback = process.env.TON_MULTISIG_SUBMITTER_TONCENTER_BASE_FALLBACK || '';
  const tonMultisigSubmitterToncenterApiKey = process.env.TON_MULTISIG_SUBMITTER_TONCENTER_API_KEY || tonMinterToncenterApiKey;
  const tonMultisigSubmitterSendAmount = process.env.TON_MULTISIG_SUBMITTER_SEND_AMOUNT || '0.2';
  const tonMultisigSubmitterPollIntervalMs = parseInt(
    process.env.TON_MULTISIG_SUBMITTER_POLL_INTERVAL_MS || '10000',
    10
  );
  const tonMultisigSubmitterConfirmationCheckIntervalMs = parseInt(
    process.env.TON_MULTISIG_SUBMITTER_CONFIRMATION_CHECK_INTERVAL_MS || '15000',
    10
  );
  const tonMultisigSubmitterMaxConfirmationRetries = parseInt(
    process.env.TON_MULTISIG_SUBMITTER_MAX_CONFIRMATION_RETRIES || '10',
    10
  );
  const tonMultisigSubmitterBackoffMultiplier = parseFloat(
    process.env.TON_MULTISIG_SUBMITTER_BACKOFF_MULTIPLIER || '2.0'
  );

  if (tonMultisigSubmitterEnabled) {
    if (!tonMultisigSubmitterMnemonic && (!tonMultisigSubmitterPublicKeyHex || !tonMultisigSubmitterSecretKeyHex)) {
      throw new Error(
        'TON_MULTISIG_SUBMITTER_MNEMONIC or (TON_MULTISIG_SUBMITTER_PUBLIC_KEY_HEX + TON_MULTISIG_SUBMITTER_SECRET_KEY_HEX) required when TON_MULTISIG_SUBMITTER_ENABLED=true'
      );
    }
    if (!tonMultisigSubmitterToncenterApiKey) {
      throw new Error('TON_MULTISIG_SUBMITTER_TONCENTER_API_KEY is required when TON_MULTISIG_SUBMITTER_ENABLED=true');
    }
    if (isNaN(tonMultisigSubmitterPollIntervalMs) || tonMultisigSubmitterPollIntervalMs < 1000) {
      throw new Error(
        `Invalid TON_MULTISIG_SUBMITTER_POLL_INTERVAL_MS: ${process.env.TON_MULTISIG_SUBMITTER_POLL_INTERVAL_MS}. Must be at least 1000ms.`
      );
    }
    if (isNaN(tonMultisigSubmitterConfirmationCheckIntervalMs) || tonMultisigSubmitterConfirmationCheckIntervalMs < 1000) {
      throw new Error(
        `Invalid TON_MULTISIG_SUBMITTER_CONFIRMATION_CHECK_INTERVAL_MS: ${process.env.TON_MULTISIG_SUBMITTER_CONFIRMATION_CHECK_INTERVAL_MS}. Must be at least 1000ms.`
      );
    }
    if (isNaN(tonMultisigSubmitterMaxConfirmationRetries) || tonMultisigSubmitterMaxConfirmationRetries < 1) {
      throw new Error(
        `Invalid TON_MULTISIG_SUBMITTER_MAX_CONFIRMATION_RETRIES: ${process.env.TON_MULTISIG_SUBMITTER_MAX_CONFIRMATION_RETRIES}. Must be at least 1.`
      );
    }
    if (isNaN(tonMultisigSubmitterBackoffMultiplier) || tonMultisigSubmitterBackoffMultiplier < 1) {
      throw new Error(
        `Invalid TON_MULTISIG_SUBMITTER_BACKOFF_MULTIPLIER: ${process.env.TON_MULTISIG_SUBMITTER_BACKOFF_MULTIPLIER}. Must be at least 1.`
      );
    }
  }

  // Logging
  const logLevel = process.env.LOG_LEVEL || 'info';
  const logFormat = (process.env.LOG_FORMAT || 'json') as 'json' | 'text';

  if (!['error', 'warn', 'info', 'debug', 'verbose'].includes(logLevel)) {
    throw new Error(
      `Invalid LOG_LEVEL: ${logLevel}. Must be one of: error, warn, info, debug, verbose.`
    );
  }

  if (!['json', 'text'].includes(logFormat)) {
    throw new Error(`Invalid LOG_FORMAT: ${logFormat}. Must be either 'json' or 'text'.`);
  }

  // Security
  const apiKey = (process.env.BRIDGE_API_KEY || '').trim() || null;

  return {
    database: {
      path: databasePath,
      verbose: databaseVerbose,
    },
    network: {
      port,
      host,
    },
    base: baseConfig,
    bsc: bscConfig,
    watchers: {
      addresses: watcherAddresses,
      threshold: watcherThreshold,
    },
    worker: {
      pollIntervalMs,
      maxRetries,
      retryBackoffMs,
      enabled: workerEnabled,
    },
    tonBurner: {
      enabled: tonBurnerEnabled,
      chain: tonChain,
      vault: tonVault,
      jettonRoot: tonJettonRoot,
      jettonRootRaw: tonJettonRootRaw,
      publicKeyHex: tonPublicKeyHex,
      secretKeyHex: tonSecretKeyHex,
      toncenterApiKey: tonToncenterApiKey,
      gasTonBurn: tonGasBurn,
      pollIntervalMs: tonBurnerPollIntervalMs,
      confirmationCheckIntervalMs: tonBurnerConfirmationCheckIntervalMs,
    },
    tonMinter: {
      enabled: tonMinterEnabled,
      chain: tonMinterChain,
      jettonRoot: tonMinterJettonRoot,
      mnemonic: tonMinterMnemonic,
      publicKeyHex: tonMinterPublicKeyHex,
      secretKeyHex: tonMinterSecretKeyHex,
      toncenterBase: tonMinterToncenterBase,
      toncenterApiKey: tonMinterToncenterApiKey,
      gasTonMint: tonMinterGasMint,
      pollIntervalMs: tonMinterPollIntervalMs,
      confirmationCheckIntervalMs: tonMinterConfirmationCheckIntervalMs,
    },
    tonMultisig: {
      enabled: tonMultisigEnabled,
      address: tonMultisigAddress,
      chain: tonMultisigChain,
      watchers: tonMultisigWatchers,
      governance: tonMultisigGovernance,
      jettonRoot: tonMultisigJettonRoot,
      mintGas: tonMultisigMintGas,
      governanceGas: tonMultisigGovernanceGas,
    },
    tonMultisigSubmitter: {
      enabled: tonMultisigSubmitterEnabled,
      walletMnemonic: tonMultisigSubmitterMnemonic,
      walletPublicKeyHex: tonMultisigSubmitterPublicKeyHex,
      walletSecretKeyHex: tonMultisigSubmitterSecretKeyHex,
      toncenterBase: tonMultisigSubmitterToncenterBase,
      toncenterBaseFallback: tonMultisigSubmitterToncenterBaseFallback,
      toncenterApiKey: tonMultisigSubmitterToncenterApiKey,
      sendAmount: tonMultisigSubmitterSendAmount,
      pollIntervalMs: tonMultisigSubmitterPollIntervalMs,
      confirmationCheckIntervalMs: tonMultisigSubmitterConfirmationCheckIntervalMs,
      maxConfirmationRetries: tonMultisigSubmitterMaxConfirmationRetries,
      backoffMultiplier: tonMultisigSubmitterBackoffMultiplier,
    },
    token: {
      decimals: tokenDecimals,
    },
    logging: {
      level: logLevel,
      format: logFormat,
    },
    security: {
      apiKey,
    },
  };
}

/**
 * Validates configuration without throwing errors
 *
 * @returns Validation result with errors
 */
export function validateConfig(): { valid: boolean; errors: string[] } {
  const errors: string[] = [];

  try {
    loadConfig();
    return { valid: true, errors: [] };
  } catch (err) {
    errors.push(err instanceof Error ? err.message : String(err));
    return { valid: false, errors };
  }
}

/**
 * Prints configuration summary (without sensitive data)
 *
 * @param config - Configuration object
 */
export function printConfigSummary(config: BridgeConfig): void {
  console.log('Bridge Aggregator Configuration:');
  console.log('================================');
  console.log(`Database Path:         ${config.database.path}`);
  console.log(`Network:               ${config.network.host}:${config.network.port}`);
  if (config.base) {
    console.log(`Base Chain ID:         ${config.base.chainId}`);
    console.log(`Base RPC:              ${config.base.rpcUrl}`);
    console.log(`Base Multisig:         ${config.base.multisigAddress}`);
    console.log(`Base OFT:              ${config.base.oftAddress}`);
    console.log(`Base Min Confirmations: ${config.base.minConfirmations}`);
  } else {
    console.log(`Base Chain:            (not configured)`);
  }
  if (config.bsc) {
    console.log(`BSC Chain ID:          ${config.bsc.chainId}`);
    console.log(`BSC RPC:               ${config.bsc.rpcUrl}`);
    console.log(`BSC Multisig:          ${config.bsc.multisigAddress}`);
    console.log(`BSC OFT:               ${config.bsc.oftAddress}`);
    console.log(`BSC Min Confirmations: ${config.bsc.minConfirmations}`);
  } else {
    console.log(`BSC Chain:             (not configured)`);
  }
  console.log(`Watcher Count:         ${config.watchers.addresses.length}`);
  console.log(`Watcher Threshold:     ${config.watchers.threshold}`);
  console.log(`Token Decimals:        ${config.token.decimals}`);
  console.log(`Worker Enabled:        ${config.worker.enabled}`);
  console.log(`Worker Poll Interval:  ${config.worker.pollIntervalMs}ms`);
  console.log(`Worker Max Retries:    ${config.worker.maxRetries}`);
  console.log(`Worker Retry Backoff:  ${config.worker.retryBackoffMs}ms`);
  console.log(`TON Burner Enabled:    ${config.tonBurner.enabled}`);
  if (config.tonBurner.enabled) {
    console.log(`TON Chain:             ${config.tonBurner.chain}`);
    console.log(`TON Vault:             ${config.tonBurner.vault}`);
    console.log(`TON Burner Poll:       ${config.tonBurner.pollIntervalMs}ms`);
  }
  console.log(`TON Minter Enabled:    ${config.tonMinter.enabled} (LEGACY)`);
  if (config.tonMinter.enabled) {
    console.log(`TON Minter Chain:      ${config.tonMinter.chain}`);
    console.log(`TON Jetton Root:       ${config.tonMinter.jettonRoot}`);
    console.log(`TON Minter Poll:       ${config.tonMinter.pollIntervalMs}ms`);
  }
  console.log(`TON Multisig Enabled:  ${config.tonMultisig.enabled}`);
  if (config.tonMultisig.enabled) {
    console.log(`TON Multisig Address:  ${config.tonMultisig.address}`);
    console.log(`TON Multisig Chain:    ${config.tonMultisig.chain}`);
    console.log(`TON Multisig Watchers: ${config.tonMultisig.watchers.length}`);
    console.log(`TON Multisig Gov:      ${config.tonMultisig.governance.length}`);
  }
  console.log(`TON Multisig Submitter: ${config.tonMultisigSubmitter.enabled}`);
  if (config.tonMultisigSubmitter.enabled) {
    console.log(`TON Submitter Poll:    ${config.tonMultisigSubmitter.pollIntervalMs}ms`);
    console.log(`TON Submitter Confirm: ${config.tonMultisigSubmitter.confirmationCheckIntervalMs}ms`);
  }
  console.log(`Log Level:             ${config.logging.level}`);
  console.log(`Log Format:            ${config.logging.format}`);
  console.log(`API Key Auth:          ${config.security.apiKey ? 'enabled' : 'disabled'}`);
  console.log('================================\n');
}
