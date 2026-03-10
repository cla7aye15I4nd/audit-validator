/**
 * @file signature.ts
 * @notice Signature validation and recovery for watcher signatures
 *
 * This module provides utilities for validating EIP-712 signatures from watchers
 * and ensuring they match the configured watcher set.
 */

import { ethers } from 'ethers';
import { MintPayload, EIP712Domain, WatcherSignature } from './types';
import { computeDigest, normalizeAddress as normalizeAddr } from './payload';

// Re-export normalizeAddress for use in other modules
export { normalizeAddress } from './payload';

/**
 * Recovers the signer address from an EIP-712 signature
 *
 * @param digest - EIP-712 digest
 * @param signature - Signature bytes
 * @returns Recovered signer address (checksummed)
 * @throws Error if signature is invalid
 */
export function recoverSigner(digest: string, signature: string): string {
  try {
    const recovered = ethers.utils.recoverAddress(digest, signature);
    return ethers.utils.getAddress(recovered);
  } catch (err) {
    throw new Error(
      `Failed to recover signer from signature: ${err instanceof Error ? err.message : String(err)}`
    );
  }
}

/**
 * Verifies that a signature is valid for a given payload and signer
 *
 * @param payload - Mint payload
 * @param domain - EIP-712 domain
 * @param signature - Signature bytes
 * @param expectedSigner - Expected signer address
 * @returns True if signature is valid
 * @throws Error if signature is invalid or doesn't match expected signer
 */
export function verifySignature(
  payload: MintPayload,
  domain: EIP712Domain,
  signature: string,
  expectedSigner: string
): boolean {
  const digest = computeDigest(payload, domain);
  const recovered = recoverSigner(digest, signature);
  const normalized = normalizeAddr(expectedSigner, 'expectedSigner');

  if (recovered !== normalized) {
    throw new Error(
      `Signature verification failed: expected ${normalized}, recovered ${recovered}`
    );
  }

  return true;
}

/**
 * Validates that a signature comes from a known watcher
 *
 * @param payload - Mint payload
 * @param domain - EIP-712 domain
 * @param signature - Signature bytes
 * @param watcherSet - Array of known watcher addresses
 * @returns Watcher address that signed
 * @throws Error if signature is invalid or from unknown watcher
 */
export function validateWatcherSignature(
  payload: MintPayload,
  domain: EIP712Domain,
  signature: string,
  watcherSet: string[]
): string {
  const digest = computeDigest(payload, domain);
  const signer = recoverSigner(digest, signature);

  // Normalize watcher set
  const normalizedWatchers = watcherSet.map((w) => normalizeAddr(w, 'watcher'));

  // Check if signer is in watcher set
  if (!normalizedWatchers.includes(signer)) {
    throw new Error(
      `Unknown watcher: ${signer} is not in the configured watcher set [${normalizedWatchers.join(', ')}]`
    );
  }

  return signer;
}

/**
 * Validates multiple signatures and ensures no duplicates
 *
 * @param payload - Mint payload
 * @param domain - EIP-712 domain
 * @param signatures - Array of signatures
 * @param watcherSet - Array of known watcher addresses
 * @returns Array of validated watcher signatures
 * @throws Error if any signature is invalid, from unknown watcher, or duplicate
 */
export function validateSignatures(
  payload: MintPayload,
  domain: EIP712Domain,
  signatures: WatcherSignature[],
  watcherSet: string[]
): WatcherSignature[] {
  const seen = new Set<string>();
  const validated: WatcherSignature[] = [];

  for (const sig of signatures) {
    // Validate signature
    const signer = validateWatcherSignature(payload, domain, sig.signature, watcherSet);

    // Check for duplicates
    if (seen.has(signer)) {
      throw new Error(`Duplicate signature from watcher: ${signer}`);
    }

    seen.add(signer);

    // Verify claimed watcher matches recovered signer
    const normalizedClaimed = normalizeAddr(sig.watcher, 'watcher');
    if (normalizedClaimed !== signer) {
      throw new Error(
        `Watcher mismatch: claimed ${normalizedClaimed}, recovered ${signer}`
      );
    }

    validated.push({
      watcher: signer,
      signature: sig.signature,
    });
  }

  return validated;
}

/**
 * Checks if a payload has reached quorum (3-of-5 signatures)
 *
 * @param signatureCount - Number of unique signatures
 * @param threshold - Required threshold (default: 3)
 * @returns True if quorum is met
 */
export function hasQuorum(signatureCount: number, threshold: number = 3): boolean {
  return signatureCount >= threshold;
}

/**
 * Parses watcher addresses from environment variable
 *
 * Supports formats:
 * - Comma-separated list: "0x123...,0x456...,0x789..."
 *
 * @param envValue - Environment variable value
 * @returns Array of normalized watcher addresses
 * @throws Error if format is invalid or addresses are malformed
 */
export function parseWatcherSet(envValue: string | undefined): string[] {
  if (!envValue) {
    throw new Error('Watcher set not configured: MULTISIG_WATCHERS environment variable is required');
  }

  const addresses = envValue
    .split(',')
    .map((addr) => addr.trim())
    .filter(Boolean);

  if (addresses.length === 0) {
    throw new Error('Watcher set is empty: MULTISIG_WATCHERS must contain at least one address');
  }

  // Normalize and validate all addresses
  const normalized = addresses.map((addr, idx) => {
    try {
      return normalizeAddr(addr, `watcher[${idx}]`);
    } catch (err) {
      throw new Error(
        `Invalid watcher address in MULTISIG_WATCHERS at index ${idx}: ${addr}. ` +
          `${err instanceof Error ? err.message : ''}`
      );
    }
  });

  // Check for duplicates
  const unique = new Set(normalized);
  if (unique.size !== normalized.length) {
    throw new Error('Watcher set contains duplicate addresses');
  }

  return normalized;
}

/**
 * Validates that a watcher address is in the configured set
 *
 * @param watcher - Watcher address to check
 * @param watcherSet - Array of known watcher addresses
 * @returns True if watcher is valid
 * @throws Error if watcher is not in set
 */
export function validateWatcherAddress(watcher: string, watcherSet: string[]): boolean {
  const normalized = normalizeAddr(watcher, 'watcher');
  const normalizedSet = watcherSet.map((w) => normalizeAddr(w, 'watcher'));

  if (!normalizedSet.includes(normalized)) {
    throw new Error(
      `Unknown watcher address: ${normalized} is not in the configured watcher set`
    );
  }

  return true;
}
