# Mint nonce is never validated, allowing execution of stale/rewound mint authorizations


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex, aiflow_scanner_smart |
| Scan Model | gpt-5.2 |
| Project ID | `c0b155c0-ce9d-11f0-afef-b3f141791562` |
| Commit | `20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856` |

## Location

- **Local path:** `./src/contracts/ton/bridge-multisig.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc
- **Lines:** 1–1

## Description

The `execute_mint` logic has a nonce-handling flaw: it assigns `mint_nonce = nonce` but never validates the provided `nonce` against the current on-chain `mint_nonce` (e.g., requiring `nonce == mint_nonce + 1` or at least `nonce > mint_nonce`), unlike `execute_governance_action` which correctly enforces strict ordering (`nonce == governance_nonce + 1`). Consequently, the contract’s documented “replay protection via nonces” is not actually enforced for mints—any watcher-signed mint payload can be executed even if its nonce is old, skipped, duplicated, or out of order, and a smaller nonce can even rewind `mint_nonce` backwards, breaking the intended monotonic progression and potentially confusing off-chain relayers/indexers that rely on `mint_nonce` to determine pending mints (leading to missed or stalled processing). The only on-chain protection is `consumed_hashes` keyed by `payload_hash`, which prevents re-executing the exact same payload but does not enforce per-nonce uniqueness/order or allow newer nonces to invalidate previously signed payloads; therefore, multiple distinct payloads with different hashes can still be executed under the same or older nonce. This breaks the intended “Exactly-Once” delivery semantics for source-chain events: during source chain reorganizations or temporary forks where watchers may sign different payloads for the same sequence number, an attacker holding valid signature bundles can execute all conflicting mints (or submit mints out of order), causing double-minting/double-spending; e.g., execute a mint with `nonce=100` then another with `nonce=50` (rewinding `mint_nonce`), or execute Payload A and Payload B that share `nonce=10` but differ in other fields, both succeeding because each has a unique `payload_hash` and no `nonce > mint_nonce` check blocks the second execution. The issue is exploitable by a non-privileged caller who legitimately obtains watcher signatures, and the fix is to enforce the expected nonce progression in `execute_mint` before updating state.

## Recommendation

- Enforce strict monotonic progression in execute_mint: require nonce == mint_nonce + 1 and revert otherwise. Never assign mint_nonce = nonce without validation.
- Update mint_nonce only after all signature checks and state mutations succeed (advance by one; do not accept smaller, equal, skipped, or out-of-order nonces).
- Align the nonce logic with execute_governance_action for consistency and to preserve exactly-once semantics.
- Do not rely on consumed_hashes to prevent replays; for mints, either:
  - Rely solely on strict sequential nonces (preferred), or
  - If gaps must be supported, maintain a processedNonces set/bitmap and reject nonce <= mint_nonce while never decreasing mint_nonce.
- Add tests covering stale, duplicate, out-of-order, and rewind scenarios, and verify that conflicting payloads with the same nonce are rejected.

## Vulnerable Code

```
() execute_mint(int origin_chain_id, int token, slice ton_recipient, int amount, int nonce, int epoch, cell signatures) impure {
    ;; Load state
    load_data();

    ;; Verify epoch matches current epoch (prevents replay of old signatures after rotation)
    throw_unless(ERR_INVALID_NONCE, epoch == governance_epoch);

    ;; Hash the mint payload
    int payload_hash = hash_mint_payload(origin_chain_id, token, ton_recipient, amount, nonce, epoch);

    ;; Check if already consumed
    throw_if(ERR_PAYLOAD_CONSUMED, is_hash_consumed(payload_hash));

    ;; Lookup TON jetton root from token mapping
    (slice jetton_root, int found) = get_token_mapping(token);
    throw_unless(ERR_TOKEN_NOT_ALLOWED, found);

    ;; Verify jetton is allowed in whitelist
    throw_unless(ERR_TOKEN_NOT_ALLOWED, is_jetton_allowed(jetton_root));

    ;; Validate watcher signatures
    validate_watcher_signatures(payload_hash, signatures);

    ;; Update state
    mint_nonce = nonce;
    mark_hash_consumed(payload_hash);
    save_data();

    ;; Build jetton mint message (nested structure from @ton-community/assets-sdk)
    ;; Internal transfer body (will be stored in ref)
    cell internal_transfer = begin_cell()
        .store_uint(OP_INTERNAL_TRANSFER, 32)  ;; op = 0x178d4519
        .store_uint(0, 64)                      ;; query_id
        .store_coins(amount)                    ;; amount
        .store_slice(my_address())              ;; from (multisig)
        .store_slice(my_address())              ;; responseAddress (bounce back to multisig)
        .store_coins(OWNER_FORWARD_TON)         ;; forwardTonAmount (0.05 TON)
        .store_uint(1, 1)                       ;; forwardPayload (Either: 1 = in ref)
        .store_ref(begin_cell().end_cell())    ;; empty cell as forward payload
    .end_cell();

    ;; Mint message body
    cell mint_body = begin_cell()
        .store_uint(OP_MINT_JETTON, 32)         ;; op = 0x15 (mint)
        .store_uint(0, 64)                      ;; query_id
        .store_slice(ton_recipient)             ;; to (receiver)
        .store_coins(JW_FORWARD_VALUE)          ;; walletForwardValue (0.05 TON)
        .store_ref(internal_transfer)           ;; internal transfer in ref
    .end_cell();

    send_raw_message(begin_cell()
        .store_uint(0x18, 6)                 ;; bounceable message
        .store_slice(jetton_root)
        .store_coins(GAS_FOR_JETTON_MINT)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1)  ;; extra_currencies, ihr_fee, fwd_fee, created_lt, created_at, init
        .store_uint(1, 1)                    ;; body in ref (not inline)
        .store_ref(mint_body)
    .end_cell(), 1);

    ;; Emit mint executed log
    ;; Store ton_recipient in ref to avoid cell overflow (MsgAddressInt can be ~267 bits)
    cell recipient_ref = begin_cell()
        .store_slice(ton_recipient)
    .end_cell();

    cell log = begin_cell()
        .store_uint(0x4d494e54, 32)         ;; mint_executed_log tag
        .store_uint(payload_hash, 256)
        .store_uint(origin_chain_id, 32)
        .store_uint(token, 256)
        .store_uint(amount, 128)
        .store_uint(nonce, 64)
        .store_uint(now(), 64)
        .store_ref(recipient_ref)           ;; ton_recipient in ref
    .end_cell();

    ;; Send log as internal message to self (for indexing)
    send_raw_message(begin_cell()
        .store_uint(0x10, 6)                ;; nobounce
        .store_slice(my_address())
        .store_coins(GAS_FOR_LOG)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .store_ref(log)
    .end_cell(), 1);
}
```

## Related Context

```
load_data -> () load_data() impure {
    slice ds = get_data().begin_parse();
    ;; Load watchers, governance, allowed_jettons
    ;; These dicts should NEVER be empty (watchers has 5 members, governance has 5)
    watchers = ds~load_ref();
    governance = ds~load_ref();
    allowed_jettons = ds~load_ref();

    ;; Operations cell contains: token_mappings, consumed_hashes, consumed_references, fee_wallet
    ;; Dicts CAN be empty initially, stored as empty cells (0 bits, 0 refs)
    cell operations_cell = ds~load_ref();
    slice ops = operations_cell.begin_parse();
    token_mappings = ensure_initialized_dict(ops~load_ref());
    consumed_hashes = ensure_initialized_dict(ops~load_ref());
    consumed_references = ensure_initialized_dict(ops~load_ref());
    fee_wallet = ops~load_msg_addr();  ;; Load fee wallet address

    ;; ensure_initialized_dict() converts empty cells → () for dict operations

    mint_nonce = ds~load_uint(64);
    governance_nonce = ds~load_uint(64);
    governance_epoch = ds~load_uint(64);
}

