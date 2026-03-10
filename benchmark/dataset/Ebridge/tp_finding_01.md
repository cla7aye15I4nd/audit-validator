# bridge_pool `add_native_token_liquidity` doesn't check `jetton_address`


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `97cd8990-a175-11ef-bde1-6ddfa26a617d` |
| Commit | `d88b8f41c00b0fc9cb85d5c99b1c92837e4b19ac` |

## Location

- **Local path:** `./src/contracts/bridge_pool.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/97cd8990-a175-11ef-bde1-6ddfa26a617d/source?file=$/github/eBridgeCrosschain/ebridge-contracts.ton/d88b8f41c00b0fc9cb85d5c99b1c92837e4b19ac/contracts/bridge_pool.fc
- **Lines:** 223–223

## Description

```c=220
    if (op == add_native_token_liquidity) {
        int amount = in_msg_body~load_coins();
        storage::liquidity += amount;
        msg_value -= amount;
        cell acc_state_init = calculate_bridge_pool_liquidity_account_state_init(sender_address, my_address(), storage::jetton_address, storage::pool_liquidity_account_code);
        var body = begin_cell()
            .store_uint(provider_liquidity, 32)
            .store_uint(query_id, 64)
            .store_coins(amount);
        send_message_with_stateinit(msg_value, calculate_bridge_pool_liquidity_account_address(acc_state_init), acc_state_init, body.end_cell(), SEND_MODE_REGULAR | SEND_MODE_IGNORE_ERRORS);
        save_storage();
        return ();
    }
```
1. It is not checked explicitly that initial `msg_value` is bigger than `amount`.
2. It is not checked that `storage::jetton_address` is HOLE_ADDRESS.
3. The message to bridge_pool_liquidity_account is sent in `SEND_MODE_IGNORE_ERRORS` mode, so in case of not enough funds the transaction will not be reverted.
4. The gas provided is not checked.

As a result, the user can attach less tons than expected. The user can send `add_native_token_liquidity` to the bridge_pool with expensive `storage::jetton_address` and get credit in those jettons.

## Recommendation

We recommend performing the required checks.

## Vulnerable Code

```
if (op == release_native_token) {
        throw_unless(UNAUTHORIZED, equal_slices(sender_address, storage::bridge_swap_address));
        (var swap_id, var message_id, var receipt_cell, var chain_id, var amount) =
        (in_msg_body~load_ref(), in_msg_body~load_uint(256), in_msg_body~load_ref(), in_msg_body~load_uint(32), in_msg_body~load_coins());
        var receipt_info = receipt_cell.begin_parse();
        (var receipt_id, int receipt_hash, slice receiver) = (receipt_info~load_ref(), receipt_info~load_uint(256), receipt_info~load_msg_addr());
        if (storage::liquidity < amount) {
            resend_to_swap(query_id, receipt_id, receipt_hash, message_id, LIQUIDITY_NOT_ENOUGH, HALF_ONE_DAY);
            return ();
        }
        (var success, var error, var min_wait_seconds) = consume_limit(chain_id, SWAP, amount);
        if (success) {
            var ton_amount_to_record_swap = ONE_TON / 100;
            var body = begin_cell().store_uint(chain_id, 32).end_cell();
            storage::liquidity -= amount;
            send_message_nobounce(amount + calculate_release_transfer_fee(), receiver, body, SEND_MODE_PAY_FEES_SEPARETELY);
            emit_and_send_to_swap(receiver, amount, chain_id, query_id, swap_id, receipt_id, ton_amount_to_record_swap);
        } else {
            resend_to_swap(query_id, receipt_id, receipt_hash, message_id, error, min_wait_seconds);
            return ();
        }
        save_storage();
        return ();
    }

    if (op == add_native_token_liquidity) {
        int amount = in_msg_body~load_coins();
        storage::liquidity += amount;
        msg_value -= amount;
        cell acc_state_init = calculate_bridge_pool_liquidity_account_state_init(sender_address, my_address(), storage::jetton_address, storage::pool_liquidity_account_code);
        var body = begin_cell()
            .store_uint(provider_liquidity, 32)
            .store_uint(query_id, 64)
            .store_coins(amount);
        send_message_with_stateinit(msg_value, calculate_bridge_pool_liquidity_account_address(acc_state_init), acc_state_init, body.end_cell(), SEND_MODE_REGULAR | SEND_MODE_IGNORE_ERRORS);
        save_storage();
        return ();
    }

    if (op == remove_liquidity) {
        var liquidity = in_msg_body~load_coins();
        slice owner = in_msg_body~load_msg_addr();
        int is_native = in_msg_body~load_uint(1);
        cell acc_state_init = calculate_bridge_pool_liquidity_account_state_init(owner, my_address(), storage::jetton_address, storage::pool_liquidity_account_code);
        throw_unless(UNAUTHORIZED, equal_slices(calculate_bridge_pool_liquidity_account_address(acc_state_init), sender_address));
        throw_unless(LIQUIDITY_NOT_ENOUGH, storage::liquidity >= liquidity);
        storage::liquidity -= liquidity;
        if (is_native) {
            send_simple_message(liquidity, owner, begin_cell().store_slice(owner).end_cell(), SEND_MODE_PAY_FEES_SEPARETELY);
        } else {
            var body0 = create_simple_transfer_body(query_id, 0, owner, liquidity, owner);
            body0 = body0.store_uint(remove_liquidity_ok, 32); ;; append exit code
            send_simple_message(0, storage::jetton_pool_wallet_address, body0.end_cell(), SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);
        }
        save_storage();
        return ();
    }

    if (op == set_daily_limit_config) {
```
