# Ownership transfer log is emitted as success even if the transfer message bounces/fails


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | info |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `c0b155c0-ce9d-11f0-afef-b3f141791562` |
| Commit | `20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856` |

## Location

- **Local path:** `./source_code/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc
- **Lines:** 1–1

## Description

transfer_token_ownership emits token_ownership_transferred_log immediately after sending the change_admin message, but the contract cannot know whether the target jetton root accepted the change (the message may bounce due to wrong admin, insufficient value, non-jetton target, etc.). This can mislead off-chain monitoring/automation into believing ownership was transferred when it was not. Consider renaming the event semantics to indicate an attempted/requested transfer, and/or handling bounced messages in recv_internal (bounced flag) to emit a failure log.

## Recommendation

- Do not emit a “success” ownership transfer event immediately after sending the change_admin message. Rename it to indicate intent (for example, OwnershipTransferRequested) and clearly document that it does not confirm acceptance by the target jetton root.
- Track each outgoing change_admin request (e.g., request_id/new_admin/amount/timestamp) so you can correlate later outcomes.
- Handle bounced internal messages in recv_internal (bounced flag). If a bounce corresponds to a tracked change_admin request, emit a failure event (for example, OwnershipTransferFailed) with the correlated request data and clear the pending state.
- Only emit a definitive success event if you can verify acceptance (for example, via an explicit acknowledgment from the target contract or by reading the target’s admin state). If no confirmation is available, omit the success event and rely on off-chain verification.
- Ensure the outbound message is bounceable, includes sufficient value to cover processing, and uses the correct payload to minimize avoidable bounces.
- Update documentation and off-chain automation to rely on the request/failure semantics (and, if available, confirmation), not on a preemptive success log.

## Vulnerable Code

```
() transfer_token_ownership(slice payload) impure {
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
```