hash_mint_payload -> int hash_mint_payload(int origin_chain_id, int token, slice ton_recipient, int amount, int nonce, int epoch) inline {
    cell payload = begin_cell()
        .store_uint(0x4d494e54, 32)         ;; mint_payload tag
        .store_uint(origin_chain_id, 32)
        .store_uint(token, 256)
        .store_slice(ton_recipient)
        .store_uint(amount, 128)
        .store_uint(nonce, 64)
        .store_uint(epoch, 64)
    .end_cell();
    return cell_hash(payload);
}

is_hash_consumed -> int is_hash_consumed(int hash) inline {
    (slice value, int found) = consumed_hashes.udict_get?(256, hash);
    if (~ found) {
        return 0;
    }
    return value~load_uint(1);
}

get_token_mapping -> (slice, int) get_token_mapping(int evm_token) inline {
    (slice value, int found) = token_mappings.udict_get?(256, evm_token);
    if (~ found) {
        return (begin_cell().end_cell().begin_parse(), 0);
    }
    return (value~load_msg_addr(), 1);
}

is_jetton_allowed -> int is_jetton_allowed(slice jetton_addr) inline {
    int addr_hash = slice_hash(jetton_addr);
    (slice value, int found) = allowed_jettons.udict_get?(256, addr_hash);
    if (~ found) {
        return 0;
    }
    return value~load_uint(1);
}

