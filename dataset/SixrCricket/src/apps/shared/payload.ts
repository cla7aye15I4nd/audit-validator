/**
 * @file payload.ts
 * @notice Shared payload helpers for canonical payload construction and hashing
 *
 * This module extracts the core logic from prepare-ton-to-base.ts to ensure
 * consistent payload hashing across manual scripts, watchers, and the bridge aggregator.
 *
 * All functions match the BridgeMultisig EIP-712 implementation exactly.
 */

import { BigNumber, ethers } from 'ethers';
import { MintPayload, MintPayloadForChain, TonMintPayload, EIP712Domain } from './types';
import { Address } from '@ton/core';

/**
 * EIP-712 constants matching BridgeMultisig.sol
 */
export const DOMAIN_NAME = 'BridgeMultisig';
export const DOMAIN_VERSION = '1';

/**
 * EIP-712 type definitions matching BridgeMultisig.sol
 */
export const MINT_PAYLOAD_TYPES = {
  MintPayload: [
    { name: 'originChainId', type: 'uint256' },
    { name: 'token', type: 'address' },
    { name: 'recipient', type: 'address' },
    { name: 'amount', type: 'uint256' },
    { name: 'nonce', type: 'uint64' },
  ],
};

/**
 * EIP-712 type definitions for TON mint payload (EVM -> TON)
 */
export const TON_MINT_PAYLOAD_TYPES = {
  TonMintPayload: [
    { name: 'originChainId', type: 'uint256' },
    { name: 'token', type: 'address' },
    { name: 'tonRecipientHash', type: 'bytes32' },
    { name: 'amount', type: 'uint256' },
    { name: 'nonce', type: 'uint64' },
    { name: 'burnTxHash', type: 'bytes32' },
  ],
};

/**
 * TON blockchain uses 9 decimals (configurable via env)
 */
export const RAW_DECIMALS = parseInt(process.env.TON_RAW_DECIMALS || '9', 10);

/**
 * Validates and normalizes an Ethereum address using ethers checksum
 *
 * @param address - Raw address string
 * @param label - Description for error messages
 * @returns Checksummed address
 * @throws Error if address is invalid
 */
export function normalizeAddress(address: string, label: string): string {
  try {
    return ethers.utils.getAddress(address);
  } catch (err) {
    throw new Error(
      `Invalid ${label} address: ${address}. ${err instanceof Error ? err.message : ''}`
    );
  }
}

/**
 * Validates that a numeric string is non-negative and represents a valid integer
 *
 * @param value - Numeric string
 * @param label - Description for error messages
 * @returns BigNumber representation
 * @throws Error if value is invalid or negative
 */
export function validateNonNegativeInteger(value: string, label: string): BigNumber {
  if (!/^\d+$/.test(value)) {
    throw new Error(`${label} must be a non-negative integer (got: ${value})`);
  }

  const bn = BigNumber.from(value);
  if (bn.lt(0)) {
    throw new Error(`${label} must be non-negative (got: ${value})`);
  }

  return bn;
}

/**
 * Scales a raw TON amount (9 decimals) to the destination token's decimal precision
 *
 * Scaling rules:
 * - If tokenDecimals > TON_RAW_DECIMALS: multiply by 10^(tokenDecimals - TON_RAW_DECIMALS)
 * - If tokenDecimals == TON_RAW_DECIMALS: no scaling needed
 * - If tokenDecimals < TON_RAW_DECIMALS: divide by 10^(TON_RAW_DECIMALS - tokenDecimals)
 *   with divisibility check to prevent precision loss
 *
 * @param amountRaw - Raw amount as string (TON 9-decimal units)
 * @param decimals - Target token decimals
 * @returns Scaled amount as BigNumber
 * @throws Error if amount is invalid or down-scaling would lose precision
 */
