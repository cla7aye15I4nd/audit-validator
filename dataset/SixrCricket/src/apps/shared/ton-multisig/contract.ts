/**
 * @file contract.ts
 * @notice TON Bridge Multisig - Contract Interaction Utilities
 *
 * This module provides high-level functions for interacting with
 * the deployed TON bridge multisig contract.
 */

import { Address, Cell, Contract, ContractProvider, Sender, beginCell, toNano, Dictionary } from '@ton/core';
import {
  TonMintPayload,
  GovernanceAction,
  TonSignature,
  buildExecuteMintMessage,
  buildExecuteGovernanceMessage,
  hashMintPayload,
  hashGovernanceAction,
} from './payload';

/**
 * Configuration for the bridge multisig contract
 */
export interface BridgeMultisigConfig {
  contractAddress: string;  // TON address of the deployed contract
  chain: 'mainnet' | 'testnet';
}

/**
 * TON Bridge Multisig contract wrapper
 */
export class BridgeMultisig implements Contract {
  readonly address: Address;
  readonly init?: { code: Cell; data: Cell };

  constructor(address: Address, init?: { code: Cell; data: Cell }) {
    this.address = address;
    this.init = init;
  }

  /**
   * Create BridgeMultisig instance from address
   */
  static createFromAddress(address: Address) {
    return new BridgeMultisig(address);
  }

  /**
   * Execute a mint operation (2-of-3 watcher quorum)
   *
   * @param provider - Contract provider
   * @param via - Sender (wallet)
   * @param payload - Mint payload
   * @param signatures - Array of watcher signatures (minimum 2)
   * @param gasAmount - Gas amount in TON (default: 0.26)
   */
  async sendMint(
    provider: ContractProvider,
    via: Sender,
    payload: TonMintPayload,
    signatures: TonSignature[],
    gasAmount: number = 0.26
  ) {
    const body = buildExecuteMintMessage(payload, signatures);

    await provider.internal(via, {
      value: toNano(String(gasAmount)),
      sendMode: 1,
      body,
    });
  }

  /**
   * Execute a governance action (4-of-5 governance quorum)
   *
   * @param provider - Contract provider
   * @param via - Sender (wallet)
   * @param action - Governance action
   * @param signatures - Array of governance signatures (minimum 4)
   * @param gasAmount - Gas amount in TON (default: 0.05)
   */
  async sendGovernanceAction(
    provider: ContractProvider,
    via: Sender,
    action: GovernanceAction,
    signatures: TonSignature[],
    gasAmount: number = 0.05
  ) {
    const body = buildExecuteGovernanceMessage(action, signatures);

    await provider.internal(via, {
      value: toNano(String(gasAmount)),
      sendMode: 1,
      body,
    });
  }

  /**
   * Get current mint nonce
   */
  async getMintNonce(provider: ContractProvider): Promise<bigint> {
    const result = await provider.get('get_mint_nonce', []);
    return result.stack.readBigNumber();
  }

  /**
   * Get current governance nonce
   */
  async getGovernanceNonce(provider: ContractProvider): Promise<bigint> {
    const result = await provider.get('get_governance_nonce', []);
    return result.stack.readBigNumber();
  }

  /**
   * Get current governance epoch
   */
  async getGovernanceEpoch(provider: ContractProvider): Promise<bigint> {
    const result = await provider.get('get_governance_epoch', []);
    return result.stack.readBigNumber();
  }

  /**
   * Get nonce for a specific chain (returns 0 if chain not found)
   */
  async getChainNonce(provider: ContractProvider, originChainId: number): Promise<bigint> {
    const result = await provider.get('get_chain_nonce', [{ type: 'int', value: BigInt(originChainId) }]);
    return result.stack.readBigNumber();
  }

  /**
   * Get watcher public key by index (0-2)
   */
  async getWatcher(provider: ContractProvider, index: number): Promise<bigint> {
    const result = await provider.get('get_watcher', [{ type: 'int', value: BigInt(index) }]);
    return result.stack.readBigNumber();
  }

  /**
   * Get governance member public key by index (0-4)
   */
  async getGovernanceMember(provider: ContractProvider, index: number): Promise<bigint> {
    const result = await provider.get('get_governance_member', [
      { type: 'int', value: BigInt(index) },
    ]);
    return result.stack.readBigNumber();
  }

