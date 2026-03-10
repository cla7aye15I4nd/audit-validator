/**
 * @file signatures.ts
 * @notice TON Bridge Multisig - Signature Generation and Verification
 *
 * This module provides utilities for Ed25519 signature generation
 * and aggregation for the TON bridge multisig contract.
 */

import { sign, sha256_sync } from '@ton/crypto';
import { TonSignature } from './payload';
import * as nacl from 'tweetnacl';

/**
 * Keypair for Ed25519 signing
 */
export interface Ed25519Keypair {
  publicKey: Buffer;        // 32-byte public key
  secretKey: Buffer;        // 64-byte secret key (32-byte seed + 32-byte public key)
}

/**
 * Sign a payload hash with an Ed25519 private key
 *
 * NOTE: Initial hypothesis about CHKSIGNU double-hashing was INCORRECT.
 * The documentation's mention of "double hashing" refers to check_data_signature(),
 * not check_signature(). When using check_signature() with a pre-computed hash,
 * we sign the hash directly WITHOUT additional hashing.
 *
 * @param payloadHash - 32-byte hash of the payload to sign
 * @param keypair - Ed25519 keypair
 * @returns Signature object with public key and signature
 */
export function signPayload(payloadHash: Buffer, keypair: Ed25519Keypair): TonSignature {
  if (payloadHash.length !== 32) {
    throw new Error('Payload hash must be exactly 32 bytes');
  }

  if (keypair.publicKey.length !== 32) {
    throw new Error('Public key must be exactly 32 bytes');
  }

  if (keypair.secretKey.length !== 64) {
    throw new Error('Secret key must be exactly 64 bytes');
  }

  // Sign the hash directly using TON's Ed25519 implementation
  const signature = sign(payloadHash, keypair.secretKey);

  if (signature.length !== 64) {
    throw new Error('Generated signature is not 64 bytes');
  }

  return {
    publicKey: keypair.publicKey,
    signature,
  };
}

/**
 * Aggregate multiple signatures for a multisig operation
 * Validates that signatures are unique (no duplicate signers)
 *
 * @param signatures - Array of signatures to aggregate
 * @returns Array of unique signatures
 * @throws Error if duplicate signers are detected
 */
export function aggregateSignatures(signatures: TonSignature[]): TonSignature[] {
  const uniqueSignatures: TonSignature[] = [];
  const seenPublicKeys = new Set<string>();

  for (const sig of signatures) {
    const pubKeyHex = sig.publicKey.toString('hex');

    if (seenPublicKeys.has(pubKeyHex)) {
      throw new Error(`Duplicate signer detected: ${pubKeyHex}`);
    }

    seenPublicKeys.add(pubKeyHex);
    uniqueSignatures.push(sig);
  }

  return uniqueSignatures;
}

/**
 * Validate that signature count meets threshold
 *
 * @param signatures - Array of signatures
 * @param threshold - Required number of signatures
 * @throws Error if threshold not met
 */
export function validateThreshold(signatures: TonSignature[], threshold: number): void {
  if (signatures.length < threshold) {
    throw new Error(
      `Insufficient signatures: got ${signatures.length}, need ${threshold}`
    );
  }
}

/**
 * Sort signatures by public key (for deterministic ordering)
 * This ensures consistent signature ordering across different watchers/governance members
 *
 * @param signatures - Array of signatures
 * @returns Sorted array of signatures
 */
export function sortSignatures(signatures: TonSignature[]): TonSignature[] {
  return [...signatures].sort((a, b) => {
    return Buffer.compare(a.publicKey as any, b.publicKey as any);
  });
}

/**
 * Prepare signatures for mint operation (3-of-5 threshold)
 * - Validates uniqueness
 * - Validates threshold
 * - Sorts for deterministic ordering
 *
 * @param signatures - Array of watcher signatures
 * @returns Prepared signatures ready for contract call
 */
export function prepareMintSignatures(signatures: TonSignature[]): TonSignature[] {
  const unique = aggregateSignatures(signatures);
  validateThreshold(unique, 3); // 3-of-5 watcher threshold
  return sortSignatures(unique);
}

/**
 * Prepare signatures for governance operation (4-of-5 threshold)
 * - Validates uniqueness
 * - Validates threshold
 * - Sorts for deterministic ordering
 *
 * @param signatures - Array of governance signatures
 * @returns Prepared signatures ready for contract call
 */
export function prepareGovernanceSignatures(signatures: TonSignature[]): TonSignature[] {
  const unique = aggregateSignatures(signatures);
  validateThreshold(unique, 4); // 4-of-5 governance threshold
  return sortSignatures(unique);
}

/**
 * Convert hex string to Ed25519 keypair
 * Assumes the hex string is the 64-byte secret key (seed + public key)
 *
 * @param secretKeyHex - Hex string of the secret key (0x-prefixed or not)
 * @returns Ed25519 keypair
 */
export function keypairFromSecretKeyHex(secretKeyHex: string): Ed25519Keypair {
  const cleaned = secretKeyHex.startsWith('0x') ? secretKeyHex.slice(2) : secretKeyHex;

  if (cleaned.length !== 128) {
    throw new Error('Secret key hex must be 128 characters (64 bytes)');
  }

  const secretKey = Buffer.from(cleaned, 'hex');

  // Extract public key from last 32 bytes of secret key
  const publicKey = secretKey.slice(32, 64);

  return {
    publicKey,
    secretKey,
  };
}

/**
 * Verify an Ed25519 signature
 * Uses TweetNaCl for Ed25519 signature verification
 *
 * @param hash - 32-byte hash that was signed
 * @param signature - 64-byte signature
 * @param publicKey - 32-byte public key
 * @returns true if signature is valid, false otherwise
 */
export function verifySignature(
  hash: Buffer,
  signature: Buffer,
  publicKey: Buffer
): boolean {
  if (hash.length !== 32 || signature.length !== 64 || publicKey.length !== 32) {
    throw new Error('Invalid input lengths for signature verification');
  }

  try {
    // Use TweetNaCl's Ed25519 signature verification
    // This matches the verification logic used by TON's check_signature()
    // Convert Buffers to Uint8Array for TweetNaCl compatibility
    return nacl.sign.detached.verify(
      new Uint8Array(hash),
      new Uint8Array(signature),
      new Uint8Array(publicKey)
    );
  } catch (e) {
    return false;
  }
}

/**
 * Export signature to hex format for storage/transmission
 *
 * @param signature - Signature object
 * @returns Object with hex-encoded public key and signature
 */
export function signatureToHex(signature: TonSignature): {
  publicKey: string;
  signature: string;
} {
  return {
    publicKey: '0x' + signature.publicKey.toString('hex'),
    signature: '0x' + signature.signature.toString('hex'),
  };
}

/**
 * Import signature from hex format
 *
 * @param hexSig - Hex-encoded signature
 * @returns Signature object
 */
export function signatureFromHex(hexSig: {
  publicKey: string;
  signature: string;
}): TonSignature {
  return {
    publicKey: Buffer.from(
      hexSig.publicKey.startsWith('0x') ? hexSig.publicKey.slice(2) : hexSig.publicKey,
      'hex'
    ),
    signature: Buffer.from(
      hexSig.signature.startsWith('0x') ? hexSig.signature.slice(2) : hexSig.signature,
      'hex'
    ),
  };
}