export function scaleAmount(amountRaw: string, decimals: number): BigNumber {
  if (!/^\d+$/.test(amountRaw)) {
    throw new Error(`amountRaw9 must be a numeric string (got: ${amountRaw})`);
  }

  const raw = BigNumber.from(amountRaw);

  // No scaling needed if decimals match
  if (decimals === RAW_DECIMALS) {
    return raw;
  }

  // Scale up: multiply by 10^difference
  if (decimals > RAW_DECIMALS) {
    const scaleFactor = BigNumber.from(10).pow(decimals - RAW_DECIMALS);
    return raw.mul(scaleFactor);
  }

  // Scale down: divide by 10^difference, but ensure no precision loss
  const scaleFactor = BigNumber.from(10).pow(RAW_DECIMALS - decimals);
  if (!raw.mod(scaleFactor).isZero()) {
    throw new Error(
      `Precision loss error: amountRaw9=${amountRaw} is not divisible by 10^(${RAW_DECIMALS} - ${decimals}). ` +
        `Cannot scale down from ${RAW_DECIMALS} to ${decimals} decimals without truncation. ` +
        `Please provide an amount that is a multiple of ${scaleFactor.toString()}.`
    );
  }

  return raw.div(scaleFactor);
}

/**
 * Builds a canonical mint payload from input parameters
 *
 * @param originChainId - Origin chain ID
 * @param token - Token address (will be checksummed)
 * @param recipient - Recipient address (will be checksummed)
 * @param amountRaw9 - Raw amount in 9 decimals
 * @param nonce - Nonce (string | number | BigNumber) - accepts BigInt-generated strings for precision
 * @param tokenDecimals - Token decimals on destination chain
 * @returns Canonical mint payload with string values
 */
export function buildPayload(
  originChainId: number,
  token: string,
  recipient: string,
  amountRaw9: string,
  nonce: string | number | BigNumber,
  tokenDecimals: number
): MintPayload {
  // Normalize addresses
  const normalizedToken = normalizeAddress(token, 'token');
  const normalizedRecipient = normalizeAddress(recipient, 'recipient');

  // Scale amount
  const scaledAmount = scaleAmount(amountRaw9, tokenDecimals);

  // Validate nonce fits in uint64
  // Accept string, number, or BigNumber to support BigInt-generated nonces
  const MAX_UINT64 = BigNumber.from('0xFFFFFFFFFFFFFFFF');
  const nonceBN = BigNumber.from(nonce);
  if (nonceBN.gt(MAX_UINT64)) {
    throw new Error(`Nonce ${nonce} exceeds maximum uint64 value (${MAX_UINT64.toString()})`);
  }

  return {
    originChainId: originChainId.toString(),
    token: normalizedToken,
    recipient: normalizedRecipient,
    amount: scaledAmount.toString(),
    nonce: nonceBN.toString(),
  };
}

/**
 * Converts a string-based payload to chain-compatible format with BigNumber
 *
 * @param payload - Mint payload with string values
 * @returns Mint payload with BigNumber for amount
 */
export function toChainPayload(payload: MintPayload): MintPayloadForChain {
  return {
    originChainId: parseInt(payload.originChainId, 10),
    token: payload.token,
    recipient: payload.recipient,
    amount: BigNumber.from(payload.amount),
    nonce: payload.nonce,
  };
}

/**
 * Computes the EIP-712 struct hash for a mint payload
 * This matches BridgeMultisig.hashMintPayload exactly
 *
 * @param payload - Mint payload
 * @returns Struct hash (not yet domain-separated)
 */
export function hashMintPayload(payload: MintPayload): string {
  const MINT_TYPEHASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes(
      'MintPayload(uint256 originChainId,address token,address recipient,uint256 amount,uint64 nonce)'
    )
  );

  return ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ['bytes32', 'uint256', 'address', 'address', 'uint256', 'uint64'],
      [
        MINT_TYPEHASH,
        payload.originChainId,
        payload.token,
        payload.recipient,
        payload.amount,
        payload.nonce,
      ]
    )
  );
}

/**
 * Computes the EIP-712 domain separator
 *
 * @param domain - EIP-712 domain
 * @returns Domain separator hash
 */
export function hashDomain(domain: EIP712Domain): string {
  const DOMAIN_TYPEHASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
    )
  );

  return ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
      [
        DOMAIN_TYPEHASH,
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes(domain.name)),
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes(domain.version)),
        domain.chainId,
        domain.verifyingContract,
      ]
    )
  );
}

/**
 * Computes the complete EIP-712 digest for a mint payload
 * This matches BridgeMultisig.mintDigest exactly
 *
 * @param payload - Mint payload
 * @param domain - EIP-712 domain
 * @returns EIP-712 digest ready for signing
 */
export function computeDigest(payload: MintPayload, domain: EIP712Domain): string {
  const structHash = hashMintPayload(payload);
  const domainSeparator = hashDomain(domain);

  return ethers.utils.keccak256(
    ethers.utils.solidityPack(['string', 'bytes32', 'bytes32'], ['\x19\x01', domainSeparator, structHash])
  );
}

