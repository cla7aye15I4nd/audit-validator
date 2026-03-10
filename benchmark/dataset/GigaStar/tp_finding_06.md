# Upgrade sequencing leaves _seqNums inconsistent, allowing seqNum reuse after an upgrade and overwriting the upgrade’s ReqAck/CallRes


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | info |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./source_code/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/ContractUser.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/ContractUser.sol
- **Lines:** 1–1

## Description

When seqNumEx>0, preUpgrade advances the caller’s expected sequence number via _isReqReplay (sets _seqNums[caller]=seqNumEx+1) and stages _nextUpgradeSeqNum=seqNumEx+1 for the subsequent upgrade. However, the actual upgrade path (_authorizeUpgradeImpl) records a CallRes at _nextUpgradeSeqNum but does not advance _seqNums again. As a result, the next off-chain write call from the same caller is accepted with the same seqNum as the upgrade (because nextExpected remains seqNumEx+1), and will overwrite _crBySeqNum[caller][seqNumEx+1], erasing the upgrade’s recorded result and potentially breaking later replay/diagnostics for that seqNum.

Recommended fix: on successful upgrade authorization, advance the caller’s expected sequence number (e.g., _seqNums[msg.sender]=_nextUpgradeSeqNum+1 when sequencing is in use), or redesign staging so preUpgrade does not consume a seqNum while upgrade does (but ensure one consistent seqNum progression across the two-step flow).

## Recommendation

Ensure a single, monotonic seqNum progression across preUpgrade and the upgrade path. After recording the upgrade’s ReqAck/CallRes at _nextUpgradeSeqNum, advance the caller’s expected sequence number (e.g., _seqNums[msg.sender]=_nextUpgradeSeqNum+1 when sequencing is in use). Alternatively, do not advance _seqNums in preUpgrade and only consume/advance the seqNum during the upgrade, so off-chain writes using the upgrade’s seqNum are rejected and cannot overwrite _crBySeqNum[caller][_nextUpgradeSeqNum].

## Vulnerable Code

```
function preUpgrade(uint40 seqNumEx, UUID reqId, UUID reqIdStage) external override {
        address caller = msg.sender;
        _requireVaultOrAdminOrCreator(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        if (isEmpty(reqId)) revert EmptyReqId();

        _nextUpgradeSeqNum = seqNumEx + 1;
        _nextUpgradedReqId = reqIdStage;

        _setCallRes(caller, seqNumEx, reqId, true); // For off-chain sequencing
    }
```
