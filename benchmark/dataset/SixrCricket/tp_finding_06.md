# Outgoing withdrawal/log messages are built with an inconsistent body encoding (body-in-ref bit not set)


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `c0b155c0-ce9d-11f0-afef-b3f141791562` |
| Commit | `20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856` |

## Location

- **Local path:** `./source_code/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc
- **Lines:** 1–1

## Description

In execute_withdraw_ton_funds, both `send_raw_message` constructions use `.store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)` followed by `.store_ref(msg_body/log)`, which appears to encode `init=0` and `body` as inline while still storing the body as a ref. This can produce a malformed/non-canonical message body (e.g., recipient sees an empty-bit body with an unexpected ref), increasing the chance of bounces or unexpected parsing failures, and undermining the intended inclusion of the comment/log payload. Align the encoding with the pattern used elsewhere in the contract when sending a body by reference (store the `body_in_ref` bit explicitly, e.g., store the init bit then `.store_uint(1,1)` before `.store_ref(body)`).

## Recommendation

- In both send_raw_message constructions in execute_withdraw_ton_funds that use “.store_uint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)” followed by “.store_ref(msg_body/log)”, set the body-in-ref bit to 1 before storing the ref and keep init=0. Do not encode an inline body and a ref simultaneously.
- If you choose an inline body instead, set body-in-ref=0 and write the body inline; do not call .store_ref in that case.
- Align this encoding with the pattern used elsewhere in the contract for ref bodies to maintain canonical message layout and avoid bounces/parsing errors.
- Verify via decoding/tests that the emitted messages include the intended comment/log payload and are accepted by standard parsers/wallets.

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
