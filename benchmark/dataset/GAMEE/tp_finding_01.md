# Lack of gas can lead to incomplete execution


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `03a8bcb0-4f51-11ef-8188-0505b58ed717` |
| Commit | `47b8fb00163af2755b413c16cd815672c5cdeae2` |

## Location

- **Local path:** `./src/contracts/airdrop_helper.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/03a8bcb0-4f51-11ef-8188-0505b58ed717/source?file=$/github/Ton-Raffles/scalable_airdrops_with_date_start/47b8fb00163af2755b413c16cd815672c5cdeae2/contracts/airdrop_helper.fc
- **Lines:** 26–26

## Description

`op::process_claim` works this way:
1. The user sends an external message to their airdrop_helper.
2. It is checked that the airdrop_helper balance is at least `const::min_balance + const::fee` (0.1 ton).
3. `const::min_balance` is reserved on airdrop_helper.
4. `op::process_claim` message is sent to the airdrop contract with all the rest balance attached. `set_claimed(-1)` is saved to the storage.
5. Airdrop sends the `op::jetton::transfer` message to their wallet with the destination specified in the Merkle tree item.

However, the gas ensured (0.05 ton) is not enough to complete the transaction:
1. 0.01 ton is used in `op::jetton::transfer` message as `fwd_ton_amount`.
2. 0.034 ton is used by the jetton transfer handler.
3. Two messages forwarded (from airdrop_helper to airdrop, from airdrop to its jetton_wallet).
4. Two messages processed (external message in airdrop_helper and internal message in airdrop).
5. Merkle proof size is not completely predictable.

Also, if the `op::process_claim` fails due to lack of gas, the bounced message will not be delivered to airdrop_helper and the `claimed` flag is kept active. As a result, the funds will be lost.

## Recommendation

We recommend increasing the `const::fee` to ensure complete transaction flow execution.

## Vulnerable Code

```
#include "imports/stdlib.fc";
#include "constants.fc";

() set_claimed(int claimed) impure {
    set_data(begin_cell()
        .store_int(claimed, 1)
        .store_slice(get_data().begin_parse().skip_bits(1))
    .end_cell());
}

() recv_internal(cell in_msg_full, slice in_msg_body) impure {
    slice cs = in_msg_full.begin_parse();
    int bounced? = cs~load_uint(4) & 1;
    if (bounced?) {
        slice sender = cs~load_msg_addr();
        slice ds = get_data().begin_parse().skip_bits(1);
        slice airdrop = ds~load_msg_addr();
        throw_unless(error::wrong_sender, equal_slices(sender, airdrop));
        int op = in_msg_body.skip_bits(32).preload_uint(32);
        throw_unless(error::wrong_operation, op == op::process_claim);
        set_claimed(0);
    }
}

() recv_external(int my_balance, int msg_value, cell in_msg_full, slice in_msg_body) impure {
    throw_unless(error::not_enough_coins, my_balance >= const::min_balance + const::fee);
    slice ds = get_data().begin_parse();
    throw_if(error::already_claimed, ds~load_int(1));
    slice airdrop = ds~load_msg_addr();
    int proof_hash = ds~load_uint(256);
    int index = ds~load_uint(256);

    int query_id = in_msg_body~load_uint(64);
    cell proof = in_msg_body~load_ref();

    throw_unless(error::wrong_proof, proof.cell_hash() == proof_hash);

    accept_message();

    raw_reserve(const::min_balance, 0);

    send_raw_message(begin_cell()
        .store_uint(0x18, 6)
        .store_slice(airdrop)
        .store_coins(0)
        .store_uint(1, 107)
        .store_ref(begin_cell()
            .store_uint(op::process_claim, 32)
            .store_uint(query_id, 64)
            .store_ref(proof)
            .store_uint(index, 256)
        .end_cell())
    .end_cell(), 128);
    
    set_claimed(-1);
}
```
