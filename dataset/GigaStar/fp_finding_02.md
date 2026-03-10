# Reentrancy via external xferMgr.propExecute can double-execute proposal transfers (Impacts: 2, 4, 11)


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | 🟠 Major |
| Triage Verdict | ❌ Invalid |
| Source | aiflow_scanner_llm_reverse |
| Scan Model | gpt-5.2 |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/Vault.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/Vault.sol
- **Lines:** 1–1

## Description

Impacts: (2) assets in the vault can be drained; (4) users’/vault funds can be extracted; (11) proposal state can be manipulated into inconsistent/incorrect execution status.

Vulnerability: `execXferProp()` performs an external call to an untrusted/upgradeable component (`xferMgr.propExecute(pid)`) before it commits any “in-progress/finalized” state in the `Vault` proposal record. Specifically, when `status == PropStatus.Passed` it only sets `prop.status = Executing` **after** the external call returns non-Done; and when `result.rc == Done` it calls `_onPropExecuted` only **after** the external call returns. There is no reentrancy guard around `execXferProp` and no state is set pre-call to prevent re-entry for the same `pid`.

If `xferMgr.propExecute` (or a token hook / callback it triggers) can re-enter `Vault.execXferProp` (e.g., via an Agent contract calling back, or via ERC777/receiver hooks depending on internal transfer mechanisms), the re-entrant call will observe the proposal still in `Passed`/`Executing` (because the outer call hasn’t updated it yet) and can execute the same transfer page(s) again. This can lead to duplicated transfers for a single proposal, draining vault assets.

Exploit scenario (no privileged roles beyond being an “Agent” caller, which is already required by the function):
1) A proposal `pid` is in `Passed` and contains one or more transfers from the vault.
2) Attacker controls (or influences) the execution path of `xferMgr.propExecute` such that during execution it makes an external call that re-enters the vault (e.g., a crafted recipient contract or token with callbacks), and the re-entrant call invokes `execXferProp(pid)` again as an Agent.
3) Because the vault hasn’t set `prop.status` to a final/locked state pre-call, the re-entrant invocation passes the same status checks and calls `xferMgr.propExecute(pid)` again.
4) Transfers are executed twice (or more) before `_onPropExecuted` is finally reached, resulting in vault funds being paid out multiple times.

Root cause: Checks-effects-interactions violation. The vault relies on `xferMgr` to execute transfers but does not preemptively lock proposal execution state (nor use a reentrancy guard) before the external call, enabling same-`pid` reentrancy and repeated execution.

## Recommendation

- Apply checks-effects-interactions in `execXferProp`. Before calling `xferMgr.propExecute(pid)`, validate the proposal is eligible and immediately persist a lock by transitioning the proposal to a non-reenterable state (e.g., `Executing`) or setting a per-`pid` execution mutex. Revert if the proposal is already in `Executing`/`Executed`.
- Add a reentrancy guard to `execXferProp` (and any internal path it reaches) to block nested invocations from token receiver hooks or `xferMgr` callbacks.
- Maintain the locked state across paginated executions. If `result.rc != Done`, keep the proposal in `Executing` for subsequent calls; only when `result.rc == Done` finalize atomically by marking it executed and invoking `_onPropExecuted`.
- Do not swallow external-call reverts; ensure failures bubble so pre-call state changes roll back.
- As a defense-in-depth measure, constrain `xferMgr` upgradeability (e.g., timelocks/approvals) and prefer token transfer mechanisms that do not invoke arbitrary callbacks.

## Vulnerable Code

```
function execXferProp(uint40 seqNumEx, UUID reqId, uint pid) external override{
        address caller = msg.sender;
        _requireOnlyAgent(caller); // Access control

        if (_paused) revert ContractPaused(); // Occurs after seqNum check for idempotence

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        Prop storage prop = _proposals[pid];
        (bool expired, PropStatus status) = _lazySetExpired(pid, prop);
        IXferMgr xferMgr = IXferMgr(_contracts[CU.XferMgr]);

        // slither-disable-next-line uninitialized-local (zero-init is ok)
        ICallTracker.CallRes memory result;
        if (status == PropStatus.Executed) {
            result.count = uint16(xferMgr.getXfersLen(pid));
            result.rc = uint16(IXferMgr.ExecXferRc.Done);
        } else if (expired || !(status == PropStatus.Executing || status == PropStatus.Passed)) {
            result.rc = uint16(IXferMgr.ExecXferRc.PropStat);
        } else {
            // Delegate the execution to reduce contract size
            result = xferMgr.propExecute(pid);
            if (result.rc == uint16(IXferMgr.ExecXferRc.Done)) {
                _onPropExecuted(pid, prop.eid, prop);
            } else if (status == PropStatus.Passed) {
                prop.status = PropStatus.Executing; // Value in a proposal after 1st page exec and before done
            }
        }
        _setCallRes(caller, seqNumEx, reqId, result.rc, result.lrc, result.count); // See SET_CR_LESS_SIGS
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

function _onPropExecuted(uint pid, UUID reqId, Prop storage prop) private{
        prop.executedAt = block.timestamp;
        prop.status = PropStatus.Executed;
        emit PropExecuted(pid, reqId);
    }

function getXfersLen(uint pid) external view override returns(uint){
        return _proposals[pid].xfers.length;
    }

function _lazySetExpired(uint pid, Prop storage prop) private returns(bool expired, PropStatus status){
        status = prop.status;
        expired = prop.expiredAt <= block.timestamp; // See BLOCK_TIMESTAMP
        if (expired && !_isFinal(status)) {
            prop.status = status = PropStatus.Expired;
            emit PropExpired(pid, prop.eid, prop.expiredAt);
        }
    }

function _isFinal(PropStatus status) private pure returns(bool){
        return status < PropStatus.FinalPartition;
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
