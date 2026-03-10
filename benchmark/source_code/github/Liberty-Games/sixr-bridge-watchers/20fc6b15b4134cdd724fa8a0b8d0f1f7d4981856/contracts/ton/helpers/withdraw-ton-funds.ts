/**
 * TON Bridge Multisig - WITHDRAW_TON_FUNDS Helper Functions
 *
 * This module provides TypeScript helpers for creating and submitting
 * TON withdrawal transactions via the multisig governance mechanism.
 */

import { Address, beginCell, Cell, Contract, contractAddress } from '@ton/core';
import { sign } from '@ton/crypto';

/**
 * Parameters for a TON withdrawal action
 */
export interface WithdrawTonFundsParams {
    destination: Address;       // TON address to receive funds
    amount: bigint;             // Amount in nanotons
    reference: bigint;          // Unique reference ID (for replay protection)
}

/**
 * Governance signature for withdrawal action
 */
export interface GovernanceSignature {
    publicKey: Buffer;          // Ed25519 public key (32 bytes)
    signature: Buffer;          // Ed25519 signature (64 bytes)
}

/**
 * Op codes for TON Bridge Multisig
 */
export const OpCodes = {
    EXECUTE_MINT: 0x4d494e54,
    EXECUTE_GOVERNANCE: 0x474f5645,
    EXECUTE_WITHDRAW_TON: 0x574452415720n,  // 48-bit op code
} as const;

/**
 * Action type codes
 */
export const ActionTypes = {
    UPDATE_WATCHERS: 0x01,
    UPDATE_GOVERNANCE: 0x02,
    SET_TOKEN_STATUS: 0x03,
    TRANSFER_TOKEN_OWNER: 0x04,
    WITHDRAW_TON_FUNDS: 0x05,
} as const;

/**
 * Error codes from the contract
 */
export const ErrorCodes = {
    ERR_UNAUTHORIZED: 100,
    ERR_INVALID_SIGNATURE: 101,
    ERR_DUPLICATE_SIGNER: 102,
    ERR_THRESHOLD_NOT_MET: 103,
    ERR_INVALID_NONCE: 104,
    ERR_PAYLOAD_CONSUMED: 105,
    ERR_TOKEN_NOT_ALLOWED: 106,
    ERR_INVALID_ACTION: 107,
    ERR_INVALID_WATCHER_COUNT: 108,
    ERR_INVALID_GOVERNANCE_COUNT: 109,
    ERR_INSUFFICIENT_BALANCE: 110,
    ERR_INVALID_DESTINATION: 111,
} as const;

/**
 * Constants
 */
export const Constants = {
    GOVERNANCE_THRESHOLD_RELAXED: 3,            // 3-of-5 for withdrawals
    GOVERNANCE_THRESHOLD_STANDARD: 4,           // 4-of-5 for other actions
    GOVERNANCE_COUNT: 5,
} as const;

/**
 * Build the payload cell for WITHDRAW_TON_FUNDS action
 * This cell is what governance members sign
 */
export function buildWithdrawPayloadForSigning(
    params: WithdrawTonFundsParams
): Cell {
    return beginCell()
        .storeUint(OpCodes.EXECUTE_WITHDRAW_TON, 48)  // withdraw_ton_funds_payload tag
        .storeAddress(params.destination)
        .storeUint(params.amount, 128)
        .storeUint(params.reference, 64)
        .endCell();
}

/**
 * Calculate the hash that governance members must sign
 */
export function getWithdrawPayloadHash(
    params: WithdrawTonFundsParams
): Buffer {
    const payload = buildWithdrawPayloadForSigning(params);
    return payload.hash();
}

/**
 * Sign a withdrawal payload with a governance private key
 */
export async function signWithdrawPayload(
    params: WithdrawTonFundsParams,
    privateKey: Buffer
): Promise<Buffer> {
    const hash = getWithdrawPayloadHash(params);
    return sign(hash, privateKey);
}

/**
 * Pack governance signatures into a cell
 * Format: (pubkey:bits256, sig_hi:bits256, sig_lo:bits256) repeated
 */
export function packSignatures(
    signatures: GovernanceSignature[]
): Cell {
    if (signatures.length < Constants.GOVERNANCE_THRESHOLD_RELAXED) {
        throw new Error(
            `At least ${Constants.GOVERNANCE_THRESHOLD_RELAXED} signatures required, got ${signatures.length}`
        );
    }

    if (signatures.length > Constants.GOVERNANCE_COUNT) {
        throw new Error(
            `Maximum ${Constants.GOVERNANCE_COUNT} signatures allowed, got ${signatures.length}`
        );
    }

    // Build reference chain so each cell holds a single signature (prevents cell overflow)
    let currentCell: Cell | null = null;

    for (let i = signatures.length - 1; i >= 0; i--) {
        const sig = signatures[i];

        if (sig.publicKey.length !== 32) {
            throw new Error('Public key must be 32 bytes');
        }
        if (sig.signature.length !== 64) {
            throw new Error('Signature must be 64 bytes');
        }

        const builder = beginCell();
        builder.storeBuffer(sig.publicKey);
        builder.storeBuffer(sig.signature.subarray(0, 32));
        builder.storeBuffer(sig.signature.subarray(32, 64));

        if (currentCell) {
            builder.storeRef(currentCell);
        }

        currentCell = builder.endCell();
    }

    if (!currentCell) {
        throw new Error('Failed to build signatures cell');
    }

    return currentCell;
}

/**
 * Build the complete internal message body for WITHDRAW_TON_FUNDS
 */