/**
 * Builds the EIP-712 domain for a given chain and multisig address
 *
 * @param chainId - Chain ID
 * @param multisigAddress - BridgeMultisig contract address
 * @returns EIP-712 domain
 */
export function buildDomain(chainId: number, multisigAddress: string): EIP712Domain {
  return {
    name: DOMAIN_NAME,
    version: DOMAIN_VERSION,
    chainId,
    verifyingContract: normalizeAddress(multisigAddress, 'multisig'),
  };
}

/**
 * Helper to sign a payload using ethers _signTypedData
 *
 * @param wallet - Ethers wallet
 * @param payload - Mint payload
 * @param domain - EIP-712 domain
 * @returns Signature string
 */
export async function signPayload(
  wallet: ethers.Wallet,
  payload: MintPayload,
  domain: EIP712Domain
): Promise<string> {
  return wallet._signTypedData(domain, MINT_PAYLOAD_TYPES, payload);
}

/* ============================================================================
 * TON Mint Payload Helpers (EVM -> TON)
 * ========================================================================== */

/**
 * Validates a friendly TON address format
 *
 * @param address - TON address string
 * @returns True if valid
 */
export function isValidTonAddress(address: string): boolean {
  // TON friendly addresses: EQ... or UQ... (48 base64 chars)
  return /^[EU]Q[0-9A-Za-z\-_]{46}$/.test(address);
}

/**
 * Normalizes a TON address to canonical bounceable form
 *
 * @param address - Raw TON address string
 * @returns Canonical bounceable address
 * @throws Error if address is invalid
 */
export function normalizeTonAddress(address: string): string {
  try {
    const parsed = Address.parse(address);
    // Return as bounceable, testOnly=false
    return parsed.toString({ bounceable: true, testOnly: false });
  } catch (err) {
    throw new Error(
      `Invalid TON address: ${address}. ${err instanceof Error ? err.message : ''}`
    );
  }
}

/**
 * Encodes a TON address for EIP-712 payload by hashing it with keccak256
 *
 * @param tonAddress - Canonical TON address
 * @returns 0x-prefixed 32-byte hash
 */
export function encodeTonAddressForPayload(tonAddress: string): string {
  const normalized = normalizeTonAddress(tonAddress);
  // Hash the canonical string representation with keccak256
  return ethers.utils.keccak256(ethers.utils.toUtf8Bytes(normalized));
}

/**
 * Computes nonce for EVM -> TON payload: (originChainId << 48) | (blockNumber << 16) | logIndex
 *
 * This encoding ensures:
 * - Global uniqueness across multiple EVM chains (originChainId prevents collisions)
 * - Monotonically increasing per chain (blockNumber + logIndex ensure ordering within each chain)
 * - Fits in uint64 (chainId < 2^16, blockNumber < 2^32, logIndex < 2^16)
 *
 * Formula breakdown:
 * - Bits 48-63: originChainId (16 bits, supports chain IDs up to 65535)
 * - Bits 16-47: blockNumber (32 bits, supports ~4.3 billion blocks)
 * - Bits 0-15:  logIndex (16 bits, supports 65535 events per block)
 *
 * @param originChainId - EVM chain ID (e.g., 8453 for Base, 56 for BSC)
 * @param blockNumber - EVM block number
 * @param logIndex - Event log index within the block
 * @returns Nonce as string
 * @throws Error if values are out of range
 */
export function computeTonMintNonce(originChainId: number, blockNumber: number, logIndex: number): string {
  if (originChainId < 0 || !Number.isInteger(originChainId)) {
    throw new Error(`Invalid originChainId: ${originChainId}. Must be non-negative integer.`);
  }
  if (blockNumber < 0 || !Number.isInteger(blockNumber)) {
    throw new Error(`Invalid blockNumber: ${blockNumber}. Must be non-negative integer.`);
  }
  if (logIndex < 0 || !Number.isInteger(logIndex)) {
    throw new Error(`Invalid logIndex: ${logIndex}. Must be non-negative integer.`);
  }
  if (originChainId >= 2 ** 16) {
    throw new Error(`originChainId ${originChainId} too large (must be < 2^16 = 65536)`);
  }
  if (blockNumber >= 2 ** 32) {
    throw new Error(`blockNumber ${blockNumber} too large (must be < 2^32)`);
  }
  if (logIndex >= 2 ** 16) {
    throw new Error(`logIndex ${logIndex} too large (must be < 2^16)`);
  }

  // Use BigInt for precise bit shifting
  // Format: (chainId << 48) | (blockNumber << 16) | logIndex
  const nonce = (BigInt(originChainId) << 48n) | (BigInt(blockNumber) << 16n) | BigInt(logIndex);

  // Verify it fits in uint64
  const MAX_UINT64 = 2n ** 64n - 1n;
  if (nonce > MAX_UINT64) {
    throw new Error(`Computed nonce ${nonce} exceeds uint64 maximum`);
  }

  return nonce.toString();
}

