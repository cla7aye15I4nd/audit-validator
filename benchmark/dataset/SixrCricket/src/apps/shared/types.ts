/**
 * @file types.ts
 * @notice Shared TypeScript types for the Bridge Aggregator system
 */

import { BigNumber } from 'ethers';

/**
 * Bridge direction for cross-chain transfers
 */
export type BridgeDirection = 'TON_TO_EVM' | 'EVM_TO_TON';

/**
 * Payload status lifecycle with TON burn flow (TON -> EVM)
 * and TON mint flow (EVM -> TON)
 *
 * TON -> EVM flow:
 * - pending: awaiting sufficient signatures
 * - ready: quorum met, awaiting burn
 * - burn_pending: burn worker picked up, about to burn
 * - burn_submitted: burn transaction sent to TON
 * - burn_confirmed: burn confirmed on TON, ready for EVM submission
 * - submitted: EVM transaction sent, awaiting confirmation
 * - finalized: transaction confirmed on-chain
 * - failed: burn, submission, or confirmation failed
 *
 * EVM -> TON flow:
 * - pending: awaiting sufficient signatures
 * - ready: quorum met, awaiting TON mint
 * - ton_mint_pending: mint worker picked up, about to mint
 * - ton_mint_submitted: mint transaction sent to TON
 * - ton_mint_confirmed: mint confirmed on TON
 * - finalized: mint finalized
 * - failed: validation or mint failed
 */
export type PayloadStatus =
  | 'pending'
  | 'ready'
  | 'burn_pending'
  | 'burn_submitted'
  | 'burn_confirmed'
  | 'ton_mint_pending'
  | 'ton_mint_submitted'
  | 'ton_mint_confirmed'
  | 'submitted'
  | 'finalized'
  | 'failed';

/**
 * Canonical mint payload matching BridgeMultisig.MintPayload
 * All numeric values are strings to avoid precision loss
 * Used for TON -> EVM transfers
 */
export interface MintPayload {
  originChainId: string;
  token: string;
  recipient: string;
  amount: string;
  nonce: string;
}

/**
 * TON mint payload for EVM -> TON transfers
 * Includes hashed TON recipient for EIP-712 signature determinism
 */
export interface TonMintPayload {
  originChainId: string;      // EVM chain ID (e.g., '8453' for Base)
  token: string;               // MOFT contract address on origin EVM chain
  tonRecipientHash: string;    // keccak256 of canonical TON address (0x-prefixed 32 bytes)
  amount: string;              // Jetton amount in 9-decimal raw units
  nonce: string;               // uint64: (blockNumber << 16) | logIndex
  burnTxHash: string;          // EVM burn transaction hash (32 bytes)
}

/**
 * Mint payload with BigNumber types for contract calls
 */
export interface MintPayloadForChain {
  originChainId: number;
  token: string;
  recipient: string;
  amount: BigNumber;
  nonce: string;
}

/**
 * Watcher signature record
 */
export interface WatcherSignature {
  watcher: string;
  signature: string;
}

/**
 * EIP-712 domain for BridgeMultisig
 */
export interface EIP712Domain {
  name: string;
  version: string;
  chainId: number;
  verifyingContract: string;
}

/**
 * Burn status for tracking TON burn progress
 */
export type BurnStatus = 'pending' | 'submitted' | 'confirmed' | 'failed';

/**
 * Database row for payloads table
 */
export interface PayloadRow {
  hash: string;
  origin_chain_id: number;
  token: string;
  recipient: string;
  amount: string;
  amount_raw9: string | null;
  nonce: bigint;
  ton_tx_id: string;
  status: PayloadStatus;
  created_at: number;
  updated_at: number;
  submitted_tx: string | null;
  error: string | null;
  // Bridge direction
  direction: BridgeDirection;
  // TON burn fields (for TON -> EVM)
  burn_tx_hash: string | null;
  burn_lt: bigint | null;
  burn_status: BurnStatus | null;
  burn_timestamp: number | null;
  // EVM burn fields (for EVM -> TON)
  burn_chain_id: number | null;
  burn_block_number: number | null;
  burn_redeem_log_index: number | null;
  burn_transfer_log_index: number | null;
  burn_from_address: string | null;
  burn_confirmations: number | null;
  // TON recipient fields (for EVM -> TON)
  ton_recipient: string | null;
  ton_recipient_raw: string | null;
  ton_recipient_hash: string | null;
  // TON mint tracking (for EVM -> TON)
  ton_mint_tx_hash: string | null;
  ton_mint_lt: bigint | null;
  ton_mint_status: string | null;
  ton_mint_error: string | null;
  ton_mint_timestamp: number | null;
  ton_mint_attempts: bigint | null;
  ton_mint_next_retry: number | null;
  // Fee tracking (for TON -> EVM)
  fee_amount: string | null;
}

