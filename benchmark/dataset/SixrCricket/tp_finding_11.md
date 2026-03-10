# Unauthenticated jetton transfer notifications let anyone force TON payouts to an arbitrary “jetton_wallet”


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex, aiflow_scanner_smart |
| Scan Model | gpt-5.2 |
| Project ID | `c0b155c0-ce9d-11f0-afef-b3f141791562` |
| Commit | `20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856` |

## Location

- **Local path:** `./src/contracts/ton/bridge-vault.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-vault.fc
- **Lines:** 1–1

## Description

The vault/bridge contract has a critical authentication/logic flaw in `recv_internal`/`handle_jetton_notification`: any internal message whose first 32 bits equal `OP_JETTON_TRANSFER_NOTIFICATION` (`0x7362d09c`) is treated as a legitimate jetton transfer, with `jetton_amount` and `from_address` trusted directly from the message body and `sender_address` implicitly used as the `jetton_wallet`, while there is no on-chain verification that the sender is the vault’s deterministic Jetton Wallet for the configured `allowed_jetton` (derived from the Jetton Root and `my_address()`), nor that the notification corresponds to a real transfer. Although `set_allowed_jetton` sets the Jetton Root, it does not compute/persist the corresponding wallet address/code needed for validation, and `validate_jetton` (which only checks `equal_slices(jetton_root, allowed_jetton)`) is unused—so `allowed_jetton` is effectively unenforced and any contract can spoof a `transfer_notification`. An unprivileged attacker can deploy a fake “jetton wallet” (or even a non-jetton contract / worthless custom jetton) and send crafted notifications with arbitrary `query_id`, exaggerated `amount` (e.g., 1,000,000) to satisfy `jetton_amount > 0` and force the vault to compute `fee_amount`/`burn_amount`, update `total_burned`/`total_fees`, and emit `DEPO` and an official `BURN` log/event via `send_raw_message` (bridge watchers/relayers explicitly rely on this “BURN” log—“Watchers listen for this to trigger EVM mint”), enabling minting of unbacked assets on the destination/EVM chain even if subsequent outbound calls bounce. Additionally, the contract unconditionally sends value-bearing outbound messages to the attacker-controlled `sender_address` as `jetton_wallet`, including `send_jetton_burn(jetton_wallet, burn_amount)` attaching `GAS_FOR_JETTON_BURN` (0.05 TON) and, when `fee_amount > 0` and `fee_wallet` is set, `send_jetton_transfer(jetton_wallet, fee_wallet, ...)` attaching `GAS_FOR_JETTON_TRANSFER` (0.08 TON); because `send_jetton_transfer` always attaches 0.08 TON to the provided address and the attacker can accept/bypass bounces, repeated forged notifications can drain the vault’s TON balance and DoS bridge operations. The fix is to authenticate notifications by strictly requiring `msg.sender`/`sender_address` equals the expected vault jetton-wallet for `(allowed_jetton, owner=my_address())` (derive via standard wallet-address derivation / `get_wallet_address` or store the expected wallet address in state and `throw_unless` it matches), apply this check before processing/logging and before calling `send_jetton_transfer`/burn (optionally hard-assert inside `send_jetton_transfer`), and optionally include the jetton root/wallet in emitted events so off-chain watchers can independently validate the asset.

## Recommendation

- Authenticate jetton notifications. On every recv_internal/handle_jetton_notification with OP_JETTON_TRANSFER_NOTIFICATION (0x7362d09c), require msg.sender (sender_address) to equal the deterministic Jetton Wallet for (allowed_jetton, owner = my_address()). Derive this wallet via the Jetton Root’s standard get_wallet_address and persist it in state; throw unless it matches.
- Enforce the check before any state changes, logging, or outbound messages. Do not read jetton_amount/from_address, update totals, emit DEPO/BURN, or call send_jetton_burn/send_jetton_transfer until the sender is authenticated.
- Make set_allowed_jetton compute and store the expected wallet address (and, if needed, wallet code hash/version) for the new root. Reject unset/zero roots. If multiple roots are supported, store and validate against the corresponding computed wallet for each.
- Remove or repurpose validate_jetton so it actually gates processing by the stored allowed_jetton and its computed wallet; do not rely on equal_slices alone.
- Harden outbound calls. Ensure send_jetton_burn/send_jetton_transfer only accept the stored expected wallet (not the incoming sender), and hard-assert inside these routines that the wallet parameter equals the stored address. Attach only the minimum gas required, and set messages to bounce where appropriate.
- Validate message shape. Confirm the body conforms to the Jetton transfer_notification layout and that jetton_amount > 0, but never trust amounts or from_address from unauthenticated senders.
- Strengthen observability. Include allowed_jetton (root) and the authenticated jetton_wallet in emitted events so off-chain watchers can verify that burns originate from the correct wallet and asset.
- Fail closed. If the expected wallet is not initialized or derivation fails, reject notifications and skip event emission and outbound transfers.

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

## Related Context

```
load_data -> () load_data() impure {
    slice ds = get_data().begin_parse();
    admin = ds~load_msg_addr();
    fee_wallet = ds~load_msg_addr();
    allowed_jetton = ds~load_msg_addr();
    fee_basis_points = ds~load_uint(16);

    ;; Load stats from reference cell
    slice stats = ds~load_ref().begin_parse();
    total_burned = stats~load_uint(128);
    total_fees = stats~load_uint(128);
}

