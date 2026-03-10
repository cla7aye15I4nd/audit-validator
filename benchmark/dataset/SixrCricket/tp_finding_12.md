# Mint-triggering burn event and stats are emitted/updated without confirming burn success (bounced burn still looks like a successful bridge)


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `c0b155c0-ce9d-11f0-afef-b3f141791562` |
| Commit | `20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856` |

## Location

- **Local path:** `./source_code/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-vault.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-vault.fc
- **Lines:** 1–1

## Description

In handle_jetton_notification, the contract updates total_burned/total_fees and emits the mint-triggering “BURN” log immediately after sending the burn message, even though TON message delivery/execution is asynchronous and the burn may later fail and bounce (e.g., unexpected jetton wallet behavior, insufficient attached gas, or formatting mismatch). If the burn fails, recv_internal’s bounced-message branch only emits a generic “BNCE” log and does not revert/compensate the already-emitted “BURN” event or the updated stats, leaving incorrect accounting and enabling off-chain watchers (per comments) to mint on EVM based on “BURN” despite no TON-side burn, resulting in unbacked EVM mints. Correlation is further weakened because query_id is always 0 and bounce parsing ignores it, so watchers cannot reliably tie a bounce to a specific deposit and reject the earlier “BURN.” The design should emit the mint-triggering event only after an on-chain proof of successful burn (e.g., a burn confirmation/notification from the jetton wallet/root) and/or defer stats updates until confirmation; additionally, use a nonzero unique query_id (e.g., propagate the notification’s query_id) and/or maintain a pending-burn state that is finalized only upon success so failures can be deterministically detected and handled.

## Recommendation

- Emit the mint-triggering event only after receiving an on-chain confirmation of a successful burn from the expected jetton wallet/root. Do not treat the initial send as success.
- Defer updates to total_burned and total_fees until confirmation. If a failure/bounce occurs, no accounting changes should persist.
- Assign a nonzero, unique query_id to each burn (e.g., propagated from the original notification) and include it in all related messages/logs. Reject any confirmation/bounce that does not match the expected query_id and sender.
- Maintain a pending-burn record keyed by query_id (and relevant context such as wallet/root, sender, amount). On success, finalize the record, update stats, and emit the mint-triggering “BURN.” On bounce/failure, remove the record and emit an explicit failure log (e.g., “BNCE”/“BURN_FAILED”).
- Make finalization idempotent and prevent double processing of the same query_id.
- If backward compatibility with existing watchers is needed, introduce a non-mint-triggering “request” log for traceability and reserve “BURN” exclusively for confirmed burns. Update watcher documentation to mint only on the confirmed event.
- Validate the origin and format of confirmation messages and handle unexpected or malformed replies by failing the pending burn.
- Ensure sufficient attached gas for the burn and its confirmation/bounce path so that failures are observable and properly handled.

## Vulnerable Code

```
() recv_internal(int msg_value, cell in_msg_full, slice in_msg_body) impure {
    ;; Parse message
    if (in_msg_body.slice_empty?()) {
        return ();  ;; Ignore empty messages (simple TON transfers)
    }

    ;; Load sender address and check bounce flag
    slice cs = in_msg_full.begin_parse();
    int flags = cs~load_uint(4);
    int is_bounced = flags & 1;  ;; First bit indicates bounced message
    slice sender_address = cs~load_msg_addr();

    ;; Handle bounced messages (failed operations)
    if (is_bounced) {
        ;; Bounced message format: op (32 bits) + original message body
        ;; We log this for monitoring but don't fail
        ;; Fee transfers may bounce if fee_wallet is not a valid jetton wallet
        in_msg_body~skip_bits(32);  ;; Skip 0xffffffff bounce prefix

        ;; Try to parse original op if available
        if (~ in_msg_body.slice_empty?()) {
            int original_op = in_msg_body~load_uint(32);

            ;; Log bounce event for monitoring
            cell bounce_log = begin_cell()
                .store_uint(0x424e4345, 32)          ;; "BNCE" - bounce_log tag
                .store_slice(sender_address)         ;; who sent the bounce
                .store_uint(original_op, 32)         ;; original operation that failed
                .store_uint(msg_value, 64)           ;; returned gas
                .store_uint(now(), 64)               ;; timestamp
            .end_cell();

            send_raw_message(begin_cell()
                .store_uint(0x10, 6)                 ;; nobounce
                .store_slice(my_address())
                .store_coins(GAS_FOR_LOG)
                .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
                .store_ref(bounce_log)
            .end_cell(), 1);
        }

        return ();  ;; Don't process bounced messages further
    }

    ;; Load data
    load_data();

    ;; Parse operation
    int op = in_msg_body~load_uint(32);

    ;; Handle jetton transfer notification
    if (op == OP_JETTON_TRANSFER_NOTIFICATION) {
        int query_id = in_msg_body~load_uint(64);
        int jetton_amount = in_msg_body~load_coins();
        slice from_address = in_msg_body~load_msg_addr();
        ;; forward_payload is optional, we ignore it for now

        ;; sender_address is the jetton wallet that sent us this notification
        ;; We validate that it belongs to our allowed jetton
        ;; For now we trust the sender, but in production you should verify
        ;; by deriving expected jetton wallet address from jetton root

        handle_jetton_notification(
            sender_address,
            jetton_amount,
            from_address,
            sender_address  ;; jetton wallet = sender of notification
        );
        return ();
    }

    ;; Handle governance operations
    if (op == OP_SET_FEE_WALLET) {
        slice new_fee_wallet = in_msg_body~load_msg_addr();
        set_fee_wallet(sender_address, new_fee_wallet);
        return ();
    }

    if (op == OP_SET_FEE_BASIS_POINTS) {
        int new_fee_basis_points = in_msg_body~load_uint(16);
        set_fee_basis_points(sender_address, new_fee_basis_points);
        return ();
    }

    if (op == OP_SET_ADMIN) {
        slice new_admin = in_msg_body~load_msg_addr();
        set_admin(sender_address, new_admin);
        return ();
    }

    if (op == OP_SET_ALLOWED_JETTON) {
        slice new_jetton = in_msg_body~load_msg_addr();
        set_allowed_jetton(sender_address, new_jetton);
        return ();
    }

    if (op == OP_WITHDRAW_TON) {
        slice destination = in_msg_body~load_msg_addr();
        int amount = in_msg_body~load_coins();
        withdraw_ton(sender_address, destination, amount);
        return ();
    }

    ;; Unknown operation - ignore
    return ();
}
```
