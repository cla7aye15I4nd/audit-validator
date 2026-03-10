# Vote casting can revert due to underflow when voter set shrinks below countNay


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟢 Minor |
| Triage Verdict | ✅ Valid |
| Source | aiflow_scanner_codex |
| Project ID | `7b519e30-d10a-11f0-a5a1-c38d49d0912c` |
| Commit | `0b8edde27935e70ed3decbb30508bde926edf57c` |

## Location

- **Local path:** `./src/bd/bc-contract/contract/v1_0/Vault.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/7b519e30-d10a-11f0-a5a1-c38d49d0912c/source?file=$/github/GigaStarIo-public/vault-audit/0b8edde27935e70ed3decbb30508bde926edf57c/bd/bc-contract/contract/v1_0/Vault.sol
- **Lines:** 1–1

## Description

_castVote computes early-rejection with `_accountMgr.aris.voters.length - countNay < quorum`. Because `voters.length` is not snapshotted per proposal, it can decrease after a proposal is Sealed (e.g., via a later role proposal removing voters). If `countNay` (which includes votes from now-removed voters) becomes greater than the current `voters.length`, the subtraction underflows and reverts (Solidity 0.8+). This can block any further voting on that proposal (including Yay votes that do not immediately reach quorum), effectively DoSing proposal progression until it expires. Fix: guard the subtraction, e.g. treat `voters.length <= countNay` as immediately impossible-to-pass (reject), or compute remaining voters with a checked conditional before subtracting.

## Recommendation

- Snapshot the electorate size and quorum basis per proposal at the moment it is Sealed. Base all early-rejection and quorum checks on these snapshot values, not on `_accountMgr.aris.voters.length` at voting time.
- Guard the subtraction to prevent underflow: if the snapshot electorate size is less than or equal to `countNay`, short-circuit to “cannot pass” without subtracting; otherwise perform the comparison.
- Tally votes only from accounts included in the proposal’s snapshot; ignore votes from accounts added or removed after sealing to keep counts consistent with the snapshot.
- Add tests covering membership shrinking below `countNay` after sealing to ensure no reverts occur and the proposal is correctly rejected when it cannot reach quorum.

## Vulnerable Code

```
function _castVote(Prop storage prop, uint pid, bool approve, address voter) internal
        returns(CastVoteRes memory result) {
        mapping(address => Vote) storage votes = _votes[pid];
        // Voting only allowed while proposal is Sealed
        (bool expired, PropStatus status) = _lazySetExpired(pid, prop);
        if (expired || status != PropStatus.Sealed) { result.rc = CastVoteRc.Status; return result; }

        // Another vote for the same proposal? Proposal is not sealed so change is ok
        uint countYay = prop.countYay;
        uint countNay = prop.countNay;
        result.vote = votes[voter];
        if (result.vote != Vote.None) { // then already voted
            // Allow the vote to be changed (only when proposal is not final to avoid a zombie proposal apocalypse)
            if ((approve && result.vote == Vote.Yay) || (!approve && result.vote == Vote.Nay)) {
                result.rc = CastVoteRc.NoChange;
                return result;
            }

            // Reverse the previous vote
            if (result.vote == Vote.Yay) { --countYay; } else { --countNay; }
        }

        // Tally and record the vote
        if (approve) {
            ++countYay;
            result.vote = Vote.Yay;
        } else {
            ++countNay;
            result.vote = Vote.Nay;
        }
        prop.countYay = countYay;
        prop.countNay = countNay;
        votes[voter] = result.vote;
        UUID reqId = prop.eid;
        uint quorum = _accountMgr.quorum;

        // CONCURRENT_QUORUM: `quorum` may change while proposals are `Pending` hence the defensive '>= quorum'
        Vote propResult = countYay >= quorum ? Vote.Yay
            : (_accountMgr.aris.voters.length - countNay < quorum ? Vote.Nay : Vote.None);
        emit PropVoted(pid, reqId, voter, approve, propResult);

        if (propResult == Vote.Yay) {
            prop.status = PropStatus.Passed;

            // Execute proposals inline to:
            // 1) Provide a no-agent-veto path via on-chain sig, otherwise agent has potential for an
            //    implicit veto (ignore prop) if off-chain sig as the Agent does the relay
            // 2) Reduce bytecode by avoiding another execution function - This is a big motivation
            // NOTE: an execution that reverts will require another `Yay` vote to re-run after resolving the error
            if (prop.propType == PropType.Role) {
                AC.roleApplyRequestsFromStore(_accountMgr, _roleReqs[pid]); // may revert and uncast vote
                _onPropExecuted(pid, reqId, prop);
            } else if (prop.propType == PropType.Quorum) {
                uint newQuorum = prop.quorum;
                AC.setQuorum(_accountMgr, newQuorum); // may revert and uncast vote
                _onPropExecuted(pid, reqId, prop);
            } else if (prop.propType == PropType.FixDeposit) {
                // Xfer funds from deposit box(s) to corrected address(s)
                { // var scope to reduce stack pressure
                    FixDepositReq[] storage reqs = _fixDepositReqs[pid];
                    for (uint i = 0; i < reqs.length; ++i) {
                        FixDepositReq memory req = reqs[i];
                        IBox.PushResult memory pr =
                            IBoxMgr(_contracts[CU.BoxMgr]).push(req.instName, req.to, req.ti, req.qty);

                        if (pr.rc != IBox.PushRc.Success ) revert FixDepositFailed(pid, reqId, pr.rc); // Allow retry
                    }
                }
                _onPropExecuted(pid, reqId, prop);
            }
        } else if (propResult == Vote.Nay) { // then insufficient pending votes to pass
            prop.status = PropStatus.Rejected;
        }
        // result = CastVoteRc.Success; set implicitly via zero-value init
    }
```
