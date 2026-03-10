# Missing lower-bound validation allows misaligned condition windows


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Security control exists |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./src/GLDB Pulse Contracts/ENT&Swap/NFT.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/NFT.sol
- **Lines:** 1–1

## Description

The function setConditionStartTimestamp only checks that the computed condition end time (startTimestamp + 86400 * conditionDate.day) does not exceed executionDate.endTime, but never enforces that startTimestamp falls after or at executionDate.startTime (or within the originally agreed condition range). This allows a malicious PartyA to set the condition window entirely before or after the execution window, corrupting the NFT’s lifecycle and payment logic.

Exploit steps (sabotage scenario):
1. A user calls createNFTsFromTokens(...) supplying an absolute executionDate with startTime = T_execStart and endTime = T_execEnd, and a single relative condition (conditionDate.day = 1) assigned to the counter-party (the sender).
2. The NFT enters WAIT_CONDITION_DATE status. PartyA now calls:
   setConditionStartTimestamp(nftId, 0, startTimestamp = nft.createdAt)  // startTimestamp < T_execStart
   • Passes: startTimestamp ≥ createdAt, and endTimestamp = createdAt + 86400 ≤ T_execEnd.
3. conditionDate is set to [nft.createdAt, nft.createdAt + 86400], entirely before the execution window.
4. conditions.isAllConditionTimeSet() returns true ⇒ _createNFT is called, minting the NFT to PartyA.
5. The sender (condition operator) can no longer call processCondition because block.timestamp is now > conditionDate.endTime but < executionDate.startTime, so the condition window has expired.
6. When trigger() or an ExecuteRole call finally runs after T_execStart, _triggerPay sees the condition unreachable and refunds the deposited tokens to the sender, leaving PartyA with a minted NFT but no tokens.

Alternatively, PartyA could set startTimestamp = T_execEnd (and conditionDate.day=0) to create a window solely at execution end, then immediately call processCondition and collect the full payout prematurely. Both cases stem from missing a check that startTimestamp ≥ executionDate.startTime (and ≤ original conditionDate.startTime).**

Impact: PartyA can misalign or completely bypass the intended condition-processing window, leading either to an unjust refund or an unauthorized early payout.

## Vulnerable Code

```
function setConditionStartTimestamp(uint256 nftId, uint8 index, uint40 startTimestamp) public {
        NFTMetadata storage nft = _getNFTStorage().nfts[nftId];
        // Validate NFT status
        if (nft.status != NFTStatus.WAIT_CONDITION_DATE) {
            revert NFTInvalidState(nftId, NFTStatus.WAIT_CONDITION_DATE, nft.status);
        }
        // Validate operator identity
        if (nft.partyA != _msgSender()) {
            revert Unauthorized();
        }
        // Validate start time range
        if (startTimestamp < nft.createdAt) {
            revert InvalidStartTime(startTimestamp, nft.createdAt);
        }
        // Validate if index is correct
        NFTCondition[] storage conditions = nft.conditions;
        if (index >= conditions.length) {
            revert InvalidConditionIndex(index, conditions.length);
        }
        // Validate if already set, don't allow to set again
        Date storage conditionDate = conditions[index].date;
        if (conditionDate.isTimeSet()) {
            revert ConditionAlreadySetTime();
        }
        // Validate condition end time <= execution time end
        Date storage executionDate = nft.executionDate;
        uint40 endTimestamp = startTimestamp + 86400 * conditionDate.day;
        if (endTimestamp > executionDate.endTime) {
            revert ConditionEndTimeOutOfRange(endTimestamp, executionDate.endTime);
        }

        conditionDate.setTime(startTimestamp, endTimestamp);
        emit SetConditionStartTimestamp(nftId, index, startTimestamp);

        if (conditions.isAllConditionTimeSet()) {
            _createNFT(nftId, nft);
        }
    }
```

## Related Context

```
_getNFTStorage ->     function _getNFTStorage() internal pure returns (NFTStorage storage $) {
        assembly {
            $.slot := NFT_STORAGE_LOCATION
        }
    }

isTimeSet ->     function isTimeSet(Date storage date) internal view returns (bool) {
        return date.startTime != 0;
    }

setTime ->     function setTime(Date storage date, uint40 startTimestamp, uint40 endTimestamp) internal {
        date.startTime = startTimestamp;
        date.endTime = endTimestamp;
    }

isAllConditionTimeSet ->     function isAllConditionTimeSet(NFTCondition[] storage conditions) internal view returns (bool) {
        uint256 conditionsLength = conditions.length;
        for (uint256 i = 0; i < conditionsLength;) {
            if (!conditions[i].date.isTimeSet()) {
                return false;
            }
            unchecked {
                i++;
            }
        }
        return true;
    }

_createNFT -> function _createNFT(uint256 nftId, NFTMetadata storage nft) private {
        _changeNFTStatus(nftId, nft, NFTStatus.CREATED);
        nft.nftCreatedAt = uint40(block.timestamp);
        _swap(nft.sender, nft.partyA, nftId, nft.amount);
        _updateTotalHold(nftId, nft.partyA, nft.amount, true);
    }
```
