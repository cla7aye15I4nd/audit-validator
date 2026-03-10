# Unconditional 48-bit opcode peek lets any short-body internal message revert the receiver (DoS via message spam)


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

- **Local path:** `./source_code/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc
- **Lines:** 1–1

## Description

The contract’s `recv_internal` unconditionally executes `in_msg_body.preload_uint(48)` for every non-empty internal message before determining whether the opcode is a 48-bit withdraw or a 32-bit mint/governance/comment-style format. In TVM/FunC, `preload_uint(n)` throws if the slice has fewer than `n` bits; because the code only checks `slice_empty?()` and does not verify the body has at least 48 bits, any internal message with a 1–47 bit body (including common 32-bit “comment op” headers with no text) causes a slice underflow and an immediate compute-phase abort instead of the intended “Unknown operation – ignore,” potentially breaking benign top-ups. This is exploitable as a low-cost griefing/DoS vector: a non-privileged attacker can repeatedly send tiny malformed internal messages (e.g., `begin_cell().store_uint(0, 32).end_cell()` or even `store_uint(1, 1)`) with sufficient `msg_value`, forcing repeated compute failures at `preload_uint(48)` and creating sustained processing load/backlog that delays legitimate bridge operations (mint/governance/withdraw) without any watcher/governance signatures. No state changes occur, but each failing message still consumes execution resources/fees and can be spammed. Mitigation is to check `slice_bits(in_msg_body)` before preloading/loading (e.g., return early if `< 32`, and only attempt 48-bit withdraw parsing when `slice_bits >= 48`).

## Recommendation

- In recv_internal, never call preload/load with a width greater than the body’s remaining bits. Check slice_bits(in_msg_body) before any peek/read.
- Treat 0-bit bodies as benign top-ups and return early.
- If slice_bits < 32, ignore the message and return without side effects.
- Only attempt 48-bit withdraw opcode parsing when slice_bits >= 48. Otherwise, classify as unknown and ignore.
- For 32-bit op formats (mint/governance/comment), require slice_bits >= 32 before peeking; then verify the opcode and ensure the remaining fields have sufficient bits before reading.
- On unknown, malformed, or too-short bodies, return gracefully (no throw/bounce/revert) so the contract cannot be griefed via compute aborts.
- Apply the same length-guard pattern to all message-parsing paths that inspect opcodes.
- Add tests covering empty bodies and 1–47 bit bodies (including 32-bit headers with no payload) to confirm no aborts and correct no-op handling.

## Vulnerable Code

```
() recv_internal(int msg_value, cell in_msg_full, slice in_msg_body) impure {
    ;; Parse message
    if (in_msg_body.slice_empty?()) {
        return ();  ;; Ignore empty messages (simple transfers)
    }

    ;; For WITHDRAW_TON_FUNDS, op is 48 bits instead of 32
    ;; We need to peek first to determine which op code format to use
    int first_bits = in_msg_body.preload_uint(48);

    if (first_bits == OP_EXECUTE_WITHDRAW_TON) {
        ;; Parse withdraw message: op:uint48 destination:MsgAddressInt amount:uint128 reference:uint64 signatures:^Cell
        in_msg_body~load_uint(48);  ;; consume op
        slice destination = in_msg_body~load_msg_addr();
        int amount = in_msg_body~load_uint(128);
        int reference = in_msg_body~load_uint(64);
        cell signatures = in_msg_body~load_ref();

        execute_withdraw_ton_funds(destination, amount, reference, signatures);
        return ();
    }

    ;; For other operations, use standard 32-bit op code
    int op = in_msg_body~load_uint(32);

    if (op == OP_EXECUTE_MINT) {
        ;; Parse mint message: origin_chain_id:uint32 token:bits256 ton_recipient:MsgAddressInt amount:uint128 nonce:uint64 epoch:uint64 signatures:^Cell
        int origin_chain_id = in_msg_body~load_uint(32);
        int token = in_msg_body~load_uint(256);
        slice ton_recipient = in_msg_body~load_msg_addr();
        int amount = in_msg_body~load_uint(128);
        int nonce = in_msg_body~load_uint(64);
        int epoch = in_msg_body~load_uint(64);
        cell signatures = in_msg_body~load_ref();

        execute_mint(origin_chain_id, token, ton_recipient, amount, nonce, epoch, signatures);
        return ();
    }

    if (op == OP_EXECUTE_GOVERNANCE) {
        ;; Parse governance message: action_type:uint32 nonce:uint64 epoch:uint64 payload:^Cell signatures:^Cell
        int action_type = in_msg_body~load_uint(32);
        int nonce = in_msg_body~load_uint(64);
        int epoch = in_msg_body~load_uint(64);
        cell payload_ref = in_msg_body~load_ref();
        cell signatures = in_msg_body~load_ref();

        execute_governance_action(action_type, nonce, epoch, payload_ref, signatures);
        return ();
    }

    ;; Unknown operation - ignore
    return ();
}
```

## Related Context

```
execute_withdraw_ton_funds -> () execute_withdraw_ton_funds(slice destination, int amount, int reference, cell signatures) impure {
    ;; Load state
    load_data();

    ;; Validate destination address format
    validate_destination_address(destination);

    ;; Check reference hasn't been used (replay protection)
    throw_if(ERR_PAYLOAD_CONSUMED, is_reference_consumed(reference));

    ;; Hash the withdrawal payload
    int withdraw_hash = hash_withdraw_ton_funds_action(destination, amount, reference);

    ;; Validate governance signatures (3-of-5 threshold)
    validate_governance_signatures(withdraw_hash, signatures);

    ;; Get current contract balance
    [int balance, _] = get_balance();

    ;; Ensure contract has enough balance
    throw_unless(ERR_INSUFFICIENT_BALANCE, balance >= amount);

    ;; Mark reference as consumed
    mark_reference_consumed(reference);

    ;; Save state before sending (to prevent reentrancy issues)
    save_data();

    ;; Send TON to destination address
    ;; Using mode 1 (pay transfer fees separately) to ensure exact amount is sent
    cell msg_body = begin_cell()
        .store_uint(0, 32)  ;; Simple transfer, no op code
        .store_slice("TON withdrawal via multisig governance")  ;; Optional comment
    .end_cell();

    send_raw_message(begin_cell()
        .store_uint(0x18, 6)                ;; bounceable flag
        .store_slice(destination)
        .store_coins(amount)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .store_ref(msg_body)
    .end_cell(), 1);

    ;; Emit withdrawal log
    cell log = begin_cell()
        .store_uint(0x574452415720, 48)     ;; ton_funds_withdrawn_log tag
        .store_slice(destination)
        .store_uint(amount, 128)
        .store_uint(reference, 64)
        .store_uint(now(), 64)
    .end_cell();

    send_raw_message(begin_cell()
        .store_uint(0x10, 6)                ;; nobounce
        .store_slice(my_address())
        .store_coins(GAS_FOR_LOG)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .store_ref(log)
    .end_cell(), 1);
}

