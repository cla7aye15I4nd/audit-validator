# TON Bridge Multisig Smart Contracts

This directory contains the FunC smart contracts for the TON side of the bridge multisig system.

## Overview

The TON Bridge Multisig implements a secure, threshold-based governance system for managing cross-chain token minting and administrative operations. It features:

- **3-of-5 Watcher Quorum** for EVM→TON mint operations
- **3-of-5 Governance Quorum** for admin operations
- Ed25519 signature verification
- Replay protection via nonces and reference tracking
- Event logging for off-chain monitoring

## Contract Files

### Core Contracts

- **`bridge-multisig.fc`** - Main multisig contract implementation
  - Watcher-controlled mint operations
  - Governance-controlled admin operations
  - TON withdrawal emergency functionality
  - Signature verification and replay protection

- **`bridge-multisig-init.fc`** - Initialization data builder
  - Constructs initial contract storage
  - Sets up watcher and governance sets
  - Configures allowed jettons

### Schemas

- **`schemas/bridge-multisig.tlb`** - TL-B schema definitions
  - Payload structures for all operations
  - Event log formats
  - Storage layout specification

### Helpers

- **`helpers/withdraw-ton-funds.ts`** - TypeScript utilities for TON withdrawals
  - Off-chain signature generation
  - Message building
  - Validation helpers
  - Event parsing

## Features

### 1. Mint Operations (3-of-5 Watcher Quorum)

Allows watchers to mint jettons on TON after verifying burns on EVM chains.

**Payload:**
```
mint_payload#4d494e54
    origin_chain_id:uint32
    token:bits256
    ton_recipient:MsgAddressInt
    amount:uint128
    nonce:uint64
```

**Security:**
- Strictly incremental nonce enforcement
- Payload hash consumption tracking
- Jetton whitelist verification
- 3-of-5 unique watcher signatures required

### 2. Governance Actions (3-of-5 Quorum)

Critical operations requiring governance approval:

#### UPDATE_WATCHERS (0x01)
Update the set of authorized watchers.

#### UPDATE_GOVERNANCE (0x02)
Update the set of governance members.

#### SET_TOKEN_STATUS (0x03)
Enable or disable jettons for minting.

#### TRANSFER_TOKEN_OWNER (0x04)
Transfer ownership of jetton root contracts.

### 3. Emergency TON Withdrawal

Time-sensitive fund rescue scenarios.

**Payload:**
```
withdraw_ton_funds_payload#574452415720
    destination:MsgAddressInt
    amount:uint128
    reference:uint64
```

**Use Cases:**
- Contract migration during upgrades
- Emergency fund rescue
- Rebalancing between contracts

**Security Features:**
- Reference-based replay protection (independent of nonce)
- Minimum 1 TON reserve enforcement
- Destination address validation
- 3-of-5 governance signatures required
- Full audit trail via event logs

See [detailed documentation](../../docs/ton-withdraw-funds-implementation.md) for complete specification.

## Operation Codes

| Operation | Code | Description |
|-----------|------|-------------|
| EXECUTE_MINT | 0x4d494e54 | Execute mint with watcher signatures |
| EXECUTE_GOVERNANCE | 0x474f5645 | Execute governance action (3-of-5) |
| EXECUTE_WITHDRAW_TON | 0x574452415720 | Withdraw TON funds (3-of-5) |
| MINT_JETTON | 0x15 | Internal jetton mint operation |
| TRANSFER_OWNERSHIP | 0x16 | Internal ownership transfer |

## Storage Layout

```
Storage {
    watchers: dict(uint8 -> bits256)           // 5 watcher public keys
    governance: dict(uint8 -> bits256)         // 5 governance public keys
    allowed_jettons: dict(bits256 -> uint1)    // Jetton whitelist
    mint_nonce: uint64                         // Mint replay protection
    governance_nonce: uint64                   // Governance replay protection
    consumed_hashes: dict(bits256 -> uint1)    // Consumed payload hashes
    consumed_references: dict(uint64 -> uint1) // Consumed withdrawal refs
}
```

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| 100 | ERR_UNAUTHORIZED | Signer not in authorized set |
| 101 | ERR_INVALID_SIGNATURE | Ed25519 verification failed |
| 102 | ERR_DUPLICATE_SIGNER | Same signer used multiple times |
| 103 | ERR_THRESHOLD_NOT_MET | Insufficient signatures |
| 104 | ERR_INVALID_NONCE | Nonce not sequential |
| 105 | ERR_PAYLOAD_CONSUMED | Replay attempt detected |
| 106 | ERR_TOKEN_NOT_ALLOWED | Jetton not whitelisted |
| 107 | ERR_INVALID_ACTION | Unknown action type |
| 108 | ERR_INVALID_WATCHER_COUNT | Wrong watcher set size |
| 109 | ERR_INVALID_GOVERNANCE_COUNT | Wrong governance set size |
| 110 | ERR_INSUFFICIENT_BALANCE | Not enough TON for withdrawal |
| 111 | ERR_INVALID_DESTINATION | Invalid address format |

