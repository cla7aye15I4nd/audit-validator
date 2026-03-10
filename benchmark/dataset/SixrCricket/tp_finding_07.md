# Governance withdrawal signatures are replayable across contracts because the signed hash lacks domain separation (no contract/epoch/nonce)


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
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

The `execute_withdraw_ton_funds` flow (invoked by `recv_internal`) contains a critical signature-domain/replay flaw: it verifies a quorum of `signatures` over `withdraw_hash` computed by `hash_withdraw_ton_funds_action` using only the opcode `OP_EXECUTE_WITHDRAW_TON` (`0x574452415720`), `destination`, `amount`, and `reference`, and then applies replay protection solely via per-contract storage `consumed_references[reference]`. Because the signed payload omits any domain separator (e.g., `my_address()`/workchain+addr) and any chain identifier, and also omits governance freshness fields such as `governance_epoch`/`governance_nonce`, the exact same `(destination, amount, reference, signatures)` tuple is valid across any other deployment that shares the same governance public-key set (common for multisig/bridge setups, including Mainnet/Testnet or parallel vault/pool instances), and signatures may remain valid indefinitely until the reference is consumed (even after governance rotation unless enough signers are removed to drop below threshold). An unprivileged attacker can identify two instances with identical governance keys (e.g., via `get_governance_member(i)` for `i=0..4`), capture a valid withdrawal’s parameters and `signatures` cell from an executed on-chain transaction or by requesting a signed withdrawal, confirm the `reference` is unused on the target using `is_reference_consumed_query(reference)` and that the target’s `balance >= amount`, then replay `OP_EXECUTE_WITHDRAW_TON` with the same parameters to the target to trigger `send_raw_message` and drain funds. This undermines the contract’s broader replay-protection model (elsewhere governance actions include nonce+epoch to invalidate signatures) and should be fixed by binding the withdrawal hash to the contract address/workchain and a chain/epoch/monotonic nonce (e.g., include `governance_epoch` and/or a dedicated withdrawal nonce or reuse `governance_nonce`).

## Recommendation

- Bind the signed withdrawal payload to a unique domain. Redefine the hash signed by governance for OP_EXECUTE_WITHDRAW_TON to include: (a) contract identity (workchain + my_address()), (b) network identifier (e.g., TON global_id to distinguish Mainnet/Testnet), (c) a signature schema/version tag, in addition to destination, amount, and reference.
- Add governance freshness to the signed payload. Include a monotonic governance_nonce or governance_epoch (or both). Enforce single-use semantics on-chain by rejecting reused nonces/epochs and persisting consumption. Keep the existing consumed_references check, but do not rely on it as the only replay protection.
- Reject legacy signatures. Either bump the version/OP or include a version field in the signed payload and accept only the new version after upgrade. On upgrade, increment governance_epoch (or reset/start a new nonce space) to invalidate any pre-signed messages.
- Update off-chain signer tooling and documentation to sign over the new fields and to manage nonce/epoch issuance. Ensure signers cannot issue signatures without the contract address/workchain and network id embedded.
- Test that the same (destination, amount, reference, signatures) cannot execute on another contract instance or network, and that reused nonces/references are rejected.

## Vulnerable Code

```
() execute_withdraw_ton_funds(slice destination, int amount, int reference, cell signatures) impure {
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

validate_destination_address -> () validate_destination_address(slice addr) impure inline {
    ;; Check that address is not empty and is properly formatted
    ;; MsgAddressInt should have proper structure (addr_std$10 or addr_var$11)
    throw_if(ERR_INVALID_DESTINATION, addr.slice_empty?());

    ;; Parse address prefix to ensure it's valid
    int addr_type = addr.preload_uint(2);
    ;; Valid types: addr_std (0b10) or addr_var (0b11)
    throw_unless(ERR_INVALID_DESTINATION, (addr_type == 2) | (addr_type == 3));
}

is_reference_consumed -> int is_reference_consumed(int reference) inline {
    (slice value, int found) = consumed_references.udict_get?(64, reference);
    if (~ found) {
        return 0;
    }
    return value~load_uint(1);
}

hash_withdraw_ton_funds_action -> int hash_withdraw_ton_funds_action(slice destination, int amount, int reference) inline {
    cell action = begin_cell()
        .store_uint(0x574452415720, 48)     ;; withdraw_ton_funds_payload tag
        .store_slice(destination)
        .store_uint(amount, 128)
        .store_uint(reference, 64)
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

mark_reference_consumed -> () mark_reference_consumed(int reference) impure inline {
    consumed_references = consumed_references.udict_set_builder(64, reference, begin_cell().store_uint(1, 1));
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
