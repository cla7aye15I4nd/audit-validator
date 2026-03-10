# Unbounded initial fee_basis_points can make deposits revert and strand jettons in the vault wallet


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟢 Minor |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `c0b155c0-ce9d-11f0-afef-b3f141791562` |
| Commit | `20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856` |

## Location

- **Local path:** `./src/contracts/ton/bridge-vault-init.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-vault-init.fc
- **Lines:** 1–1

## Description

build_initial_storage stores fee_basis_points as an unconstrained uint16. The runtime vault logic (bridge-vault.fc) assumes a sensible fee (and governance updates later enforce <= MAX_FEE_BASIS_POINTS), but an initial value > BPS_DENOMINATOR (10000) can make calculate_fee(amount) exceed amount for common deposit sizes, producing a negative burn_amount. This causes .store_uint(burn_amount, 128) / .store_coins(burn_amount) to throw during jetton notification handling, so the notification fails and no burn/bridge event is emitted; the transferred jettons remain in the vault-owned jetton wallet with no on-chain mechanism to process/recover them. Add an explicit range check in the init builder (e.g., 0 <= fee_basis_points <= 10000 and ideally also <= the contract’s MAX_FEE_BASIS_POINTS) before storing it.

## Recommendation

- Enforce hard bounds at initialization. In build_initial_storage, validate fee_basis_points and abort deployment if it is outside 0 ≤ fee_basis_points ≤ min(BPS_DENOMINATOR=10000, MAX_FEE_BASIS_POINTS).
- Mirror the same bound check in any constructor/initialization or governance path that can set the initial fee before runtime checks take effect; reject the message if validation fails.
- Add a runtime safety guard in the jetton notification flow: if calculate_fee(amount) > amount, do not attempt .store_uint(burn_amount, 128) / .store_coins(burn_amount). Revert before accepting the transfer or proactively return the jettons to the sender to prevent stranding.
- Add tests covering boundary and invalid values (0, 10000, MAX_FEE_BASIS_POINTS, and values above each bound), and verify that deposits cannot strand funds when misconfigured.
- Emit a clear error code/reason on validation failure to aid monitoring and troubleshooting.

## Vulnerable Code

```
cell build_initial_storage(
    slice admin_address,           ;; Admin address (can update fee wallet, etc.)
    slice fee_wallet_address,      ;; Wallet to receive fees
    slice allowed_jetton_address,  ;; Whitelisted jetton root address
    int fee_basis_points           ;; Fee percentage in basis points (default 100 = 1%)
) {
    ;; Build stats cell
    cell stats_cell = begin_cell()
        .store_uint(0, 128)              ;; total_burned = 0
        .store_uint(0, 128)              ;; total_fees = 0
    .end_cell();

    ;; Build storage cell
    return begin_cell()
        .store_slice(admin_address)
        .store_slice(fee_wallet_address)
        .store_slice(allowed_jetton_address)
        .store_uint(fee_basis_points, 16)  ;; fee_basis_points (default 100 = 1%)
        .store_ref(stats_cell)
    .end_cell();
}
```