## Get Methods

```func
// Query current state
int get_mint_nonce() method_id;
int get_governance_nonce() method_id;
int get_watcher(int index) method_id;
int get_governance_member(int index) method_id;
int is_jetton_allowed_query(slice jetton_addr) method_id;
int is_payload_consumed(int hash) method_id;
int is_reference_consumed_query(int reference) method_id;

// Compute hashes for off-chain verification
int get_mint_payload_hash(int origin_chain_id, int token, slice ton_recipient, int amount, int nonce) method_id;
int get_governance_action_hash(int action_type, int nonce, cell payload_ref) method_id;
int get_withdraw_ton_funds_hash(slice destination, int amount, int reference) method_id;
```

## Compilation

### Using func compiler

```bash
func -o bridge-multisig.fif \
     -SPA \
     stdlib.fc \
     bridge-multisig.fc
```

### Using Blueprint

```bash
npx blueprint build
```

## Deployment

### 1. Prepare Initial Data

```typescript
import { buildInitialStorage } from './bridge-multisig-init';

const initData = buildInitialStorage(
    watcherKeys,      // [pubkey1, pubkey2, pubkey3]
    governanceKeys,   // [pubkey1, pubkey2, pubkey3, pubkey4, pubkey5]
    jettonAddresses   // [address1, address2, ...]
);
```

### 2. Deploy Contract

```typescript
import { contractAddress } from '@ton/core';

const contract = contractAddress(0, {
    code: compiledCode,
    data: initData
});

// Deploy via wallet...
```

### 3. Fund Contract

Send at least 1.5 TON to cover:
- Storage rent: 1 TON minimum
- Gas for operations: 0.5+ TON buffer

## Testing

### Unit Tests

```bash
# Run FunC tests
npm run test:ton

# Run TypeScript integration tests
npm run test:ton:integration
```

### Test Checklist

- [ ] Mint with 3-of-5 watcher signatures succeeds
- [ ] Mint with 2-of-5 watcher signatures fails
- [ ] Duplicate watcher signature rejected
- [ ] Nonce replay attack prevented
- [ ] Governance action with 3-of-5 signatures succeeds
- [ ] Governance action with 2-of-5 signatures fails
- [ ] TON withdrawal with 3-of-5 signatures succeeds
- [ ] TON withdrawal with 2-of-5 signatures fails
- [ ] Reference replay attack prevented
- [ ] Withdrawal respects 1 TON minimum reserve
- [ ] Invalid destination address rejected
- [ ] Event logs emitted correctly

## Security Considerations

### Signature Verification

All signatures verified using TON's built-in `check_signature()` with Ed25519:
- 256-bit public keys stored in dictionaries
- 512-bit signatures (split into hi/lo 256-bit halves)
- Hash-based signing (cell_hash of payload)

### Replay Protection

Multiple layers:
1. **Nonces**: Strictly incremental for mint and governance
2. **Hash Tracking**: Consumed payload hashes stored
3. **Reference IDs**: Unique withdrawal references tracked
4. **Bitmap**: Prevents duplicate signers within single operation

### Reentrancy Protection

State saved before external calls:
```func
save_data();  // Commit state first
send_raw_message(...);  // Then send message
```

### Gas DoS Prevention

- Controlled iteration (max 5 signatures)
- Fixed-depth operations (no recursion)
- Stipend limits on internal messages

## Migration Guide

### Adding WITHDRAW_TON_FUNDS to Existing Contract

If upgrading from v1.0.0 to v1.1.0:

1. Storage migration required (add `consumed_references` dict)
2. Code update via governance action
3. Test on testnet first
4. Execute via TRANSFER_TOKEN_OWNER to new contract

See [migration guide](../../docs/ton-withdraw-funds-implementation.md#migration-guide) for details.

## Support

For issues or questions:
- Review [TL-B schemas](schemas/bridge-multisig.tlb)
- Check [withdrawal implementation doc](../../docs/ton-withdraw-funds-implementation.md)
- Inspect [main specification](../../docs/specs/ton-bridge-multisig.md)

## License

[Your License Here]

## Version

Current version: **1.1.0**

Changes:
- ✅ Added WITHDRAW_TON_FUNDS governance action (3-of-5 quorum)
- ✅ Reference-based replay protection for withdrawals
- ✅ Withdrawals can drain full balance (no enforced storage reserve)
- ✅ TypeScript helper library for off-chain operations
