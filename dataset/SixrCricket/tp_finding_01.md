# Permanent Governance Lockout due to Unhandled Cell Overflow in Rotation Functions


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex, aiflow_scanner_smart |
| Scan Model | gemini-3-pro-preview |
| Project ID | `c0b155c0-ce9d-11f0-afef-b3f141791562` |
| Commit | `20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856` |

## Location

- **Local path:** `./src/contracts/ton/bridge-multisig.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc
- **Lines:** 1–1

## Description

The `update_watchers` and `update_governance` governance actions are effectively non-functional due to incorrect assumptions about TON/TVM cell bit limits and slice parsing across referenced cells. Both functions expect a payload containing a 32-bit tag plus five inline 256-bit public keys (32 + 5×256 = 1312 bits), which cannot fit in a single ordinary cell (1023-bit max), so any valid on-chain encoding must split data across a root cell and referenced child cell(s); however, these functions parse with sequential `load_uint` calls on `payload_ref.begin_parse()` and contain no logic to follow references (unlike `validate_governance_signatures`, which explicitly handles referenced cells), so they can read at most the first three keys (800 bits) and then inevitably trigger a cell underflow when attempting to load the fourth key (only up to 223 bits remain in the root slice). In addition, `update_watchers` attempts to construct an event log cell that inlines even more data—32-bit tag, five 256-bit keys, a 64-bit governance nonce, and a 64-bit timestamp (1440 bits total)—which will overflow the cell builder (e.g., after tag + `w1`–`w4` reaches 1056 bits) and abort with a TVM cell overflow exception (exit code 8), reverting all state changes (including leaving the watcher set unchanged and preventing `governance_epoch` increment). A governance action signed to quorum and executed via `execute_governance_action`/`OP_EXECUTE_GOVERNANCE` will therefore always revert after signature verification when parsing/logging is attempted, permanently freezing watcher/governance key rotation and creating a critical denial of service to recovery/security (e.g., compromised or inactive keys cannot be replaced, potentially undermining bridge liveness and enabling continued authorization by a compromised set). Fixes require redesigning payload/log encoding to fit within 1023 bits (e.g., storing keys in referenced cells with explicit ref-aware parsing) or logging only a hash of the new key set rather than all keys inline.

## Recommendation

- Redesign the payload and log formats to respect TVM cell limits.
  - Encode the five 256-bit keys in referenced cell(s) rather than inline. The root payload cell should contain the 32-bit tag (and any metadata) plus a reference to a canonicalized keys cell/tree.
  - Update parsing in update_watchers and update_governance to be reference-aware (consistent with validate_governance_signatures), traversing referenced cells to read all five keys.
  - Before any load operation, explicitly check that the remaining bits/refs can satisfy the read; reject invalid/truncated payloads without throwing.

- Fix event emission to avoid builder overflow.
  - Either log only compact data (e.g., tag, nonce, timestamp, and a 256-bit hash of the keys cell) or construct the event as a tree with keys stored in referenced cells. Ensure the root event cell stays within 1023 bits.

- Align the signature domain with the new encoding.
  - Verify signatures over the hash of the canonical payload root cell (including refs), or over an explicit keys_hash included in the payload. Ensure validate_governance_signatures and the update functions consume the exact same message/data.

- Provide a clear upgrade path.
  - Introduce versioned/opcode variants (e.g., V2) for the new reference-aware layout and disable the legacy inline layout to prevent ambiguity. Reject old-format payloads rather than attempting to parse them.

- Add defensive validation.
  - Enforce exactly five distinct 256-bit keys; validate nonce monotonicity and any timestamp constraints before state changes.
  - Fail fast with explicit error codes on size/format mismatches; never rely on TVM underflow/overflow to signal errors.

- Extend tests.
  - Positive tests for multi-cell payloads and event logs that traverse refs without underflow/overflow.
  - Negative tests for truncated/ill-formed cells and oversized logs.
  - Property/fuzz tests that vary slice/ref boundaries to ensure robustness.

## Vulnerable Code

```
() execute_governance_action(int action_type, int nonce, int epoch, cell payload_ref, cell signatures) impure {
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

hash_governance_action -> int hash_governance_action(int action_type, int nonce, int epoch, cell payload_ref) inline {
    cell action = begin_cell()
        .store_uint(0x474f5645, 32)         ;; governance_action tag
        .store_uint(action_type, 32)
        .store_uint(nonce, 64)
        .store_uint(epoch, 64)
        .store_ref(payload_ref)
    .end_cell();
    return cell_hash(action);
}

validate_governance_signatures -> () validate_governance_signatures(int hash, cell signatures_cell) impure inline {
    slice signatures = signatures_cell.begin_parse();

    ;; Track which governance members have signed (bitmap)
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
        int signer_index = verify_signature_in_set(hash, pubkey, sig_hi, sig_lo, governance, GOVERNANCE_COUNT);

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
    throw_unless(ERR_THRESHOLD_NOT_MET, signature_count >= GOVERNANCE_THRESHOLD);
}

update_watchers -> () update_watchers(slice payload) impure {
    ;; Parse update_watchers_payload#57415443 watcher_1:bits256 ... watcher_5:bits256
    throw_unless(ERR_INVALID_ACTION, payload~load_uint(32) == 0x57415443);

    int w1 = payload~load_uint(256);
    int w2 = payload~load_uint(256);
    int w3 = payload~load_uint(256);
    int w4 = payload~load_uint(256);
    int w5 = payload~load_uint(256);

    ;; Create new watcher dictionary
    cell new_watchers = new_dict();
    new_watchers = set_pubkey(new_watchers, 0, w1);
    new_watchers = set_pubkey(new_watchers, 1, w2);
    new_watchers = set_pubkey(new_watchers, 2, w3);
    new_watchers = set_pubkey(new_watchers, 3, w4);
    new_watchers = set_pubkey(new_watchers, 4, w5);

    watchers = new_watchers;

    ;; Emit log
    cell log = begin_cell()
        .store_uint(0x57415443, 32)         ;; watcher_set_updated_log tag
        .store_uint(w1, 256)
        .store_uint(w2, 256)
        .store_uint(w3, 256)
        .store_uint(w4, 256)
        .store_uint(w5, 256)
        .store_uint(governance_nonce, 64)
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

update_governance -> () update_governance(slice payload) impure {
    ;; Parse update_governance_payload#474f5653
    throw_unless(ERR_INVALID_ACTION, payload~load_uint(32) == 0x474f5653);

    int g1 = payload~load_uint(256);
    int g2 = payload~load_uint(256);
    int g3 = payload~load_uint(256);
    int g4 = payload~load_uint(256);
    int g5 = payload~load_uint(256);

    ;; Create new governance dictionary
    cell new_governance = new_dict();
    new_governance = set_pubkey(new_governance, 0, g1);
    new_governance = set_pubkey(new_governance, 1, g2);
    new_governance = set_pubkey(new_governance, 2, g3);
    new_governance = set_pubkey(new_governance, 3, g4);
    new_governance = set_pubkey(new_governance, 4, g5);

    governance = new_governance;

    ;; Emit log
    cell log = begin_cell()
        .store_uint(0x474f5653, 32)         ;; governance_set_updated_log tag
        .store_uint(g1, 256)
        .store_uint(g2, 256)
        .store_uint(g3, 256)
        .store_uint(g4, 256)
        .store_uint(g5, 256)
        .store_uint(governance_nonce, 64)
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

set_token_status -> () set_token_status(slice payload) impure {
    ;; Parse set_token_status_payload#544f4b53 jetton_root:MsgAddressInt status:uint1
    throw_unless(ERR_INVALID_ACTION, payload~load_uint(32) == 0x544f4b53);

    slice jetton_root = payload~load_msg_addr();
    int status = payload~load_uint(1);

    ;; Skip if no change
    int current_status = is_jetton_allowed(jetton_root);
    if (current_status == status) {
        return ();
    }

    set_jetton_allowed(jetton_root, status);

    ;; Emit log (includes old status for SCB-11)
    cell log = begin_cell()
        .store_uint(0x544f4b53, 32)         ;; token_status_updated_log tag
        .store_slice(jetton_root)
        .store_uint(current_status, 1)      ;; old status
        .store_uint(status, 1)              ;; new status
        .store_uint(governance_nonce, 64)
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

transfer_token_ownership -> () transfer_token_ownership(slice payload) impure {
    ;; Parse transfer_token_owner_payload#5452414e jetton_root:MsgAddressInt new_owner:MsgAddressInt
    throw_unless(ERR_INVALID_ACTION, payload~load_uint(32) == 0x5452414e);

    slice jetton_root = payload~load_msg_addr();
    slice new_owner = payload~load_msg_addr();

    ;; Send transfer_ownership message to jetton root
    ;; Op code for jetton ownership transfer (TEP-74 standard)
    ;; Body is small enough to store inline (op:32 + query_id:64 + address:~267 = ~363 bits)
    send_raw_message(begin_cell()
        .store_uint(0x18, 6)                ;; bounceable
        .store_slice(jetton_root)
        .store_coins(GAS_FOR_JETTON_MINT)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1) ;; no init, no extra currencies
        .store_uint(0, 1)                   ;; body inline (not in ref)
        .store_uint(OP_TRANSFER_OWNERSHIP, 32)
        .store_uint(0, 64)                  ;; query_id
        .store_slice(new_owner)
    .end_cell(), 1);

    ;; Emit log
    cell log = begin_cell()
        .store_uint(0x5452414e, 32)         ;; token_ownership_transferred_log tag
        .store_slice(jetton_root)
        .store_slice(new_owner)
        .store_uint(governance_nonce, 64)
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

map_token -> () map_token(slice payload) impure {
    ;; Parse map_token_payload#4d415054 evm_token:bits256 ton_jetton_root:MsgAddressInt
    throw_unless(ERR_INVALID_ACTION, payload~load_uint(32) == 0x4d415054);

    int evm_token = payload~load_uint(256);
    slice ton_jetton_root = payload~load_msg_addr();

    ;; Check if mapping already exists and is the same
    (slice existing_mapping, int found) = get_token_mapping(evm_token);
    if (found) {
        if (equal_slices(existing_mapping, ton_jetton_root)) {
            return ();  ;; Skip if no change
        }
    }

    ;; Set the mapping
    set_token_mapping(evm_token, ton_jetton_root);

    ;; Emit log
    cell log = begin_cell()
        .store_uint(0x4d415054, 32)         ;; token_mapped_log tag
        .store_uint(evm_token, 256)
        .store_slice(ton_jetton_root)
        .store_uint(governance_nonce, 64)
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

set_mint_nonce -> () set_mint_nonce(slice payload) impure {
    ;; Parse set_mint_nonce_payload#534d4e43 new_mint_nonce:uint64
    throw_unless(ERR_INVALID_ACTION, payload~load_uint(32) == 0x534d4e43);

    int new_mint_nonce = payload~load_uint(64);

    ;; Skip if no change
    int old_mint_nonce = mint_nonce;
    if (old_mint_nonce == new_mint_nonce) {
        return ();
    }

    ;; Update mint_nonce
    mint_nonce = new_mint_nonce;

    ;; Emit log (includes old value for SCB-11)
    cell log = begin_cell()
        .store_uint(0x534d4e43, 32)         ;; mint_nonce_set_log tag
        .store_uint(old_mint_nonce, 64)     ;; old mint nonce
        .store_uint(new_mint_nonce, 64)     ;; new mint nonce
        .store_uint(governance_nonce, 64)
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

set_vault_fee_recipient -> () set_vault_fee_recipient(slice payload) impure {
    ;; Parse set_vault_fee_recipient_payload#56465257 vault_address:MsgAddressInt new_fee_recipient:MsgAddressInt
    throw_unless(ERR_INVALID_ACTION, payload~load_uint(32) == 0x56465257);

    slice vault_address = payload~load_msg_addr();
    slice new_fee_recipient = payload~load_msg_addr();

    ;; Build message body for vault: OP_VAULT_SET_FEE_WALLET new_fee_recipient:MsgAddressInt
    cell vault_msg_body = begin_cell()
        .store_uint(OP_VAULT_SET_FEE_WALLET, 32)
        .store_slice(new_fee_recipient)
    .end_cell();

    ;; Send message to vault contract
    send_raw_message(begin_cell()
        .store_uint(0x18, 6)                ;; bounceable
        .store_slice(vault_address)
        .store_coins(GAS_FOR_VAULT_OP)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1)  ;; no extras
        .store_uint(1, 1)                   ;; body in ref
        .store_ref(vault_msg_body)
    .end_cell(), 1);

    ;; Emit log
    cell log = begin_cell()
        .store_uint(0x56465257, 32)         ;; vault_fee_recipient_set_log tag ("VFRW")
        .store_slice(vault_address)
        .store_slice(new_fee_recipient)
        .store_uint(governance_nonce, 64)
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

set_vault_fee_basis_points -> () set_vault_fee_basis_points(slice payload) impure {
    ;; Parse set_vault_fee_basis_points_payload#56464250 vault_address:MsgAddressInt new_fee_basis_points:uint16
    throw_unless(ERR_INVALID_ACTION, payload~load_uint(32) == 0x56464250);

    slice vault_address = payload~load_msg_addr();
    int new_fee_basis_points = payload~load_uint(16);

    ;; Build message body for vault: OP_VAULT_SET_FEE_BASIS_POINTS new_fee_basis_points:uint16
    cell vault_msg_body = begin_cell()
        .store_uint(OP_VAULT_SET_FEE_BASIS_POINTS, 32)
        .store_uint(new_fee_basis_points, 16)
    .end_cell();

    ;; Send message to vault contract
    send_raw_message(begin_cell()
        .store_uint(0x18, 6)                ;; bounceable
        .store_slice(vault_address)
        .store_coins(GAS_FOR_VAULT_OP)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1)  ;; no extras
        .store_uint(1, 1)                   ;; body in ref
        .store_ref(vault_msg_body)
    .end_cell(), 1);

    ;; Emit log
    cell log = begin_cell()
        .store_uint(0x56464250, 32)         ;; vault_fee_basis_points_set_log tag ("VFBP")
        .store_slice(vault_address)
        .store_uint(new_fee_basis_points, 16)
        .store_uint(governance_nonce, 64)
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