export function buildWithdrawMessage(
    params: WithdrawTonFundsParams,
    signatures: GovernanceSignature[]
): Cell {
    const signaturesCell = packSignatures(signatures);

    return beginCell()
        .storeUint(OpCodes.EXECUTE_WITHDRAW_TON, 48)  // op code (48 bits!)
        .storeAddress(params.destination)
        .storeUint(params.amount, 128)
        .storeUint(params.reference, 64)
        .storeRef(signaturesCell)
        .endCell();
}

/**
 * Helper to generate a unique reference ID based on timestamp and counter
 */
export function generateReference(counter: number = 0): bigint {
    const timestamp = BigInt(Math.floor(Date.now() / 1000)); // Unix timestamp
    const counterBits = BigInt(counter) & 0xFFFFn; // 16-bit counter
    return (timestamp << 16n) | counterBits;
}

/**
 * Interface for the TON Bridge Multisig contract (read methods)
 */
export interface BridgeMultisigContract extends Contract {
    /**
     * Get the hash of a withdrawal payload (for verification)
     */
    getWithdrawTonFundsHash(
        destination: Address,
        amount: bigint,
        reference: bigint
    ): Promise<bigint>;

    /**
     * Check if a reference ID has been consumed
     */
    isReferenceConsumedQuery(reference: bigint): Promise<boolean>;

    /**
     * Get current mint nonce
     */
    getMintNonce(): Promise<bigint>;

    /**
     * Get current governance nonce
     */
    getGovernanceNonce(): Promise<bigint>;

    /**
     * Get governance member public key by index (0-4)
     */
    getGovernanceMember(index: number): Promise<bigint>;
}

/**
 * Validation helper: Check if withdrawal can be executed
 */
export async function validateWithdrawal(
    contract: BridgeMultisigContract,
    params: WithdrawTonFundsParams
): Promise<{ valid: boolean; error?: string }> {
    // Check if reference already consumed
    const isConsumed = await contract.isReferenceConsumedQuery(params.reference);
    if (isConsumed) {
        return { valid: false, error: 'Reference ID already consumed (replay protection)' };
    }

    // Validate destination address
    if (!params.destination || params.destination.toRawString() === '') {
        return { valid: false, error: 'Invalid destination address' };
    }

    // Validate amount
    if (params.amount <= 0n) {
        return { valid: false, error: 'Amount must be positive' };
    }

    // Note: Cannot check balance from off-chain (would need contract.getBalance() method)
    // Recommendation: operators should ensure contract has enough TON for message fees.

    return { valid: true };
}

/**
 * Example usage function
 */
export async function exampleWithdrawUsage(
    multisigContract: BridgeMultisigContract,
    governancePrivateKeys: Buffer[],  // Must have at least 3
    governancePublicKeys: Buffer[],   // Corresponding public keys
    destinationAddress: Address,
    amountNanotons: bigint
) {
    // 1. Generate unique reference
    const reference = generateReference();

    // 2. Build withdrawal parameters
    const params: WithdrawTonFundsParams = {
        destination: destinationAddress,
        amount: amountNanotons,
        reference,
    };

    // 3. Validate before proceeding
    const validation = await validateWithdrawal(multisigContract, params);
    if (!validation.valid) {
        throw new Error(`Validation failed: ${validation.error}`);
    }

    // 4. Generate signatures from governance members
    const signatures: GovernanceSignature[] = [];
    for (let i = 0; i < Math.min(3, governancePrivateKeys.length); i++) {
        const signature = await signWithdrawPayload(params, governancePrivateKeys[i]);
        signatures.push({
            publicKey: governancePublicKeys[i],
            signature,
        });
    }

    // 5. Build message
    const messageBody = buildWithdrawMessage(params, signatures);

    // 6. Verify hash matches (optional sanity check)
    const localHash = getWithdrawPayloadHash(params);
    const contractHash = await multisigContract.getWithdrawTonFundsHash(
        params.destination,
        params.amount,
        params.reference
    );

    if (BigInt('0x' + localHash.toString('hex')) !== contractHash) {
        throw new Error('Hash mismatch! Local and contract hashes differ.');
    }

    console.log('Withdrawal message prepared successfully');
    console.log('Reference:', reference.toString());
    console.log('Amount:', params.amount.toString(), 'nanotons');
    console.log('Destination:', params.destination.toString());
    console.log('Signatures:', signatures.length);

    return messageBody;

    // 7. Send to contract (implementation depends on wallet SDK)
    // await wallet.sendInternalMessage(multisigContract.address, {
    //     value: toNano('0.1'),  // Gas
    //     body: messageBody,
    // });
}

/**
 * Parse withdrawal log event
 */
export interface WithdrawLogEvent {
    destination: Address;
    amount: bigint;
    reference: bigint;
    timestamp: bigint;
}

export function parseWithdrawLog(logCell: Cell): WithdrawLogEvent {
    const slice = logCell.beginParse();

    const tag = slice.loadUintBig(48);
    if (tag !== OpCodes.EXECUTE_WITHDRAW_TON) {
        throw new Error('Invalid log tag, not a withdrawal log');
    }

    return {
        destination: slice.loadAddress(),
        amount: slice.loadUintBig(128),
        reference: slice.loadUintBig(64),
        timestamp: slice.loadUintBig(64),
    };
}

/**
 * Utility: Convert nanotons to TON (for display)
 */
export function nanotonToTon(nanoton: bigint): string {
    const ton = Number(nanoton) / 1_000_000_000;
    return ton.toFixed(9);
}

/**
 * Utility: Convert TON to nanotons (for input)
 */
export function tonToNanoton(ton: number): bigint {
    return BigInt(Math.floor(ton * 1_000_000_000));
}
