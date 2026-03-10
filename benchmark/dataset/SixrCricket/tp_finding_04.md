# Mint executed log message to self is malformed and collides with OP_EXECUTE_MINT, causing failing self-transactions and TON drain


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `c0b155c0-ce9d-11f0-afef-b3f141791562` |
| Commit | `20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856` |

## Location

- **Local path:** `./src/contracts/ton/bridge-multisig.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc
- **Lines:** 1–1

## Description

execute_mint emits an “event log” by sending an internal message to my_address(), but the message is constructed in a way that cannot be safely received by this contract:
1) The log cell starts with 0x4d494e54, which is the same value as OP_EXECUTE_MINT. If the body were delivered as intended, recv_internal will interpret the log as a new OP_EXECUTE_MINT call and attempt to parse/execute it with garbage fields, reverting.
2) The log send uses `.store_uint(0, ... + 1 + 1)` (setting the `body` Either-tag bit to 0) and then `.store_ref(log)`. This makes the delivered body contain 0 bits and a single reference, so recv_internal will revert immediately on `preload_uint(48)` / `load_uint(32)` due to insufficient bits.
Because this message is sent on every mint, the contract continuously creates follow-up self-messages that fail, burning fees/value and potentially draining the contract’s TON balance over time (eventually DoS-ing minting/operations that require TON to send outbound messages). Fix by (a) using a distinct, non-conflicting log opcode/tag, and (b) correctly encoding the message body (set body-in-ref tag to 1 when storing `log` as a ref), or alternatively ignoring self-sent log messages in recv_internal before parsing.

## Recommendation

- Use a dedicated log opcode/tag that does not collide with any executable opcodes handled by recv_internal (in particular, do not reuse OP_EXECUTE_MINT / 0x4d494e54).
- Encode the internal message body correctly: if storing the log as a reference, set the body-in-ref tag bit to 1 and store only the reference; if storing inline, set the tag bit to 0 and include the bits inline. Do not set the tag to 0 when the body is actually a ref.
- In recv_internal, add an early guard to ignore self-addressed log messages before any opcode parsing. Check sender == my_address() (and/or a distinct log tag) and return without parsing or executing.
- Harden parsing: before reading opcode/fields, verify there are sufficient bits; if the body-in-ref tag indicates a reference, load from the reference before parsing.
- Ensure log messages are sent with minimal value and parameters that avoid fee amplification on unexpected failures.

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