handle_jetton_notification -> () handle_jetton_notification(
    slice sender_address,      ;; Who sent jettons to us
    int jetton_amount,         ;; Amount received
    slice from_address,        ;; Original sender (user)
    slice jetton_wallet        ;; Our jetton wallet address (sender of notification)
) impure {
    ;; Validate amount is sufficient for fee + burn
    throw_unless(ERR_INSUFFICIENT_AMOUNT, jetton_amount > 0);

    ;; Calculate fee and burn amounts
    int fee_amount = calculate_fee(jetton_amount);
    int burn_amount = jetton_amount - fee_amount;

    ;; Log the deposit event BEFORE processing
    ;; This ensures watchers can track even if subsequent operations fail
    cell deposit_log = begin_cell()
        .store_uint(0x4445504f, 32)          ;; "DEPO" - deposit_log tag
        .store_slice(from_address)           ;; original sender
        .store_uint(jetton_amount, 128)      ;; total amount
        .store_uint(fee_amount, 128)         ;; fee amount
        .store_uint(burn_amount, 128)        ;; burn amount
        .store_uint(now(), 64)               ;; timestamp
    .end_cell();

    send_raw_message(begin_cell()
        .store_uint(0x10, 6)                 ;; nobounce
        .store_slice(my_address())
        .store_coins(GAS_FOR_LOG)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .store_ref(deposit_log)
    .end_cell(), 1);

    ;; Transfer fee to fee wallet (if fee > 0 AND fee_wallet is configured)
    ;; This prevents bounce errors (exit 709) if fee_wallet is not initialized
    if ((fee_amount > 0) & is_fee_wallet_configured()) {
        send_jetton_transfer(
            jetton_wallet,
            fee_wallet,
            fee_amount,
            10000000  ;; 0.01 TON forward for notification
        );
    }

    ;; Burn remaining amount
    send_jetton_burn(jetton_wallet, burn_amount);

    ;; Update stats
    total_burned = total_burned + burn_amount;
    total_fees = total_fees + fee_amount;
    save_data();

    ;; Emit burn event for watchers
    ;; Watchers listen for this to trigger EVM mint
    cell burn_log = begin_cell()
        .store_uint(0x4255524e, 32)          ;; "BURN" - burn_log tag
        .store_slice(from_address)           ;; user who initiated bridge
        .store_uint(burn_amount, 128)        ;; amount to mint on EVM (99%)
        .store_uint(fee_amount, 128)         ;; fee collected (1%)
        .store_uint(jetton_amount, 128)      ;; original amount (100%)
        .store_uint(now(), 64)               ;; timestamp
    .end_cell();

    send_raw_message(begin_cell()
        .store_uint(0x10, 6)                 ;; nobounce
        .store_slice(my_address())
        .store_coins(GAS_FOR_LOG)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .store_ref(burn_log)
    .end_cell(), 1);
}

set_fee_wallet -> () set_fee_wallet(slice sender, slice new_fee_wallet) impure {
    throw_unless(ERR_UNAUTHORIZED, is_admin(sender));

    ;; Validate new fee wallet is not null
    throw_if(ERR_INVALID_FEE_WALLET, new_fee_wallet.slice_empty?());

    slice old_fee_wallet = fee_wallet;
    fee_wallet = new_fee_wallet;
    save_data();

    ;; Emit log
    cell log = begin_cell()
        .store_uint(0x46454557, 32)          ;; fee_wallet_updated_log tag
        .store_slice(old_fee_wallet)
        .store_slice(new_fee_wallet)
        .store_uint(now(), 64)
    .end_cell();

    send_raw_message(begin_cell()
        .store_uint(0x10, 6)
        .store_slice(my_address())
        .store_coins(GAS_FOR_LOG)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .store_ref(log)
    .end_cell(), 1);
}