  /**
   * Check if a jetton is allowed for minting
   */
  async isJettonAllowed(provider: ContractProvider, jettonAddress: Address): Promise<boolean> {
    const result = await provider.get('is_jetton_allowed_query', [
      { type: 'slice', cell: beginCell().storeAddress(jettonAddress).endCell() },
    ]);
    return result.stack.readBigNumber() !== BigInt(0);
  }

  /**
   * Check if a payload hash has been consumed
   */
  async isPayloadConsumed(provider: ContractProvider, hash: bigint): Promise<boolean> {
    const result = await provider.get('is_payload_consumed', [{ type: 'int', value: hash }]);
    return result.stack.readBigNumber() !== BigInt(0);
  }

  /**
   * Get the hash of a mint payload (for verification)
   */
  async getMintPayloadHash(
    provider: ContractProvider,
    payload: TonMintPayload
  ): Promise<bigint> {
    // This would call the on-chain get method, but for now we use off-chain calculation
    // since it should match exactly
    const hash = hashMintPayload(payload);
    return BigInt('0x' + hash.toString('hex'));
  }

  /**
   * Get the hash of a governance action (for verification)
   */
  async getGovernanceActionHash(
    provider: ContractProvider,
    action: GovernanceAction
  ): Promise<bigint> {
    // This would call the on-chain get method, but for now we use off-chain calculation
    const hash = hashGovernanceAction(action);
    return BigInt('0x' + hash.toString('hex'));
  }
}

/**
 * Deploy parameters for the bridge multisig contract
 */
export interface DeployParams {
  watchers: Buffer[];       // 5 Ed25519 public keys (32 bytes each)
  governance: Buffer[];     // 5 Ed25519 public keys (32 bytes each)
  allowedJettons: string[]; // Array of TON jetton addresses
  initialMintNonce?: bigint; // Optional initial mint_nonce (default: 0)
  initialGovernanceNonce?: bigint; // Optional initial governance_nonce (default: 0)
  initialGovernanceEpoch?: bigint; // Optional initial governance_epoch (default: 0)
  feeWallet?: string; // Optional fee wallet address (TON address, default: zero address)
}

/**
 * Build initial storage data for contract deployment
 *
 * @param params - Deployment parameters
 * @returns Initial storage cell
 */
