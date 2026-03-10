# Governance signatures are not domain-separated (replayable across contracts with same governance set)


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex, aiflow_scanner_smart |
| Project ID | `c0b155c0-ce9d-11f0-afef-b3f141791562` |
| Commit | `20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856` |

## Location

- **Local path:** `./source_code/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc
- **Lines:** 1–1

## Description

`execute_governance_action` verifies signatures over `hash_governance_action(action_type, nonce, epoch, payload_ref)` (committing to `(tag, action_type, nonce, epoch, payload_ref)`), but this hash lacks any contract-specific domain separator (e.g., contract address, workchain/network/chain ID, global-id, or unique salt). If the same governance public key set is reused across multiple bridge deployments/environments (common during initialization, redeploy/migration, or across testnet/mainnet or shards) and their `governance_nonce`/`governance_epoch` are aligned, a validly signed governance action intended for one instance can be replayed on another to perform the same administrative change. This enables cross-instance/cross-chain replay of actions including `transfer_token_ownership` (action_type 4), token mapping/status changes, watcher/governance rotations, mint nonce changes, and vault fee parameter updates: an attacker can copy `action_type`, `nonce`, `epoch`, `payload` (e.g., `jetton_root` and `new_owner`), and `signatures` from Chain A and submit a new `OP_EXECUTE_GOVERNANCE` message to Chain B, which will validate and execute if the nonce matches state. Mitigation is to bind signatures to a single contract instance by including a domain separator in the signed preimage within `hash_governance_action`, such as `store_slice(my_address())` and optionally a constant string/version plus workchain/network/global-id.

## Recommendation

- Bind governance signatures to a single contract instance. Modify hash_governance_action to include a domain separator in the signed preimage. The domain must at minimum commit to:
  - The contract’s full address (including workchain/global-id).
  - A deployment-unique salt (stored on-chain) and a constant tag/version to avoid ambiguity across upgrades.
- Make execute_governance_action verify signatures against this new domain-bound hash and reject legacy (non-domain-separated) signatures once the upgrade is active.
- On upgrade/migration:
  - Initialize and persist a unique domain_salt per deployment (preferably random; deriving from address is acceptable if uniqueness is guaranteed).
  - Bump governance_epoch to invalidate any previously issued signatures and clear any queued governance messages relying on the old hashing scheme.
- Update off-chain signing/verification tooling to include the domain fields deterministically derived from on-chain state; refuse to sign messages without the domain separator.
- Operationally, until the fix is deployed, avoid reusing the same governance key set across different deployments/environments. If reuse is unavoidable, ensure epochs/nonces are not aligned; this is only a temporary risk-reduction, not a substitute for domain separation.
- Add tests that attempt cross-instance replay between two deployments with identical governance keys to ensure replays are rejected after the change.

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
