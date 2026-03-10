# processCondition ignores allowedAction, allowing unauthorized condition rejection and forced full refund


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

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/NFT.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/NFT.sol
- **Lines:** 1–1

## Description

Vulnerability Identification:

The processCondition function never checks the allowedAction flag specified at NFT creation. As a result, an operator can call processCondition(..., approved=false, amount=0) on a condition that was configured with allowedAction=ApproveOnly (or even NoAction) and the function will record a rejection anyway. Because the internal _triggerPay routine treats any rejected required condition as “unreachable” (nft.isConditionsUnreachable() returns true) and immediately refunds the entire nft.amount to the original sender and finalizes the NFT, an operator can maliciously force a full refund and halt all further execution of the NFT.

Exploit Demonstration:

Preconditions:
- An NFT (ID = X) has been created with at least one condition at index Y.
- That condition was assigned to operator address O and configured with isPartial=true and allowedAction=ApproveOnly (i.e. it should only ever be approved).

Steps:
1. Wait until the blockchain timestamp is within the condition’s allowed date range.
2. From the operator address O, call:
   processCondition(
     nftId = X,
     externalId = 0,
     index = Y,
     approved = false,
     amount = 0
   )
3. Inside processCondition:
   - The code skips any check of condition.allowedAction.
   - It sees amount=0, so it allows a rejection.
   - It calls condStorage.setAction(false), setting condition.action to Action3.Reject.
4. Immediately after, processCondition invokes _triggerPay:
   - `_isNFTFinished` is false (NFT not yet finalized).
   - `nft.isConditionsUnreachable()` returns true because one of the required conditions is now rejected.
   - The contract calls `IERC20(tokenAddress).safeTransfer(nft.sender, nft.amount)`, refunding the full locked amount.
   - The NFT status is changed to NOT_SATISFIED_FINISH, preventing any further condition processing or token distribution.

Result:
Operator O, although not permitted to reject that condition, has bypassed the intended allowedAction restrictions, forced a full refund of the NFT’s underlying tokens to the original sender, and prematurely finalized the NFT contract in a failed state.

## Vulnerable Code

```
function processCondition(uint256 nftId, uint64 externalId, uint8 index, bool approved, uint256 amount) external {
        address operator = _msgSender();
        (NFTMetadata storage nft, NFTCondition storage condition) = _getNFTAndCondition(nftId, index, NFTStatus.CREATED);
        // Validate operator identity
        if (condition.operator != operator) {
            revert Unauthorized();
        }

        bool skipActionUpdate;
        Action3 action = condition.action;

        if (!condition.isPartial) {
            if (amount > 0) revert RequireZeroAmount();
            if (action != Action3.None) revert ActionAlreadyTaken();
        } else {
            if (amount > 0) {
                if (!approved) revert RequireNonZeroAmount();
                if (condition.confirmedAmount + amount > nft.amount) {
                    revert ExceedMaxAmount(condition.confirmedAmount, amount, nft.amount);
                }
            }
            if (action == Action3.Approve) {
                skipActionUpdate = true; // No need to update
            } else if (action != Action3.None) {
                revert ActionAlreadyTaken();
            }
        }

        NFTCondition storage condStorage = _getNFTStorage().nfts[nftId].conditions[index];
        condStorage.setActionTime(uint40(block.timestamp));
        condStorage.setAction(approved, skipActionUpdate);
        if (amount > 0) {
            condition.confirmedAmount += amount;
        }

        emit ProcessCondition(nftId, index, externalId, approved, amount);

        _triggerPay(nftId, nft);
    }
```

## Related Context

```
_getNFTAndCondition ->     function _getNFTAndCondition(uint256 nftId, uint8 index, NFTStatus requiredStatus)
        private
        view
        returns (NFTMetadata storage, NFTCondition storage)
    {
        NFTMetadata storage cond = _getNFTStorage().nfts[nftId];
        // Check if NFT status is CREATED
        if (cond.status != requiredStatus) {
            revert NFTInvalidState(nftId, requiredStatus, cond.status);
        }
        // Check if TA index is within valid range
        if (index >= uint8(cond.conditions.length)) {
            revert InvalidConditionIndex(index, cond.conditions.length);
        }
        // Check if in condition processing time
        NFTCondition storage condition = cond.conditions[index];
        if (!condition.date.isInRange(uint40(block.timestamp))) {
            revert ConditionNotInTimeRange();
        }
        return (cond, condition);
    }

_getNFTStorage ->     function _getNFTStorage() internal pure returns (NFTStorage storage $) {
        assembly {
            $.slot := NFT_STORAGE_LOCATION
        }
    }

setActionTime ->         function setActionTime(NFTCondition storage cond, uint40 timestamp) internal {
            if (cond.firstActionTime == 0) {
                cond.firstActionTime = timestamp;
            }
            cond.lastActionTime = timestamp;
        }

setAction ->     function setAction(NFTCondition storage cond, bool approved, bool skip) internal {
        if (!skip) {
            cond.action = approved ? Action3.Approve : Action3.Reject;
        }
    }

_triggerPay ->     function _triggerPay(uint256 nftId, NFTMetadata storage nft) private {
        if (_isNFTFinished(nft)) {
            return;
        }

        // Completely rejected, unable to meet conditions, direct refund
        if (nft.isConditionsUnreachable()) {
            IERC20(tokenAddress).safeTransfer(nft.sender, nft.amount);
            emit NFTRefunded(nftId, nft.sender, nft.amount);
            _changeNFTStatus(nftId, nft, NFTStatus.NOT_SATISFIED_FINISH);
            return;
        }

        uint40 nowTime = uint40(block.timestamp);
        if (nowTime < nft.executionDate.startTime) {
            return;
        }

        (bool isMet, uint256 maximumBenefit) = nft.isMet(nowTime);
        uint256 paidAmount = nft.paidAmount;

        if (isMet && maximumBenefit > paidAmount) {
            uint256 diff = maximumBenefit - paidAmount;
            nft.paidAmount += diff;
            if (paidAmount + diff == nft.amount) {
                _changeNFTStatus(nftId, nft, NFTStatus.FINISH);
            }
            // Payment
            address[] storage history = _getNFTStorage().nftTransferHistory[nftId];
            uint256 historyLength = history.length;
            for (uint256 i = 0; i < historyLength + 1;) {
                address to = i == historyLength ? nft.partyA : history[i];
                uint256 balance = minUint256(diff, super.balanceOf(to, nftId));
                if (balance > 0) {
                    _settle(nftId, to, balance);
                    diff -= balance;
                }
                if (diff == 0) {
                    break;
                }
                unchecked {
                    i++;
                }
            }
        }

        //////////////// Refund to sender ////////////////////
        // Liquidation, return unused tokens to the original sender
        if (nowTime >= _triggerTime(nft)) {
            uint256 diff = nft.amount - nft.paidAmount;
            if (diff > 0) {
                // Refund
                _refund(nftId, nft.sender, diff);
                _changeNFTStatus(nftId, nft, NFTStatus.PART_REFUND_FINISH);
            }
        }
    }
```