export function buildInitialStorage(params: DeployParams): Cell {
  if (params.watchers.length !== 5) {
    throw new Error('Exactly 5 watchers required');
  }

  if (params.governance.length !== 5) {
    throw new Error('Exactly 5 governance members required');
  }

  for (const watcher of params.watchers) {
    if (watcher.length !== 32) {
      throw new Error('Watcher public keys must be 32 bytes');
    }
  }

  for (const gov of params.governance) {
    if (gov.length !== 32) {
      throw new Error('Governance public keys must be 32 bytes');
    }
  }

  // Build watchers dictionary: dict(uint8 -> bits256)
  // Store as BigUint(256) to match FunC's store_uint(pubkey, 256)
  const watchersDict = Dictionary.empty(Dictionary.Keys.Uint(8), Dictionary.Values.BigUint(256));
  for (let i = 0; i < 5; i++) {
    const pubkeyBigInt = BigInt('0x' + params.watchers[i].toString('hex'));
    watchersDict.set(i, pubkeyBigInt);
  }

  // Build governance dictionary: dict(uint8 -> bits256)
  const governanceDict = Dictionary.empty(Dictionary.Keys.Uint(8), Dictionary.Values.BigUint(256));
  for (let i = 0; i < 5; i++) {
    const pubkeyBigInt = BigInt('0x' + params.governance[i].toString('hex'));
    governanceDict.set(i, pubkeyBigInt);
  }

  // Build allowed jettons dictionary: dict(uint256 -> uint1)
  // Key is the hash of the jetton address
  // Value serializer for single bit (uint1)
  const uint1Value = {
    serialize: (src: boolean, builder: any) => {
      builder.storeBit(src);
    },
    parse: (src: any) => {
      return src.loadBit();
    },
  };

  const allowedJettonsDict = Dictionary.empty(Dictionary.Keys.BigUint(256), uint1Value);
  for (const jettonAddr of params.allowedJettons) {
    const addr = Address.parse(jettonAddr);
    const addrCell = beginCell().storeAddress(addr).endCell();
    const addrHash = BigInt('0x' + addrCell.hash().toString('hex'));
    allowedJettonsDict.set(addrHash, true); // allowed = true
  }

  // Build token mappings dictionary: dict(bits256 -> MsgAddressInt)
  // Initially empty
  const tokenMappingsDict = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Address());

  // Build consumed hashes dictionary: dict(bits256 -> uint1)
  // Initially empty
  const consumedHashesDict = Dictionary.empty(Dictionary.Keys.BigUint(256), uint1Value);

  // Build consumed references dictionary: dict(uint64 -> uint1)
  // Initially empty
  const consumedReferencesDict = Dictionary.empty(Dictionary.Keys.BigUint(64), uint1Value);

  // Build complete storage
  // Storage layout needs to fit within 4 refs per cell limit
  // We nest operation-related dicts together to stay within limits

  // IMPORTANT: FunC expects raw dictionary cells, not wrapped cells!
  // storeDict() creates wrapper (1bit + ref to actual dict), so we extract the inner ref
  const extractDictCell = (dict: any) => {
    const wrapper = beginCell().storeDict(dict).endCell();
    // If dict is empty, wrapper has 1 bit (0) and 0 refs
    // If dict has entries, wrapper has 1 bit (1) and 1 ref (actual dict)
    return wrapper.refs.length > 0 ? wrapper.refs[0] : new Cell();
  };

  const watchersCell = extractDictCell(watchersDict);
  const governanceCell = extractDictCell(governanceDict);
  const allowedJettonsCell = extractDictCell(allowedJettonsDict);
  const tokenMappingsCell = extractDictCell(tokenMappingsDict);
  const consumedHashesCell = extractDictCell(consumedHashesDict);
  const consumedReferencesCell = extractDictCell(consumedReferencesDict);

  // Parse fee wallet address (default to zero address if not provided)
  const feeWalletAddress = params.feeWallet
    ? Address.parse(params.feeWallet)
    : null;

  // Nest operation-related dictionaries to fit within 4 ref limit:
  // - token_mappings, consumed_hashes, consumed_references, fee_wallet
  // Note: FunC load_data() expects: token_mappings, consumed_hashes, consumed_references, fee_wallet
  const operationsCell = beginCell()
    .storeRef(tokenMappingsCell)
    .storeRef(consumedHashesCell)
    .storeRef(consumedReferencesCell)
    .storeAddress(feeWalletAddress)   // fee_wallet (MsgAddressInt, can be addr_none)
    .endCell();

  // Get initial nonce values
  const mintNonce = params.initialMintNonce ?? 0n;
  const governanceNonce = params.initialGovernanceNonce ?? 0n;
  const governanceEpoch = params.initialGovernanceEpoch ?? 0n;

  // Build main storage with 4 refs + inline data
  return beginCell()
    .storeRef(watchersCell)           // ref 1
    .storeRef(governanceCell)         // ref 2
    .storeRef(allowedJettonsCell)     // ref 3
    .storeRef(operationsCell)         // ref 4: (token_mappings, consumed_hashes, consumed_references, fee_wallet)
    .storeUint(mintNonce, 64)         // mint_nonce
    .storeUint(governanceNonce, 64)   // governance_nonce
    .storeUint(governanceEpoch, 64)   // governance_epoch
    .endCell();
}

/**
 * Helper to create contract instance from config
 */
export function createBridgeMultisig(config: BridgeMultisigConfig): BridgeMultisig {
  return BridgeMultisig.createFromAddress(Address.parse(config.contractAddress));
}

/**
 * Estimate gas needed for mint operation
 * @param gasAmount - Gas amount in TON (default: 0.26)
 */
export function estimateMintGas(gasAmount: number = 0.26): bigint {
  return toNano(String(gasAmount));
}

/**
 * Estimate gas needed for governance operation
 * @param gasAmount - Gas amount in TON (default: 0.05)
 */
export function estimateGovernanceGas(gasAmount: number = 0.05): bigint {
  return toNano(String(gasAmount));
}

/**
 * Format public key as hex string for display
 */
export function formatPublicKey(pubkey: bigint | Buffer): string {
  if (Buffer.isBuffer(pubkey)) {
    return '0x' + pubkey.toString('hex');
  }
  return '0x' + pubkey.toString(16).padStart(64, '0');
}

/**
 * Parse public key from hex string
 */
export function parsePublicKey(hex: string): Buffer {
  const cleaned = hex.startsWith('0x') ? hex.slice(2) : hex;
  if (cleaned.length !== 64) {
    throw new Error('Public key hex must be 64 characters (32 bytes)');
  }
  return Buffer.from(cleaned, 'hex');
}
