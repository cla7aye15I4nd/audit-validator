# getSeqNum returns 1 even when seqNum=1 was already consumed/recorded (e.g., via __CallTracker_init), enabling silent overwrite and breaking idempotency invariants


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/CallTracker.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/CallTracker.sol
- **Lines:** 1–1

## Description

getSeqNum returns 1 whenever _seqNums[account] is 0. However, __CallTracker_init writes a CallRes at seqNum=1 for the creator without advancing _seqNums[creator]. As a result, after initialization getSeqNum(creator) still returns 1, causing the creator’s first tracked call to reuse seqNum=1 and overwrite the initialization CallRes in _crBySeqNum. This breaks the documented invariant that each (caller, seqNum) uniquely maps to one reqId, can make the initialization ReqAck/CallRes non-replayable by (caller,seqNum,reqId), and can confuse off-chain sequencing/reorg recovery logic (e.g., clients that assume init consumed seqNum=1 and start from 2 will hit SeqNumGap). Fix by advancing _seqNums during initialization (e.g., set _seqNums[creator]=2 when seeding seqNum=1) or by having getSeqNum account for a pre-seeded seqNum=1 record.

## Recommendation

- Treat the initialization record at seqNum=1 as consumed. During __CallTracker_init, advance the creator’s sequence so that getSeqNum(creator) returns 2 after initialization (e.g., set _seqNums for the creator accordingly).
- Alternatively, make getSeqNum account for a pre-seeded seqNum=1: if _seqNums[account] is 0 but a record exists at seqNum=1, return 2 instead of 1.
- Prevent silent overwrites by rejecting any write to _crBySeqNum[caller][seqNum] when an entry already exists for that (caller, seqNum).
- For existing deployments, perform a one-time migration on upgrade: if a creator has a record at seqNum=1 and _seqNums[creator]==0, advance their sequence so the next value returned is 2.
- Add tests covering initialization, first-call behavior, overwrite prevention, and off-chain sequencing assumptions.

## Vulnerable Code

```
function getSeqNum(address account) external view override returns(uint40 seqNumEx) {
        seqNumEx = _seqNums[account];
        return seqNumEx > 0 ? seqNumEx : 1;
    }
```