execute_mint -> () execute_mint(int origin_chain_id, int token, slice ton_recipient, int amount, int nonce, int epoch, cell signatures) impure {
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

execute_governance_action -> () execute_governance_action(int action_type, int nonce, int epoch, cell payload_ref, cell signatures) impure {
    ;; Load state
    load_data();

    ;; Verify epoch matches current epoch (prevents replay of old signatures after rotation)
    throw_unless(ERR_INVALID_NONCE, epoch == governance_epoch);

    ;; Verify nonce (strictly incremental)
    throw_unless(ERR_INVALID_NONCE, nonce == governance_nonce + 1);

    ;; Hash the governance action (includes epoch)
    int action_hash = hash_governance_action(action_type, nonce, epoch, payload_ref);

    ;; Validate governance signatures
    validate_governance_signatures(action_hash, signatures);

    ;; Update governance nonce
    governance_nonce = nonce;

    ;; Execute action based on type
    slice payload = payload_ref.begin_parse();

    if (action_type == ACTION_UPDATE_WATCHERS) {
        update_watchers(payload);
        governance_epoch += 1;  ;; Increment epoch on watcher rotation
    }
    elseif (action_type == ACTION_UPDATE_GOVERNANCE) {
        update_governance(payload);
        governance_epoch += 1;  ;; Increment epoch on governance rotation
    }
    elseif (action_type == ACTION_SET_TOKEN_STATUS) {
        set_token_status(payload);
    }
    elseif (action_type == ACTION_TRANSFER_TOKEN_OWNER) {
        transfer_token_ownership(payload);
    }
    elseif (action_type == ACTION_MAP_TOKEN) {
        map_token(payload);
    }
    elseif (action_type == ACTION_SET_MINT_NONCE) {
        set_mint_nonce(payload);
    }
    elseif (action_type == ACTION_SET_VAULT_FEE_RECIPIENT) {
        set_vault_fee_recipient(payload);
    }
    elseif (action_type == ACTION_SET_VAULT_FEE_BASIS_POINTS) {
        set_vault_fee_basis_points(payload);
    }
    else {
        throw(ERR_INVALID_ACTION);
    }

    ;; Save state
    save_data();
}
```
