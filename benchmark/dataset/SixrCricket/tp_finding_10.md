# withdraw_ton destination validation is ineffective and can allow addr_none/unsupported address types


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `c0b155c0-ce9d-11f0-afef-b3f141791562` |
| Commit | `20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856` |

## Location

- **Local path:** `./source_code/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-vault.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-vault.fc
- **Lines:** 1–1

## Description

withdraw_ton only checks destination.slice_empty?(), but destination is parsed with load_msg_addr(), so it will not be an “empty slice” even for addr_none ($00) or other unsupported address forms. This can allow constructing a withdrawal to addr_none or a non-internal address type, which may burn funds (if accepted) or trigger action-phase errors/bounces (fees lost) unexpectedly. Validate destination as a proper internal address (e.g., reject addr_none by checking the first 2 bits != 00 and/or enforce addr_std/addr_var only) similar to is_fee_wallet_configured().

## Recommendation

- Do not rely on destination.slice_empty?() after load_msg_addr(); it is non-empty even for addr_none and unsupported address types.
- Explicitly validate that destination is an internal address. Accept only addr_std and/or addr_var. Reject addr_none ($00) and addr_extern ($01).
- Reuse the same internal-address checks used in is_fee_wallet_configured() (or an equivalent helper) to keep logic consistent.
- On invalid destination, revert with a clear error code before deducting funds or sending a message.
- If your design requires it, further restrict to addr_std only and enforce expected flags (e.g., bounceable), zero anycast, and allowed workchain(s).
- Add tests for addr_none and addr_extern to confirm withdrawals are rejected and no fees are spent.

## Vulnerable Code

```
() withdraw_ton(slice sender, slice destination, int amount) impure {
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
