# Missing upper‐bound check on execution start timestamp allows PartyA to bypass timelock


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | — |
| Triage Verdict | ✅ Valid |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/NFT.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/NFT.sol
- **Lines:** 1–1

## Description

A logic bug in setExecutionStartTimestamp lets PartyA move the execution window entirely into the past and then immediately drain all funds. The function only checks

    if (timestamp < nft.createdAt) revert;

but never ensures that the provided timestamp—even after adding the relative offset—lies in the future relative to block.timestamp. Because executionDate.day > 0 for T1‐type NFTs, the actual start time is computed as

    startTime = timestamp + 86400 * executionDate.day;

If PartyA waits until more than executionDate.day days after creation, they can pass timestamp = nft.createdAt and get startTime = nft.createdAt + executionDate.day·86400, which is already in the past by the time of the call. The code then calls _createNFT (pulling and minting tokens) without locking the window in the future.

Since PartyA is also a condition operator, they can immediately call processCondition to mark the (single) condition approved. Inside processCondition, _triggerPay is invoked; its first line

    if (nowTime < nft.executionDate.startTime) return;

no longer holds (startTime < now), so the contract computes the full payout and calls _settle, burning the NFT and transferring the entire amount back to PartyA.

Exploit steps:
1. Sender mints an NFT via createNFTsFromTokens with:
   • executionDate.day = 1
   • one absolute condition whose operator is PartyA and whose date window includes the current time.
2. Wait > 1 day after creation so that block.timestamp > nft.createdAt + 86400.
3. PartyA calls setExecutionStartTimestamp(nftId, nft.createdAt):
   • timestamp = nft.createdAt passes the >= check.
   • startTime = nft.createdAt + 86400 < block.timestamp, so execution window is in the past.
   • needSetConditionDate=false → _createNFT runs, pulling and minting tokens.
4. PartyA immediately calls processCondition(nftId, extId, 0, true, 0):
   • Inside processCondition → _triggerPay is called.
   • Since now >= executionDate.startTime, the guard is bypassed and the contract pays out the full nft.amount via _settle.

Result: PartyA receives the entire deposit instantly, completely bypassing the intended delay.

## Vulnerable Code

```
function setExecutionStartTimestamp(uint256 nftId, uint40 timestamp) public {
        NFTMetadata storage nft = _getNFTStorage().nfts[nftId];
        // Check NFT status
        if (nft.status != NFTStatus.WAIT_EXECUTION_DATE) {
            revert NFTInvalidState(nftId, NFTStatus.WAIT_EXECUTION_DATE, nft.status);
        }
        // Check operator identity
        if (nft.partyA != _msgSender()) {
            revert Unauthorized();
        }
        // Validate start time range
        if (timestamp < nft.createdAt) {
            revert InvalidStartTime(timestamp, nft.createdAt);
        }
        // Get the maximum time from Conditions with time already set
        (uint40 maxTime, bool needSetConditionDate) = nft.conditions.getMaxTime();

        Date storage executionDate = nft.executionDate;
        uint40 startTimestamp = timestamp + 86400 * executionDate.day;
        uint40 endTimestamp = startTimestamp + 86400; /*1day*/
        // Require endTimestamp to be greater than or equal to the maximum time in conditions
        if (maxTime > endTimestamp) {
            revert InvalidEndTime(endTimestamp, maxTime);
        }
        executionDate.setTime(startTimestamp, endTimestamp);

        // If need to set time in Conditions, change the status
        if (needSetConditionDate) {
            _changeNFTStatus(nftId, nft, NFTStatus.WAIT_CONDITION_DATE);
        } else {
            // Otherwise create NFT directly
            _createNFT(nftId, nft);
        }

        emit SetExecutionStartTimestamp(nftId, startTimestamp, endTimestamp);
    }
```

## Related Context

```
_getNFTStorage ->     function _getNFTStorage() internal pure returns (NFTStorage storage $) {
        assembly {
            $.slot := NFT_STORAGE_LOCATION
        }
    }

getMaxTime ->     function getMaxTime(NFTCondition[] storage conditions)
        internal
        view
        returns (uint40 maxTime, bool needSetConditionDate)
    {
        uint256 conditionsLength = conditions.length;
        for (uint256 i = 0; i < conditionsLength;) {
            uint40 endTimestamp = conditions[i].date.endTime;
            if (endTimestamp != 0) {
                maxTime = endTimestamp > maxTime ? endTimestamp : maxTime;
            } else {
                needSetConditionDate = true;
            }
            unchecked {
                i++;
            }
        }
        return (maxTime, needSetConditionDate);
    }

setTime ->     function setTime(Date storage date, uint40 startTimestamp, uint40 endTimestamp) internal {
        date.startTime = startTimestamp;
        date.endTime = endTimestamp;
    }

_changeNFTStatus ->     function _changeNFTStatus(uint256 nftId, NFTMetadata storage nft, NFTStatus status) private {
        NFTStatus preStatus = nft.status;
        if (preStatus == status) {
            return;
        }
        nft.status = status;
        emit NFTStatusChanged(nftId, status, preStatus);
    }

_createNFT ->     function _createNFT(uint256 nftId, NFTMetadata storage nft) private {
        _changeNFTStatus(nftId, nft, NFTStatus.CREATED);
        nft.nftCreatedAt = uint40(block.timestamp);
        _swap(nft.sender, nft.partyA, nftId, nft.amount);
        _updateTotalHold(nftId, nft.partyA, nft.amount, true);
    }
```
