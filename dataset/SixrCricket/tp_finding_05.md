# Governance Update Mechanism Permanently Inoperable Due to Cell Size Limit Violation


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_smart |
| Scan Model | gemini-3-pro-preview |
| Project ID | `c0b155c0-ce9d-11f0-afef-b3f141791562` |
| Commit | `20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856` |

## Location

- **Local path:** `./src/contracts/ton/bridge-multisig.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/c0b155c0-ce9d-11f0-afef-b3f141791562/source?file=$/github/Liberty-Games/sixr-bridge-watchers/20fc6b15b4134cdd724fa8a0b8d0f1f7d4981856/contracts/ton/bridge-multisig.fc
- **Lines:** 1–1

## Description

The `update_governance` function contains a critical logical flaw that renders the governance rotation mechanism permanently unusable. The function attempts to parse five 256-bit public keys and a 32-bit tag from the `payload` slice, totaling 1312 bits ($32 + 5 \times 256$). However, a standard cell in the TON blockchain has a hard limit of 1023 bits. Since the `payload` slice is derived from a single `payload_ref` cell passed in `execute_governance_action`, and the function uses sequential `load_uint` operations without implementing any logic to load data from chained reference cells (e.g., using `load_ref`), it is physically impossible to provide a valid payload that fits the required data structure within the slice's constraints.

**Exploit Demonstration:**
1. **Setup:** Deploy the contract and assume the role of an auditor or admin attempting to rotate the governance keys.
2. **Payload Construction:** Construct a standard governance update payload containing the required tag `0x474f5653` and 5 new 256-bit public keys. Observe that the total size is 1312 bits.
3. **Transaction Attempt:** Attempt to create a valid `OP_EXECUTE_GOVERNANCE` message. You will be forced to split the payload into a chain of cells (Root -> Reference) because 1312 bits cannot fit into the single `payload_ref` cell (max 1023 bits).
4. **Execution Failure:** Send the transaction. The `update_governance` function will execute and successfully read the tag and the first three keys (consuming $32 + 768 = 800$ bits). When it attempts to execute `payload~load_uint(256)` for the fourth key, it will try to read beyond the bit limit of the current cell/slice (requiring access up to bit 1056). Because the code does not load the reference cell, the VM triggers a `cell_underflow` exception.
5. **Result:** The transaction reverts, and the governance keys are never updated. This confirms that the governance logic is permanently frozen and cannot be rotated.

## Recommendation

Redesign the governance payload and parser to respect the 1023-bit cell limit and support multi-cell input.

- Define a canonical multi-cell layout for governance updates. Keep the tag (0x474f5653) in the root cell and place the five 256-bit keys in reference cells (e.g., one key per ref, or a single ref containing a compact subtree or dictionary). The parser in update_governance must read keys from references (load_ref) and reconstruct the ordered sequence deterministically.
- Add strict bounds checks before each read. If the current slice lacks enough bits for the next key, explicitly load the next reference; if the reference is missing or malformed, revert with a clear error code. Never rely on a single slice to hold all 1312 bits.
- Enforce limits to prevent abuse: exact key count = 5, maximum reference depth, and maximum total bits. Reject payloads that exceed limits or contain extra data.
- Version the payload format (e.g., include a version/discriminant with the tag) and support only the new, canonical encoding going forward. If backward compatibility is required, accept both formats and route to the correct parser unambiguously.
- Ship a patch release immediately so governance rotation becomes possible, and add tests that construct the multi-cell payload and verify successful key updates, as well as negative tests for underflow, missing refs, and oversize payloads.
- Document the payload schema and validation rules to ensure off-chain tooling constructs cells correctly.

## Vulnerable Code

```
() update_governance(slice payload) impure {
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
```

## Related Context

```
set_pubkey -> cell set_pubkey(cell dict, int index, int pubkey) inline {
    return dict.udict_set_builder(8, index, begin_cell().store_uint(pubkey, 256));
}
```