validate_watcher_signatures -> () validate_watcher_signatures(int hash, cell signatures_cell) impure inline {
    slice signatures = signatures_cell.begin_parse();

    ;; Track which watchers have signed (bitmap)
    int seen_bitmap = 0;
    int signature_count = 0;

    ;; Parse signatures: each signature is (pubkey:bits256, sig_hi:bits256, sig_lo:bits256)
    ;; Signatures may span multiple cells in a reference chain
    int continue_parsing = -1;

    while (continue_parsing) {
        ;; Load signature from current cell
        int pubkey = signatures~load_uint(256);
        int sig_hi = signatures~load_uint(256);
        int sig_lo = signatures~load_uint(256);

        ;; Verify signature and get signer index
        int signer_index = verify_signature_in_set(hash, pubkey, sig_hi, sig_lo, watchers, WATCHER_COUNT);

        ;; Check for duplicate signer
        int signer_mask = 1 << signer_index;
        throw_if(ERR_DUPLICATE_SIGNER, seen_bitmap & signer_mask);

        ;; Mark this signer as seen
        seen_bitmap = seen_bitmap | signer_mask;
        signature_count += 1;

        ;; Check if there are more signatures in the reference chain
        if (~ signatures.slice_refs_empty?()) {
            ;; Load next cell in chain
            cell next_cell = signatures~load_ref();
            signatures = next_cell.begin_parse();
        } else {
            ;; No more references, stop parsing
            continue_parsing = 0;
        }
    }

    ;; Verify threshold met
    throw_unless(ERR_THRESHOLD_NOT_MET, signature_count >= WATCHER_THRESHOLD);
}

mark_hash_consumed -> () mark_hash_consumed(int hash) impure inline {
    consumed_hashes = consumed_hashes.udict_set_builder(256, hash, begin_cell().store_uint(1, 1));
}

save_data -> () save_data() impure {
    ;; Build operations cell: token_mappings, consumed_hashes, consumed_references, fee_wallet
    ;; Convert () → empty cell before storing with store_ref()
    cell operations_cell = begin_cell()
        .store_ref(dict_as_cell(token_mappings))
        .store_ref(dict_as_cell(consumed_hashes))
        .store_ref(dict_as_cell(consumed_references))
        .store_slice(fee_wallet)
    .end_cell();

    ;; Build main storage (4 refs max per cell)
    set_data(
        begin_cell()
            .store_ref(watchers)
            .store_ref(governance)
            .store_ref(allowed_jettons)
            .store_ref(operations_cell)
            .store_uint(mint_nonce, 64)
            .store_uint(governance_nonce, 64)
            .store_uint(governance_epoch, 64)
        .end_cell()
    );
}
```