set_fee_basis_points -> () set_fee_basis_points(slice sender, int new_fee_basis_points) impure {
    throw_unless(ERR_UNAUTHORIZED, is_admin(sender));

    ;; Validate fee basis points range (0 to MAX_FEE_BASIS_POINTS)
    throw_unless(ERR_INVALID_FEE_BASIS_POINTS, new_fee_basis_points >= 0);
    throw_unless(ERR_INVALID_FEE_BASIS_POINTS, new_fee_basis_points <= MAX_FEE_BASIS_POINTS);

    int old_fee_basis_points = fee_basis_points;
    fee_basis_points = new_fee_basis_points;
    save_data();

    ;; Emit log
    cell log = begin_cell()
        .store_uint(0x46454250, 32)          ;; fee_basis_points_updated_log tag ("FEBP")
        .store_uint(old_fee_basis_points, 16)
        .store_uint(new_fee_basis_points, 16)
        .store_uint(now(), 64)
    .end_cell();

    send_raw_message(begin_cell()
        .store_uint(0x10, 6)
        .store_slice(my_address())
        .store_coins(GAS_FOR_LOG)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .store_ref(log)
    .end_cell(), 1);
}

set_admin -> () set_admin(slice sender, slice new_admin) impure {
    throw_unless(ERR_UNAUTHORIZED, is_admin(sender));

    slice old_admin = admin;
    admin = new_admin;
    save_data();

    ;; Emit log
    cell log = begin_cell()
        .store_uint(0x41444d4e, 32)          ;; admin_updated_log tag
        .store_slice(old_admin)
        .store_slice(new_admin)
        .store_uint(now(), 64)
    .end_cell();

    send_raw_message(begin_cell()
        .store_uint(0x10, 6)
        .store_slice(my_address())
        .store_coins(GAS_FOR_LOG)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .store_ref(log)
    .end_cell(), 1);
}

set_allowed_jetton -> () set_allowed_jetton(slice sender, slice new_jetton) impure {
    throw_unless(ERR_UNAUTHORIZED, is_admin(sender));

    slice old_jetton = allowed_jetton;
    allowed_jetton = new_jetton;
    save_data();

    ;; Emit log
    cell log = begin_cell()
        .store_uint(0x414c4c57, 32)          ;; jetton_updated_log tag
        .store_slice(old_jetton)
        .store_slice(new_jetton)
        .store_uint(now(), 64)
    .end_cell();

    send_raw_message(begin_cell()
        .store_uint(0x10, 6)
        .store_slice(my_address())
        .store_coins(GAS_FOR_LOG)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .store_ref(log)
    .end_cell(), 1);
}

withdraw_ton -> () withdraw_ton(slice sender, slice destination, int amount) impure {
    throw_unless(ERR_UNAUTHORIZED, is_admin(sender));

    ;; Validate destination address is not null
    throw_if(ERR_INVALID_WITHDRAW_AMOUNT, destination.slice_empty?());

    ;; Validate amount is positive
    throw_unless(ERR_INVALID_WITHDRAW_AMOUNT, amount > 0);

    ;; Get current contract balance
    ;; We need to keep MIN_TON_RESERVE for contract operations
    int current_balance = get_balance().pair_first();
    int available_balance = current_balance - MIN_TON_RESERVE;

    ;; Check if we have enough balance
    throw_unless(ERR_INSUFFICIENT_BALANCE, available_balance >= amount);

    ;; Send TON to destination
    send_raw_message(begin_cell()
        .store_uint(0x18, 6)                     ;; bounceable
        .store_slice(destination)
        .store_coins(amount)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)  ;; no extras
    .end_cell(), 1);  ;; mode = 1 (pay fees separately)

    ;; Emit log
    cell log = begin_cell()
        .store_uint(0x57495448, 32)          ;; withdraw_log tag ("WITH")
        .store_slice(destination)
        .store_coins(amount)
        .store_uint(now(), 64)
    .end_cell();

    send_raw_message(begin_cell()
        .store_uint(0x10, 6)                 ;; nobounce
        .store_slice(my_address())
        .store_coins(GAS_FOR_LOG)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .store_ref(log)
    .end_cell(), 1);
}
```
