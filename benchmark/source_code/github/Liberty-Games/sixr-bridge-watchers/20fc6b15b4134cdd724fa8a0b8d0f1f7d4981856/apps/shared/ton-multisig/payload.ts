/**
 * @file payload.ts
 * @notice TON Bridge Multisig - Payload Generation and Hashing
 *
 * This module provides utilities for creating and hashing payloads
 * that match the on-chain TL-B schemas in the FunC contract.
 */

import { Address, beginCell, Cell } from '@ton/core';
import { sha256_sync } from '@ton/crypto';

/**
 * Mint payload structure (matches TL-B schema)
 */
export interface TonMintPayload {
  originChainId: number;     // uint32: EVM chain ID
  token: string;             // bits256: EVM token address (0x-prefixed)
  tonRecipient: string;      // MsgAddressInt: TON recipient address
  amount: bigint;            // uint128: Amount in 9-decimal raw units
  nonce: bigint;             // uint64: Replay protection nonce
}

/**
 * Governance action types (must match contract constants)
 */
export enum GovernanceActionType {
  UPDATE_WATCHERS = 0x01,
  UPDATE_GOVERNANCE = 0x02,
  SET_TOKEN_STATUS = 0x03,
  TRANSFER_TOKEN_OWNER = 0x04,
  MAP_TOKEN = 0x06,
  SET_MINT_NONCE = 0x07,
}

/**
 * Governance action structure
 */
export interface GovernanceAction {
  actionType: GovernanceActionType;
  nonce: bigint;            // uint64: Governance nonce
  epoch: bigint;            // uint64: Governance epoch (for replay protection after rotation)
  payload: Cell;            // Action-specific payload
}

/**
 * Update watchers payload
 */
export interface UpdateWatchersPayload {
  watcher1: Buffer;         // 32-byte Ed25519 public key
  watcher2: Buffer;         // 32-byte Ed25519 public key
  watcher3: Buffer;         // 32-byte Ed25519 public key
}

/**
 * Update governance payload
 */
export interface UpdateGovernancePayload {
  gov1: Buffer;             // 32-byte Ed25519 public key
  gov2: Buffer;             // 32-byte Ed25519 public key
  gov3: Buffer;             // 32-byte Ed25519 public key
  gov4: Buffer;             // 32-byte Ed25519 public key
  gov5: Buffer;             // 32-byte Ed25519 public key
}

/**
 * Set token status payload
 */
export interface SetTokenStatusPayload {
  jettonRoot: string;       // TON address
  status: boolean;          // true = allowed, false = not allowed
}

/**
 * Transfer token ownership payload
 */
export interface TransferTokenOwnerPayload {
  jettonRoot: string;       // TON address
  newOwner: string;         // TON address
}

/**
 * Map token payload (EVM token -> TON jetton root)
 */
export interface MapTokenPayload {
  evmToken: string;         // EVM token address (0x-prefixed)
  tonJettonRoot: string;    // TON jetton root address
}

/**
 * Set mint nonce payload
 */
export interface SetMintNoncePayload {
  newMintNonce: bigint;     // uint64: New mint nonce value
}

/**
 * Signature structure for contract calls
 */
export interface TonSignature {
  publicKey: Buffer;        // 32-byte Ed25519 public key
  signature: Buffer;        // 64-byte Ed25519 signature
}

/**
 * Convert EVM address (0x-prefixed 20 bytes) to 256-bit value
 * Pads with zeros on the left to reach 32 bytes
 */
function evmAddressTo256Bits(address: string): bigint {
  // Remove 0x prefix if present
  const cleanAddr = address.toLowerCase().startsWith('0x') ? address.slice(2) : address;

  if (cleanAddr.length !== 40) {
    throw new Error(`Invalid EVM address length: ${address}`);
  }

  // Pad to 64 hex chars (32 bytes = 256 bits)
  const padded = cleanAddr.padStart(64, '0');
  return BigInt('0x' + padded);
}

/**
 * Build and hash a mint payload according to TL-B schema
 * mint_payload#4d494e54 origin_chain_id:uint32 token:bits256 ton_recipient:MsgAddressInt amount:uint128 nonce:uint64
 *
 * @param payload - Mint payload data
 * @returns Hash of the payload as a Buffer (32 bytes)
 */
export function hashMintPayload(payload: TonMintPayload): Buffer {
  const recipientAddress = Address.parse(payload.tonRecipient);
  const tokenBits = evmAddressTo256Bits(payload.token);

  const cell = beginCell()
    .storeUint(0x4d494e54, 32)              // mint_payload tag
    .storeUint(payload.originChainId, 32)
    .storeUint(tokenBits, 256)
    .storeAddress(recipientAddress)
    .storeUint(payload.amount, 128)
    .storeUint(payload.nonce, 64)
    .endCell();

  // FunC uses cell_hash() which is single hash, not double
  return cell.hash() as Buffer;
}

/**
 * Build mint payload cell for contract call
 * Does NOT include signatures - those are added by buildExecuteMintMessage
 */
