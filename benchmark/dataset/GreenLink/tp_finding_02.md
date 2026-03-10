# Batch Transfer History Limit Bypass via First-ID HistoryLength Misuse


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

Vulnerability Identification:
The safeBatchTransferFrom function reads the transfer history length only once—using ids[0]—and reuses that single historyLength value for every NFT ID in the batch. It never recalculates each id’s own history length. As a result, if ids[0] has a small history count, the MAX_TRANSFER_HISTORY_LENGTH check (historyLength > 500) passes for all subsequent IDs, even if those IDs have individually exceeded the history cap. This is a logical flaw: the per-ID history limit is only enforced using the first ID’s history length, allowing all other IDs in the batch to bypass the limit.

Exploit Demonstration:
1. Precondition: You are partyA (the original receiver) for two NFTs, idA and idB.
   • idA.transferHistory.length = 0 (fresh NFT).
   • idB.transferHistory.length = 501 (> MAX_TRANSFER_HISTORY_LENGTH).
2. You still hold at least 1 token of idB and you want to transfer it despite idB being at its history cap.
3. Construct a batch transfer call: safeBatchTransferFrom(from = your address, to = victim, ids = [idA, idB], values = [1, 1], data = "0x").
4. Execution flow:
   a. historyLength ← nftTransferHistory[idA].length = 0.
   b. Loop i=0 (idA):
      – Checks historyLength (0) ≤ 500 → passes.
      – Pushes to idA.history, historyLength++ → historyLength = 1.
   c. Loop i=1 (idB):
      – Still checks historyLength (1) ≤ 500 → passes, even though idB.actual history length was 501.
      – Pushes to idB.history, bypassing its per-ID cap.
5. The transaction succeeds, transferring idB tokens to the victim and appending to idB’s history, despite idB already exceeding MAX_TRANSFER_HISTORY_LENGTH.

Impact: An attacker (as partyA) can bypass the per-ID MAX_TRANSFER_HISTORY_LENGTH restriction for any NFT in a batch by placing a fresh NFT ID first, thereby resetting the historyLength check and permitting transfers of fully-capped NFTs.

## Vulnerable Code

```
function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public virtual override {
        address operator = _msgSender();
        uint256 historyLength = _getNFTStorage().nftTransferHistory[ids[0]].length;
        uint40 nowTime = uint40(block.timestamp);
        for (uint256 i = 0; i < ids.length;) {
            uint256 id = ids[i];
            NFTMetadata storage mt = _getNFTStorage().nfts[id];
            address nftPartyA = mt.partyA;
            if (nftPartyA != from || to == nftPartyA) {
                revert TransferNotAllowed();
            }
            // Only before the execution date can it be transferred.
            if (mt.status != NFTStatus.CREATED || nowTime > mt.executionDate.startTime) {
                revert TransferNotAllowed();
            }
            if (historyLength > MAX_TRANSFER_HISTORY_LENGTH) {
                revert MaxTransferExceed(id);
            }
            _updateTotalHold(id, to, values[i], true);
            _updateTotalHold(id, from, values[i], false);
            _getNFTStorage().nftTransferHistory[id].push(to);
            historyLength++;
            unchecked {
                i++;
            }
        }
        super.safeBatchTransferFrom(from, to, ids, values, data);
        emit BatchNFTTransferred(operator, from, to, ids, values);
    }
```

## Related Context

```
_msgSender ->     function _msgSender() internal view virtual override(Context, ContextUpgradeable) returns (address) {
        return ContextUpgradeable._msgSender();
    }

_getNFTStorage ->     function _getNFTStorage() internal pure returns (NFTStorage storage $) {
        assembly {
            $.slot := NFT_STORAGE_LOCATION
        }
    }

_updateTotalHold ->     function _updateTotalHold(uint256 nftId, address account, uint256 amount, bool increase) internal {
        mapping(NFTStatisticsType => uint256) storage r = _getNFTStorage().nftActivityLedger[nftId][account];
        if (increase) {
            r[NFTStatisticsType.TOTAL_HOLD] += amount;
        } else {
            r[NFTStatisticsType.TOTAL_HOLD] -= amount;
        }
    }
```