/**
 * Input type for creating/updating payloads
 * ton_mint_attempts and ton_mint_next_retry are optional and will default to 0 and null
 */
export type PayloadInput = Omit<PayloadRow, 'created_at' | 'updated_at' | 'ton_mint_attempts' | 'ton_mint_next_retry'> & {
  ton_mint_attempts?: bigint | null;
  ton_mint_next_retry?: number | null;
};

/**
 * Database row for payload_signatures table
 */
export interface SignatureRow {
  hash: string;
  watcher: string;
  signature: string;
  ton_public_key: string | null;
  ton_signature: string | null;
  received_at: number;
}

/**
 * Complete payload with signatures for API responses
 * BigInt fields are serialized as strings for JSON compatibility
 */
export interface PayloadWithSignatures {
  hash: string;
  originChainId: number;
  token: string;
  recipient: string;
  amount: string;
  amountRaw9: string | null;
  nonce: string;
  tonTxId: string;
  status: PayloadStatus;
  createdAt: number;
  updatedAt: number;
  submittedTx: string | null;
  error: string | null;
  // Bridge direction
  direction: BridgeDirection;
  // TON burn fields (for TON -> EVM)
  burnTxHash: string | null;
  burnLt: string | null;
  burnStatus: BurnStatus | null;
  burnTimestamp: number | null;
  // EVM burn fields (for EVM -> TON)
  burnChainId: number | null;
  burnBlockNumber: number | null;
  burnRedeemLogIndex: number | null;
  burnTransferLogIndex: number | null;
  burnFromAddress: string | null;
  burnConfirmations: number | null;
  // TON recipient fields (for EVM -> TON)
  tonRecipient: string | null;
  tonRecipientRaw: string | null;
  tonRecipientHash: string | null;
  // TON mint tracking (for EVM -> TON)
  tonMintTxHash: string | null;
  tonMintLt: string | null;
  tonMintStatus: string | null;
  tonMintError: string | null;
  tonMintTimestamp: number | null;
  tonMintAttempts: string | null;
  tonMintNextRetry: number | null;
  // Fee tracking (for TON -> EVM)
  feeAmount: string | null;
  signatures: WatcherSignature[];
}

/**
 * Input for POST /payloads endpoint (TON -> EVM)
 */
export interface PayloadSubmissionInput {
  originChainId: number;
  token: string;
  recipient: string;
  amountRaw9: string;
  nonce: string;
  watcher: string;
  signature: string;
  tonTxId: string;
  feeAmount?: string; // Optional: fee collected by vault contract (1%)
}

/**
 * Input for POST /payloads endpoint (EVM -> TON)
 */
export interface TonMintPayloadSubmissionInput {
  direction: 'EVM_TO_TON';
  originChainId: number;
  token: string;
  tonRecipient: string;
  tonRecipientRaw?: string;
  tonRecipientHash: string;
  amountRaw9: string;
  amountRaw18: string;
  nonce: string;
  watcher: string;
  signature: string;
  // Burn proof data
  burnTxHash: string;
  burnBlockNumber: number;
  burnRedeemLogIndex: number;
  burnTransferLogIndex?: number;
  // TON multisig fields
  tonWatcherIndex: number;
  tonPublicKey: string;
  tonSignature: string;
}

/**
 * Health check response
 */
export interface HealthResponse {
  status: 'healthy' | 'degraded' | 'unhealthy';
  timestamp: number;
  counts: {
    pending: number;
    ready: number;
    burn_pending: number;
    burn_submitted: number;
    burn_confirmed: number;
    ton_mint_pending: number;
    ton_mint_submitted: number;
    ton_mint_confirmed: number;
    submitted: number;
    finalized: number;
    failed: number;
  };
  oldestPendingAge: number | null;
  tonMultisig: {
    readyCount: number;
    pendingCount: number;
    submittedCount: number;
    confirmedCount: number;
    failedCount: number;
  };
}

/**
 * EIP-712 typed data structure
 */
export interface TypedData {
  domain: EIP712Domain;
  types: {
    MintPayload: Array<{ name: string; type: string }>;
  };
  message: MintPayload;
}