export function buildMintPayloadCell(payload: TonMintPayload): Cell {
  const recipientAddress = Address.parse(payload.tonRecipient);
  const tokenBits = evmAddressTo256Bits(payload.token);

  return beginCell()
    .storeUint(0x4d494e54, 32)              // OP_EXECUTE_MINT
    .storeUint(payload.originChainId, 32)
    .storeUint(tokenBits, 256)
    .storeAddress(recipientAddress)
    .storeUint(payload.amount, 128)
    .storeUint(payload.nonce, 64)
    .endCell();
}

/**
 * Build UPDATE_WATCHERS governance payload
 * update_watchers_payload#57415443 watcher_1:bits256 watcher_2:bits256 watcher_3:bits256
 */
export function buildUpdateWatchersPayload(payload: UpdateWatchersPayload): Cell {
  if (payload.watcher1.length !== 32 || payload.watcher2.length !== 32 || payload.watcher3.length !== 32) {
    throw new Error('Watcher public keys must be exactly 32 bytes');
  }

  return beginCell()
    .storeUint(0x57415443, 32)              // update_watchers_payload tag
    .storeBuffer(payload.watcher1)
    .storeBuffer(payload.watcher2)
    .storeBuffer(payload.watcher3)
    .endCell();
}

/**
 * Build UPDATE_GOVERNANCE governance payload
 * update_governance_payload#474f5653 gov_1:bits256 ... gov_5:bits256
 */
export function buildUpdateGovernancePayload(payload: UpdateGovernancePayload): Cell {
  const keys = [payload.gov1, payload.gov2, payload.gov3, payload.gov4, payload.gov5];

  for (const key of keys) {
    if (key.length !== 32) {
      throw new Error('Governance public keys must be exactly 32 bytes');
    }
  }

  return beginCell()
    .storeUint(0x474f5653, 32)              // update_governance_payload tag
    .storeBuffer(payload.gov1)
    .storeBuffer(payload.gov2)
    .storeBuffer(payload.gov3)
    .storeBuffer(payload.gov4)
    .storeBuffer(payload.gov5)
    .endCell();
}

/**
 * Build SET_TOKEN_STATUS governance payload
 * set_token_status_payload#544f4b53 jetton_root:MsgAddressInt status:uint1
 */
export function buildSetTokenStatusPayload(payload: SetTokenStatusPayload): Cell {
  const jettonAddress = Address.parse(payload.jettonRoot);

  return beginCell()
    .storeUint(0x544f4b53, 32)              // set_token_status_payload tag
    .storeAddress(jettonAddress)
    .storeUint(payload.status ? 1 : 0, 1)
    .endCell();
}

/**
 * Build TRANSFER_TOKEN_OWNER governance payload
 * transfer_token_owner_payload#5452414e jetton_root:MsgAddressInt new_owner:MsgAddressInt
 */
export function buildTransferTokenOwnerPayload(payload: TransferTokenOwnerPayload): Cell {
  const jettonAddress = Address.parse(payload.jettonRoot);
  const newOwnerAddress = Address.parse(payload.newOwner);

  return beginCell()
    .storeUint(0x5452414e, 32)              // transfer_token_owner_payload tag
    .storeAddress(jettonAddress)
    .storeAddress(newOwnerAddress)
    .endCell();
}

/**
 * Build MAP_TOKEN governance payload
 * map_token_payload#4d415054 evm_token:bits256 ton_jetton_root:MsgAddressInt
 */
export function buildMapTokenPayload(payload: MapTokenPayload): Cell {
  const evmTokenBits = evmAddressTo256Bits(payload.evmToken);
  const tonJettonRoot = Address.parse(payload.tonJettonRoot);

  return beginCell()
    .storeUint(0x4d415054, 32)              // map_token_payload tag ("MAPT")
    .storeUint(evmTokenBits, 256)
    .storeAddress(tonJettonRoot)
    .endCell();
}

/**
 * Build set_mint_nonce payload for governance action
 * set_mint_nonce_payload#534d4e43 new_mint_nonce:uint64
 *
 * @param payload - Set mint nonce payload data
 * @returns Payload cell
 */
export function buildSetMintNoncePayload(payload: SetMintNoncePayload): Cell {
  return beginCell()
    .storeUint(0x534d4e43, 32)              // set_mint_nonce_payload tag ("SMNC")
    .storeUint(payload.newMintNonce, 64)
    .endCell();
}

/**
 * Hash a governance action according to TL-B schema
 * governance_action#474f5645 action_type:uint32 nonce:uint64 epoch:uint64 payload:^Cell
 *
 * @param action - Governance action data
 * @returns Hash of the action as a Buffer (32 bytes)
 */
export function hashGovernanceAction(action: GovernanceAction): Buffer {
  const cell = beginCell()
    .storeUint(0x474f5645, 32)              // governance_action tag
    .storeUint(action.actionType, 32)
    .storeUint(action.nonce, 64)
    .storeUint(action.epoch, 64)
    .storeRef(action.payload)
    .endCell();

  // FunC uses cell_hash() which is single hash, not double
  return cell.hash() as Buffer;
}

