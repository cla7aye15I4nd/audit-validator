/**
 * @file index.ts
 * @notice TON Bridge Multisig - Main Export Module
 *
 * This module exports all utilities for interacting with the
 * TON bridge multisig contract.
 */

// Payload generation and hashing
export {
  TonMintPayload,
  GovernanceAction,
  GovernanceActionType,
  UpdateWatchersPayload,
  UpdateGovernancePayload,
  SetTokenStatusPayload,
  TransferTokenOwnerPayload,
  MapTokenPayload,
  SetMintNoncePayload,
  TonSignature,
  hashMintPayload,
  hashGovernanceAction,
  buildMintPayloadCell,
  buildUpdateWatchersPayload,
  buildUpdateGovernancePayload,
  buildSetTokenStatusPayload,
  buildTransferTokenOwnerPayload,
  buildMapTokenPayload,
  buildSetMintNoncePayload,
  buildGovernanceActionCell,
  buildSignaturesCell,
  buildExecuteMintMessage,
  buildExecuteGovernanceMessage,
  hexToBuffer,
  bufferToHex,
} from './payload';

// Signature generation and verification
export {
  Ed25519Keypair,
  signPayload,
  aggregateSignatures,
  validateThreshold,
  sortSignatures,
  prepareMintSignatures,
  prepareGovernanceSignatures,
  keypairFromSecretKeyHex,
  verifySignature,
  signatureToHex,
  signatureFromHex,
} from './signatures';

// Contract interaction
export {
  BridgeMultisig,
  BridgeMultisigConfig,
  DeployParams,
  buildInitialStorage,
  createBridgeMultisig,
  estimateMintGas,
  estimateGovernanceGas,
  formatPublicKey,
  parsePublicKey,
} from './contract';
