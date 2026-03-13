/**
 * @file ton.ts
 * @notice Shared TON blockchain utilities for burning jettons
 *
 * This module provides utilities for interacting with TON blockchain,
 * specifically for fetching jetton wallet addresses and burning jettons.
 * Extracted from watcher code to be shared by Bridge burn worker.
 */

import { Address, toNano } from '@ton/core';

/* eslint-disable @typescript-eslint/no-var-requires */
const TonWebLib = require('tonweb');
const TonWeb = TonWebLib.default || TonWebLib;

const fetch = (global as any).fetch ?? require('node-fetch');

/**
 * TON configuration for burn operations
 */
export interface TonBurnConfig {
  chain: 'mainnet' | 'testnet';
  vault: string;
  jettonRoot: string;
  jettonRootRaw?: string;
  publicKeyHex: string;
  secretKeyHex: string;
  toncenterApiKey: string;
  gasTonBurn: number;
}

/**
 * Result of a burn operation
 */
export interface BurnResult {
  txHash: string;
  explorerUrl: string;
}

/**
 * Converts address to raw format
 */
function toRaw(addr: string): string {
  return Address.parse(addr).toRawString();
}

/**
 * Sleep utility
 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Gets jetton wallet address cache per configuration
 */
const jettonWalletCache = new Map<string, Address>();

/**
 * Fetches the vault's jetton wallet address
 *
 * @param config - TON burn configuration
 * @returns Jetton wallet address
 * @throws Error if address cannot be resolved
 */