/**
 * Build governance action cell for contract call
 */
export function buildGovernanceActionCell(action: GovernanceAction): Cell {
  return beginCell()
    .storeUint(0x474f5645, 32)              // OP_EXECUTE_GOVERNANCE
    .storeUint(action.actionType, 32)
    .storeUint(action.nonce, 64)
    .storeUint(action.epoch, 64)
    .storeRef(action.payload)
    .endCell();
}

/**
 * Build signatures cell for contract call
 * Each signature is: (pubkey:bits256, signature_hi:bits256, signature_lo:bits256)
 *
 * For multiple signatures, uses a reference chain to avoid cell overflow:
 * - Each signature consumes 768 bits (3 × 256)
 * - TON cells have a 1023-bit limit, so only 1 signature fits per cell
 * - Additional signatures are stored in referenced cells
 *
 * Structure:
 *   Cell { data: [sig1], ref: Cell { data: [sig2], ref: Cell { data: [sig3] } } }
 *
 * @param signatures - Array of signatures with public keys
 * @returns Cell containing all signatures in a reference chain
 */
export function buildSignaturesCell(signatures: TonSignature[]): Cell {
  if (signatures.length === 0) {
    throw new Error('At least one signature is required');
  }

  // Validate all signatures first
  for (const sig of signatures) {
    if (sig.publicKey.length !== 32) {
      throw new Error('Public key must be 32 bytes');
    }
    if (sig.signature.length !== 64) {
      throw new Error('Signature must be 64 bytes');
    }
  }

  // Build from last signature to first (reverse order for chaining)
  let currentCell: Cell | null = null;

  for (let i = signatures.length - 1; i >= 0; i--) {
    const sig = signatures[i];
    const builder = beginCell();

    // Store signature data as uint256 (NOT Buffer) to match FunC load_uint(256)
    const pubkeyUint = BigInt('0x' + sig.publicKey.toString('hex'));
    const sigHiUint = BigInt('0x' + sig.signature.slice(0, 32).toString('hex'));
    const sigLoUint = BigInt('0x' + sig.signature.slice(32, 64).toString('hex'));

    builder.storeUint(pubkeyUint, 256);      // pubkey: uint256
    builder.storeUint(sigHiUint, 256);       // signature_hi: uint256
    builder.storeUint(sigLoUint, 256);       // signature_lo: uint256

    // If there's a next cell in the chain, add it as a reference
    if (currentCell !== null) {
      builder.storeRef(currentCell);
    }

    currentCell = builder.endCell();
  }

  return currentCell!;
}

/**
 * Build complete execute_mint message body
 * OP_EXECUTE_MINT origin_chain_id:uint32 token:bits256 ton_recipient:MsgAddressInt amount:uint128 nonce:uint64 signatures:^Cell
 *
 * @param payload - Mint payload
 * @param signatures - Array of watcher signatures
 * @returns Complete message body cell
 */
export function buildExecuteMintMessage(
  payload: TonMintPayload,
  signatures: TonSignature[]
): Cell {
  const recipientAddress = Address.parse(payload.tonRecipient);
  const tokenBits = evmAddressTo256Bits(payload.token);
  const signaturesCell = buildSignaturesCell(signatures);

  return beginCell()
    .storeUint(0x4d494e54, 32)              // OP_EXECUTE_MINT
    .storeUint(payload.originChainId, 32)
    .storeUint(tokenBits, 256)
    .storeAddress(recipientAddress)
    .storeUint(payload.amount, 128)
    .storeUint(payload.nonce, 64)
    .storeRef(signaturesCell)
    .endCell();
}

/**
 * Build complete execute_governance message body
 * OP_EXECUTE_GOVERNANCE action_type:uint32 nonce:uint64 epoch:uint64 payload:^Cell signatures:^Cell
 *
 * @param action - Governance action
 * @param signatures - Array of governance signatures
 * @returns Complete message body cell
 */
export function buildExecuteGovernanceMessage(
  action: GovernanceAction,
  signatures: TonSignature[]
): Cell {
  const signaturesCell = buildSignaturesCell(signatures);

  return beginCell()
    .storeUint(0x474f5645, 32)              // OP_EXECUTE_GOVERNANCE
    .storeUint(action.actionType, 32)
    .storeUint(action.nonce, 64)
    .storeUint(action.epoch, 64)
    .storeRef(action.payload)
    .storeRef(signaturesCell)
    .endCell();
}

/**
 * Helper to convert hex string to Buffer
 */
export function hexToBuffer(hex: string): Buffer {
  const cleaned = hex.startsWith('0x') ? hex.slice(2) : hex;
  return Buffer.from(cleaned, 'hex');
}

/**
 * Helper to convert Buffer to hex string
 */
export function bufferToHex(buffer: Buffer): string {
  return '0x' + buffer.toString('hex');
}
