# Proposal ID truncation to uint16 in call-result tracking enables ID confusion and replay/misdirection (Impacts: 11, 17, 38)


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟢 Minor |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_llm_reverse |
| Scan Model | gpt-5.2 |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/Vault.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/Vault.sol
- **Lines:** 1–1

## Description

Security impacts: This can cause illegal/miscalculated state usage (11) and request/recording anomalies (17, 38) by allowing the off-chain idempotency/ack mechanism to publish and store an incorrect proposal id once the proposal counter exceeds 65,535, leading clients/agents to act on the wrong proposal.

Vulnerability: In `_createProp`, the newly created proposal id `pid` is a `uint` and is monotonically incremented (`pid = ++_propsCreated`). Immediately after emitting `PropCreated`, the code stores the call result via `_setCallRes(caller, seqNumEx, reqId, uint16(pid), 0, 0);`. The cast `uint16(pid)` silently truncates high bits when `pid > type(uint16).max` (65,535). This means the stored/acknowledged return code (`rc`) no longer uniquely identifies the created proposal. Because `_setCallRes` persists `CallRes` in `_crBySeqNum[caller][seqNum]` and `_crByReqId[reqId]`, any consumer that relies on `rc` to reference the created proposal will be pointed to a different (wrapped) id.

Exploit scenario (no privileged roles required beyond being an authorized agent, which is the assumed external caller for this flow): (1) Wait until `_propsCreated` surpasses 65,535 (can happen naturally over time). (2) Submit a new off-chain tracked request with a fresh `reqId` and correct `seqNumEx`. (3) Contract creates proposal `pid = 65536`, but stores `rc = uint16(65536) = 0` (or another wrapped value for larger pids). (4) Off-chain system reads `ReqAck`/storage `_crByReqId[reqId]` and believes the created proposal id is `0` (or another existing proposal id). (5) Subsequent operations performed by the agent/client using the acked id (e.g., sealing/executing/canceling a proposal in later flows) can target the wrong proposal, potentially corrupting workflow/state and causing actions to apply to an unintended proposal.

Root cause: Unsafe down-casting of a unique identifier (`pid`) into a smaller type for the request-tracking layer, with no rollover guard or explicit bounds check (the comment `// See UINT_ROLLOVER` suggests awareness but no enforcement here). The idempotency/ack mechanism is thus not collision-resistant across the contract’s lifetime.

## Recommendation

- Eliminate the downcast of proposal IDs when acknowledging/storing call results. Persist and emit the full-width proposal ID consistently across storage, events, and return paths; do not derive it from a uint16 field.
- If “rc” is intended to be a small return code, do not overload it with a proposal ID. Introduce a dedicated field for the proposal ID in the call-result structures/mappings and in any related events/acks.
- If ABI/storage compatibility requires a 16-bit field to remain, enforce a hard bound: revert proposal creation once the proposal counter would exceed 65,535; alternatively, introduce an “era/epoch” or high-bits field and require off-chain clients to use (era, pid16) as the composite identifier.
- Add a runtime check before persisting the call result to ensure the stored identifier exactly matches the created proposal ID (no truncation). Use safe-cast patterns that revert on narrowing conversions.
- Provide a migration plan: map existing reqId/seqNum records to the correct full proposal ID, and block follow-up operations that reference a truncated ID until reconciled.
- Update off-chain agent logic to read and use the full proposal ID (or the composite key, if eras are introduced) and stop relying on a truncated field.
- Resolve the “// See UINT_ROLLOVER” comment by implementing the rollover guard or by widening the stored identifier so rollover is impossible within the contract’s lifetime.
- Add tests (including fuzzing past 65,535) to assert uniqueness of the acknowledged proposal reference and to prevent regressions.

## Vulnerable Code

```
function _createProp(address caller, uint40 seqNumEx, UUID reqId, uint expiredAt, PropType propType, bool isSealed)
        private returns(uint pid){
        _requireOnlyAgent(caller);            // Access control
        if (_paused) revert ContractPaused(); // Occurs before seqNum check for idempotence

        // General input validation

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return pid;

        if (block.timestamp >= expiredAt) revert InvalidInput(INVALID_PROP_EXPIRED);
        if (isEmpty(reqId)) revert InvalidInput(INVALID_PROP_REQ_ID);

        // General proposal init
        pid = ++_propsCreated;  // See UINT_ROLLOVER
        Prop storage prop = _proposals[pid];
        prop.pid = pid;
        prop.creator = caller;
        prop.createdAt = block.timestamp;
        prop.expiredAt = expiredAt;
        prop.eid = reqId;
        prop.propType = propType;
        prop.status = isSealed ? PropStatus.Sealed : PropStatus.Pending;

        // While not completely initialized, emit + CallRes here saves SIZE and functionally equiv vs happening later
        emit PropCreated(pid, reqId, caller, isSealed);
        _setCallRes(caller, seqNumEx, reqId, uint16(pid), 0, 0);

        // Proposal specific init happens next
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
