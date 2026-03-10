# Jetton burn message body is likely non‑TEP-74 compliant (missing custom_payload), which can make burns fail and lead to unbacked mints


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

send_jetton_burn builds the burn body as: op(32) | query_id(64) | amount | response_destination, but many TEP-74 jetton wallet implementations expect an additional field after response_destination: custom_payload:(Maybe ^Cell) (at minimum, a 1-bit flag). If the wallet expects this bit, the burn message will be rejected (slice underflow) and bounce, leaving the jettons unburned. Because the vault’s flow emits a BURN log used by off-chain watchers to mint on EVM without waiting for burn confirmation, systematic burn bounces can cause minting on EVM without actually burning on TON (supply inflation / unbacked bridge). Fix by encoding JettonBurn according to the jetton wallet’s actual schema (e.g., append .store_uint(0, 1) for custom_payload=None if following common TEP-74), and consider only emitting the mint-triggering event after observing a successful burn outcome.

## Recommendation

- Build the burn message body to match the target jetton wallet’s TEP‑74 schema: op | query_id(64) | amount | response_destination | custom_payload:(Maybe ^Cell). When no payload is needed, serialize the Maybe as absent (1‑bit flag = 0). Do not send a four‑field body.
- If the target wallet deviates from TEP‑74, mirror its exact ABI. Validate the encoding against the wallet implementation (or on testnet) to ensure no slice underflow/bounce.
- In the bridge flow, emit the mint‑triggering event only after confirming a successful burn on TON (e.g., receipt of burn_notification or other explicit success path). On bounce/failure, emit a failure event and block EVM minting.
- Attach sufficient TON for wallet execution/notification and enable bounce handling on the outbound message. Implement clear versioning/configuration of the burn encoder to prevent future schema drift.

## Vulnerable Code

```
() send_jetton_burn(slice jetton_wallet, int amount) impure inline {
    ;; Build jetton burn body
    cell burn_body = begin_cell()
        .store_uint(OP_JETTON_BURN, 32)          ;; op = burn
        .store_uint(0, 64)                       ;; query_id
        .store_coins(amount)                     ;; amount
        .store_slice(my_address())               ;; response_destination
    .end_cell();

    ;; Send message to jetton wallet
    send_raw_message(begin_cell()
        .store_uint(0x18, 6)                     ;; bounceable
        .store_slice(jetton_wallet)
        .store_coins(GAS_FOR_JETTON_BURN)
        .store_uint(0, 1 + 4 + 4 + 64 + 32 + 1)  ;; no extras
        .store_uint(1, 1)                        ;; body in ref
        .store_ref(burn_body)
    .end_cell(), 1);
}
```
