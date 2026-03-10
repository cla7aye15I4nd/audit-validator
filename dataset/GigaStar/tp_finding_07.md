# Duplicate-name overwrite during rotation lets an agent replace an existing active box entry


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟢 Minor |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex, aiflow_scanner_llm, aiflow_scanner_llm_reverse, aiflow_scanner_smart |
| Scan Model | gpt-5.2 |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/BoxMgr.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/BoxMgr.sol
- **Lines:** 1–1

## Description

`rotateBox` moves a BoxInfo record between the active (`_boxes`) and inactive (`_inactive`) maps by reading the entry from the source, inserting it into the destination via `BI.addBoxNoCheck(dst, nameKey, info)`, and then deleting the source via `BI.removeBoxByName(src, nameKey)`. The core flaw is that `addBoxNoCheck` performs no existence check and `rotateBox` does not verify that `dst` lacks the same `nameKey` (or the same `boxProxy`), so an existing destination entry can be overwritten and its index mappings (`idxByName` and potentially `idxByAddr`) corrupted while the previous element remains in the values array, becoming orphaned/unreachable via name-based lookups. This state is realistically reachable because `renameBox` only checks for name collisions within the map being modified (e.g., renaming in `_inactive` only checks `_inactive`), enabling cross-map collisions where both `_boxes` and `_inactive` contain the same `nameKey`; an Agent can, for example, rename an inactive “SpareBox” to an active “TargetBox,” then call `rotateBox(..., "TargetBox", true)` to overwrite `_boxes["TargetBox"]`. As a result, an agent (no reentrancy needed; only `_requireOnlyAgent`, which may be satisfiable by unprivileged users if misconfigured) can arbitrarily replace the active box for a given name (including `boxProxy` and other BoxInfo fields), with `rotateBox` still emitting `BoxActivation` and returning `ok=true`, coercing downstream systems that treat `_boxes[name]` as canonical (routing calls, approvals, vault interactions) into using an unintended proxy. Impacts include registry integrity loss, misrouted deposits/withdrawals or permission checks, functional disruption/insolvency risks if accounting ties to the wrong box, and permanent fund lock scenarios—e.g., Vault withdrawals calling `BoxMgr.push(boxName, ...)` rely on `_boxes` name lookup, so if the fund-holding box becomes orphaned from `idxByName`, funds may be stuck absent upgrade/recovery; a robust fix is to reject moves when `dst` already contains `nameKey` or `boxProxy` and enforce global uniqueness across both maps in `renameBox` (or otherwise guarantee `rotateBox`’s precondition).

## Recommendation

- Enforce global uniqueness by name and by boxProxy across both _boxes and _inactive. Provide helpers that query both maps (by name and by address) and use them in all mutating paths.
- In rotateBox, before insertion into dst, require that dst does not contain nameKey and that neither map contains the same boxProxy. Revert on any collision. Replace BI.addBoxNoCheck with a safe insert that validates these invariants, or gate its use with explicit checks. Emit BoxActivation only after a successful move.
- In renameBox, check the target name against both maps and reject if it exists in either. Preserve the one-to-one mapping between nameKey and boxProxy.
- Maintain index integrity atomically: whenever adding/removing/moving, update idxByName, idxByAddr, and the underlying arrays so no element is orphaned or left unreachable. Avoid writing to dst unless all preconditions pass; on failure, revert the whole operation.
- Add internal invariant assertions and tests: no duplicate nameKey or boxProxy across both maps; every index mapping matches its array entry; every array entry is reachable via nameKey.
- For existing deployments, run a one-time migration to detect duplicates and repair or purge orphaned entries; provide an admin recovery routine to reattach or safely remove any discovered orphaned boxes.
- Restrict rotateBox/renameBox to trusted roles (not user-controlled Agents) and review _requireOnlyAgent configuration to prevent unprivileged access.

## Vulnerable Code

```
function rotateBox(uint40 seqNumEx, UUID reqId, string calldata name, bool activate) external override{
        address caller = msg.sender;
        _requireOnlyAgent(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        bool ok = false;
        bytes32 nameKey = String.toBytes32(name);
        if (nameKey != bytes32(0)) {
            // Get the source and destination maps
            BI.Emap storage src = activate ? _inactive : _boxes;
            BI.Emap storage dst = activate ? _boxes : _inactive;

            // Ensure it exists
            (bool found, BI.BoxInfo storage info) = BI.tryGetBoxByName(src, nameKey);
            if (found) {
                // Add to dst boxes without recreating it
                address boxProxy = info.boxProxy;
                BI.addBoxNoCheck(dst, nameKey, info); // info is copied; no existance check (see `found`)

                // Remove from src boxes
                BI.removeBoxByName(src, nameKey);
                emit BoxActivation(name, boxProxy, name, activate);
                ok = true;
            }
        }
        _setCallRes(caller, seqNumEx, reqId, ok);
    }
```

## Related Context

```
function _setCallRes(address caller, uint40 seqNum, UUID reqId, uint16 rc, uint16 lrc, uint16 count) internal{
        if (seqNum == 0) return;

        CallRes memory cr = CallRes({
            reqId: reqId,
            rc: rc,
            lrc: lrc,
            count: count,
            blockNum: uint40(block.number),
            reserved: 0
        });

        // Track result via event (in tx receipt) and storage (easier to lookup by seqNum after storage lag)
        // - See `ReqAck` definition for more
        emit ReqAck(reqId, caller, seqNum, cr, false);
        _crBySeqNum[caller][seqNum] = cr;
        _crByReqId[reqId] = cr;
    }

function removeBoxByName(bytes32 nameKey) external{
        BI.removeBoxByName(_emap, nameKey);
    }

function addBoxNoCheck(bytes32 nameKey, BI.BoxInfo memory value) external{
        BI.addBoxNoCheck(_emap, nameKey, value);
    }

function tryGetBoxByName(bytes32 nameKey, bool expectFound) external view returns(BI.BoxInfo memory){
        (bool found, BI.BoxInfo storage value) = BI.tryGetBoxByName(_emap, nameKey);
        vm.assertEq(expectFound, found);
        return value;
    }

function toBytes32(string calldata source) public pure returns (bytes32 result){
        return String.toBytes32(source);
    }

function _isReqReplay(address caller, uint40 seqNum, UUID reqId) internal returns(bool){
        if (seqNum == 0) return false; // Hot path for on-chain calls; No tracking (reliability guaranteed)

        uint40 nextExpected = _seqNums[caller];  // Get next expected seqNum
        bool isNewReqId = _crByReqId[reqId].blockNum == 0;
        // Check if `reqId` has been used by any caller
        if (isNewReqId) { // then new `reqId`
            // Compare `seqNum` vs next expected
            if (nextExpected == 0) nextExpected = 1; // First call by `caller`
            if (nextExpected == seqNum) {            // Received matched expected
                _seqNums[caller] = seqNum + 1;       // Accept request, advance expected seq num
                return false;                        // Case 0100; Hot path for off-chain calls
            }

            if (seqNum > nextExpected) { // then client out-of-sync, possibly client problem or block reorg
                revert SeqNumGap(nextExpected, seqNum, caller); // Case 0200
            }
            // Case 0000; `seqNum` < expected with a different `reqId` => error
        } else {
            // Check if replay allowed
           
...<truncated>...
```