export async function fetchVaultJettonWalletAddr(config: TonBurnConfig): Promise<Address> {
  const cacheKey = `${config.vault}:${config.jettonRoot}`;
  const cached = jettonWalletCache.get(cacheKey);

  if (cached) {
    return cached;
  }

  const owner = config.vault;
  const jetton = config.jettonRootRaw || config.jettonRoot;
  if (!owner || !jetton) {
    throw new Error('fetchVaultJettonWalletAddr: missing vault or jetton');
  }

  const TON_BASE =
    config.chain === 'testnet' ? 'https://testnet.tonapi.io' : 'https://tonapi.io';

  const url = `${TON_BASE}/v2/accounts/${owner}/jettons`;

  const JETTON_RAW_EXPECTED = (() => {
    if (config.jettonRootRaw) return config.jettonRootRaw;
    try {
      return toRaw(config.jettonRoot);
    } catch {
      return config.jettonRoot;
    }
  })();

  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const response = await fetch(url, { headers: { Accept: 'application/json' } });

      if (response.status === 429) {
        const waitMs = 1000 * Math.pow(2, attempt);
        console.log(
          `[FETCH_JETTON_WALLET] Rate limited (429), waiting ${waitMs}ms before retry ${attempt + 1}/5`
        );
        await sleep(waitMs);
        continue;
      }

      if (!response.ok) {
        throw new Error(`TonAPI jettons error: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      const balances = data?.balances ?? [];

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

      const walletAddress = Address.parse(addr);
      jettonWalletCache.set(cacheKey, walletAddress);
      console.log('[FETCH_JETTON_WALLET] Successfully fetched and cached jetton wallet address');

      return walletAddress;
    } catch (e: any) {
      if (attempt === 4 || (e.message && !e.message.includes('429'))) {
        throw e;
      }
      console.log(`[FETCH_JETTON_WALLET] Attempt ${attempt + 1}/5 failed: ${e.message}`);
    }
  }

  throw new Error('Failed to fetch vault jetton wallet after 5 attempts');
}

/**
 * Burns jettons on TON by sending burn transaction to vault's jetton wallet
 *
 * @param config - TON burn configuration
 * @param amountRaw9 - Amount to burn in raw 9-decimal format
 * @returns Burn result with transaction hash and explorer URL
 * @throws Error if burn fails
 */
export async function burnOnTon(config: TonBurnConfig, amountRaw9: string): Promise<BurnResult> {
  try {
    const endpoint =
      config.chain === 'testnet'
        ? 'https://testnet.toncenter.com/api/v2/jsonRPC'
        : 'https://toncenter.com/api/v2/jsonRPC';

    const tonweb = new TonWeb(new TonWeb.HttpProvider(endpoint, { apiKey: config.toncenterApiKey }));

    const WalletClass = tonweb.wallet.all.v4R2;
    const wallet = new WalletClass(tonweb.provider, {
      publicKey: TonWeb.utils.hexToBytes(config.publicKeyHex),
      wc: 0,
    });

    const derivedAddr = await wallet.getAddress();
    const derivedStr = derivedAddr.toString(true, true, false);
    const vaultAddr = new TonWeb.utils.Address(config.vault);
    const vaultStr = vaultAddr.toString(true, true, false);

    console.log('[BURN] Derived wallet from keypair:', derivedStr);
    console.log('[BURN] Expected vault:', vaultStr);

    if (derivedStr !== vaultStr) {
      throw new Error(
        `WALLET MISMATCH! Derived: ${derivedStr}, Expected: ${vaultStr}. Check TON_PUBLIC_KEY_HEX and TON_SECRET_KEY_HEX in config`
      );
    }

    console.log('[BURN] Fetching vault jetton wallet...');
    const vaultJettonWallet = await fetchVaultJettonWalletAddr(config);
    const vaultJettonWalletStr = vaultJettonWallet.toString({
      bounceable: true,
      testOnly: config.chain === 'testnet',
    });
    console.log('[BURN] Jetton wallet:', vaultJettonWalletStr);

    const amount = BigInt(amountRaw9);
    const fwdAmount = toNano(String(config.gasTonBurn));

    console.log('[BURN] Building burn body...');
    const burnBody = new TonWeb.boc.Cell();
    burnBody.bits.writeUint(0x595f07bc, 32); // burn opcode
    burnBody.bits.writeUint(0, 64); // query_id
    burnBody.bits.writeCoins(new TonWeb.utils.BN(amountRaw9));
    burnBody.bits.writeAddress(new TonWeb.utils.Address(config.vault));

    console.log('[BURN] Getting seqno...');
    const seqno = (await wallet.methods.seqno().call()) || 0;
    console.log('[BURN] Seqno:', seqno);

    console.log('[BURN] Creating transfer...');
    const transfer = wallet.methods.transfer({
      secretKey: TonWeb.utils.hexToBytes(config.secretKeyHex),
      toAddress: vaultJettonWalletStr,
      amount: fwdAmount,
      seqno: seqno,
      payload: burnBody,
      sendMode: 3,
    });

    console.log('[BURN] Sending transaction...');
    const result = await transfer.send();
    console.log('[BURN] Result:', result);

    const TON_EXPLORER =
      config.chain === 'testnet' ? 'https://testnet.tonviewer.com' : 'https://tonviewer.com';

    const explorerUrl = `${TON_EXPLORER}/${vaultJettonWalletStr}`;
    const txHash = vaultJettonWalletStr; // TON doesn't return tx hash directly from send

    return {
      txHash,
      explorerUrl,
    };
  } catch (e: any) {
    console.error('[BURN] Error details:', {
      message: e?.message,
      stack: e?.stack,
      name: e?.name,
      raw: e,
    });
    throw new Error(`Burn failed: ${e?.message || e?.name || String(e)}`);
  }
}

/**
 * Validates TON configuration
 *
 * @param config - TON burn configuration
 * @throws Error if configuration is invalid
 */
export function validateTonConfig(config: TonBurnConfig): void {
  const missing: string[] = [];

  if (!config.vault) missing.push('vault');
  if (!config.jettonRoot) missing.push('jettonRoot');
  if (!config.publicKeyHex) missing.push('publicKeyHex');
  if (!config.secretKeyHex) missing.push('secretKeyHex');
  if (!config.toncenterApiKey) missing.push('toncenterApiKey');

  if (missing.length > 0) {
    throw new Error(`Missing required TON configuration: ${missing.join(', ')}`);
  }

  if (config.gasTonBurn <= 0) {
    throw new Error('gasTonBurn must be greater than 0');
  }
}

/**
 * Normalizes a TON public key by stripping the optional 0x prefix
 * and converting to lowercase for consistent comparison
 *
 * @param key - Public key hex string (with or without 0x prefix)
 * @returns Normalized key without 0x prefix, lowercase
 * @throws Error if key is not valid hex or wrong length
 */
export function normalizeTonPublicKey(key: string): string {
  if (!key || typeof key !== 'string') {
    throw new Error('TON public key must be a non-empty string');
  }

  // Strip 0x prefix if present
  const cleaned = key.toLowerCase().startsWith('0x') ? key.slice(2) : key;

  // Validate hex format
  if (!/^[0-9a-f]{64}$/i.test(cleaned)) {
    throw new Error(
      `Invalid TON public key format: expected 64 hex characters (got ${cleaned.length})`
    );
  }

  return cleaned.toLowerCase();
}

/**
 * Result of TON address normalization
 */
export interface NormalizedTonAddress {
  /** Raw address as provided */
  raw: string;
  /** Canonical bounceable address (EQ...) */
  canonical: string;
}

/**
 * Normalizes a TON address to canonical bounceable form (EQ...)
 * Accepts both user-friendly (UQ/EQ) and raw formats
 *
 * @param address - TON address in any valid format (EQ, UQ, raw, etc.)
 * @param testOnly - Whether this is a testnet address (default: false)
 * @returns Object containing both raw and canonical addresses
 * @throws Error if address is invalid
 *
 * @example
 * ```typescript
 * const result = normalizeTonAddress("UQAMjP8...");
 * // result.raw = "UQAMjP8..."
 * // result.canonical = "EQAMjP8..."
 * ```
 */
export function normalizeTonAddress(
  address: string,
  testOnly: boolean = false
): NormalizedTonAddress {
  if (!address || typeof address !== 'string') {
    throw new Error('TON address must be a non-empty string');
  }

  try {
    // Parse the address using @ton/core Address class
    // This validates the address and handles all friendly/raw formats
    const parsed = Address.parse(address);

    // Convert to canonical bounceable form
    const canonical = parsed.toString({
      bounceable: true,
      testOnly,
    });

    return {
      raw: address,
      canonical,
    };
  } catch (error: any) {
    throw new Error(`Invalid TON address "${address}": ${error?.message || String(error)}`);
  }
}

/**
 * Compares two TON addresses for equality by normalizing both to canonical form
 *
 * @param addr1 - First TON address
 * @param addr2 - Second TON address
 * @param testOnly - Whether these are testnet addresses (default: false)
 * @returns True if addresses are equivalent (same canonical form)
 *
 * @example
 * ```typescript
 * const isEqual = tonAddressEquals("UQAMjP8...", "EQAMjP8...");
 * // Returns true if they represent the same address
 * ```
 */
export function tonAddressEquals(
  addr1: string,
  addr2: string,
  testOnly: boolean = false
): boolean {
  try {
    const norm1 = normalizeTonAddress(addr1, testOnly);
    const norm2 = normalizeTonAddress(addr2, testOnly);
    return norm1.canonical === norm2.canonical;
  } catch {
    return false;
  }
}