/**
 * Builds a canonical TON mint payload from input parameters
 *
 * @param originChainId - EVM chain ID (e.g., 8453 for Base)
 * @param token - Token address on origin EVM chain
 * @param tonRecipient - TON recipient address (will be normalized)
 * @param amountRaw9 - Amount in 9-decimal raw jetton units
 * @param blockNumber - EVM burn block number
 * @param logIndex - EVM burn log index
 * @param burnTxHash - EVM burn transaction hash
 * @returns Canonical TON mint payload with string values
 */
export function buildTonMintPayload(
  originChainId: number,
  token: string,
  tonRecipient: string,
  amountRaw9: string,
  blockNumber: number,
  logIndex: number,
  burnTxHash: string
): TonMintPayload {
  // Normalize token address
  const normalizedToken = normalizeAddress(token, 'token');

  // Normalize TON recipient and compute hash
  const normalizedTonRecipient = normalizeTonAddress(tonRecipient);
  const tonRecipientHash = encodeTonAddressForPayload(normalizedTonRecipient);

  // Validate amount
  validateNonNegativeInteger(amountRaw9, 'amountRaw9');

  // Compute nonce
  const nonce = computeTonMintNonce(originChainId, blockNumber, logIndex);

  // Validate burn tx hash format
  if (!/^0x[a-fA-F0-9]{64}$/.test(burnTxHash)) {
    throw new Error(`Invalid burnTxHash format: ${burnTxHash}. Must be 0x-prefixed 32 bytes.`);
  }

  return {
    originChainId: originChainId.toString(),
    token: normalizedToken,
    tonRecipientHash,
    amount: amountRaw9,
    nonce,
    burnTxHash: burnTxHash.toLowerCase(),
  };
}

/**
 * Computes the EIP-712 struct hash for a TON mint payload
 *
 * @param payload - TON mint payload
 * @returns Struct hash (not yet domain-separated)
 */
export function hashTonMintPayload(payload: TonMintPayload): string {
  const TON_MINT_TYPEHASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes(
      'TonMintPayload(uint256 originChainId,address token,bytes32 tonRecipientHash,uint256 amount,uint64 nonce,bytes32 burnTxHash)'
    )
  );

  return ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ['bytes32', 'uint256', 'address', 'bytes32', 'uint256', 'uint64', 'bytes32'],
      [
        TON_MINT_TYPEHASH,
        payload.originChainId,
        payload.token,
        payload.tonRecipientHash,
        payload.amount,
        payload.nonce,
        payload.burnTxHash,
      ]
    )
  );
}

/**
 * Computes the complete EIP-712 digest for a TON mint payload
 *
 * @param payload - TON mint payload
 * @param domain - EIP-712 domain
 * @returns EIP-712 digest ready for signing
 */
export function computeTonMintDigest(payload: TonMintPayload, domain: EIP712Domain): string {
  const structHash = hashTonMintPayload(payload);
  const domainSeparator = hashDomain(domain);

  return ethers.utils.keccak256(
    ethers.utils.solidityPack(['string', 'bytes32', 'bytes32'], ['\x19\x01', domainSeparator, structHash])
  );
}

/**
 * Helper to sign a TON mint payload using ethers _signTypedData
 *
 * @param wallet - Ethers wallet
 * @param payload - TON mint payload
 * @param domain - EIP-712 domain
 * @returns Signature string
 */
export async function signTonMintPayload(
  wallet: ethers.Wallet,
  payload: TonMintPayload,
  domain: EIP712Domain
): Promise<string> {
  return wallet._signTypedData(domain, TON_MINT_PAYLOAD_TYPES, payload);
}
