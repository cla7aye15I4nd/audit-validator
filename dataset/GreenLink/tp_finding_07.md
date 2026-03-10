# Partial AND Conditions Underpaid – MaximumBenefit Used Instead of Sum


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

- **Local path:** `./src/GLDB Pulse Contracts/ENT&Swap/NFT.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/NFT.sol
- **Lines:** 1–1

## Description

Vulnerability:
When an NFT is created with LogicType.AND and multiple partial conditions, _triggerPay calls nft.isMet() which returns (approvedCount==conditionsLength, maximumBenefit). maximumBenefit is calculated as the maximum per-condition confirmedAmount (or full amount for non-partial), not the sum of all confirmedAmounts. As a result, even if two or more partial conditions are each approved, the contract only pays out the single largest confirmedAmount and treats the rest as “unused” – refunding it to the sender instead of paying it to the receiver.

Exploit Demonstration (Step-by-Step):
1. Setup
   – Sender (Alice) approves the contract to spend 100 tokens.
   – Alice calls createNFTsFromTokens with nftId=1, amount=100, receiver=Bob, logic=AND, and two partial conditions:
     • Condition 0: operator=Bob, isPartial=true, date immediately active, allowedAction=ApproveOrReject
     • Condition 1: operator=Alice, isPartial=true, date immediately active, allowedAction=ApproveOrReject
2. Approve Both Conditions
   – Bob (partyA) calls processCondition(1, extId, 0, approved=true, amount=40).
     • cond0.confirmedAmount becomes 40.
     • _triggerPay sees now < executionDate.startTime → does nothing.
   – Alice (sender) calls processCondition(1, extId, 1, approved=true, amount=60).
     • cond1.confirmedAmount becomes 60.
     • Now block.timestamp ≥ executionDate.startTime; in _triggerPay:
       • isMet returns (approvedCount==2, maximumBenefit=max(40,60)=60).
       • paidAmount was 0 → diff=60.
       • paidAmount set to 60.
       • Burns 60 NFT-units and transfers 60 ERC20 tokens to holders (Bob).
       • paidAmount+diff != 100 → status remains CREATED.
3. Trigger Final Settlement
   – After all condition endTimes, an executor (with EXECUTE_ROLE) calls trigger(1).
     • block.timestamp ≥ _triggerTime → calls _triggerPay.
     • isMet returns (true, maximumBenefit=60), but paidAmount==60 → skip distribution.
     • now ≥ _triggerTime → final refund diff=100−60=40.
     • Sends 40 ERC20 tokens back to Alice and sets status PART_REFUND_FINISH.
4. Outcome
   – Bob (receiver) receives only 60 tokens (the maximum of the two partial approvals).
   – Alice gets back the remaining 40 tokens.

Expected behavior under AND logic is to pay out the sum of all partial approvals (40+60=100), but the contract only uses maximumBenefit=max(40,60)=60. This underpays Bob by 40 tokens and incorrectly refunds them to Alice.

## Vulnerable Code

```
function _triggerPay(uint256 nftId, NFTMetadata storage nft) private {
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

## Related Context

```
_isNFTFinished ->     function _isNFTFinished(NFTMetadata storage nft) private view returns (bool) {
        return nft.status == NFTStatus.FINISH || nft.status == NFTStatus.PART_REFUND_FINISH
            || nft.status == NFTStatus.NOT_SATISFIED_FINISH;
    }

isConditionsUnreachable ->     function isConditionsUnreachable(NFTMetadata storage nft) internal view returns (bool) {
        NFTCondition[] storage conditions = nft.conditions;
        LogicType logic = nft.logic;
        uint256 conditionsLength = conditions.length;
        
        // If there are no conditions, they can't be unreachable
        if (conditionsLength == 0) {
            return false;
        }
        
        uint256 rejectCount = 0;
        for (uint8 i = 0; i < conditionsLength;) {
            if (conditions[i].action == Action3.Reject) {
                if (logic == LogicType.AND) {
                    // For AND logic, any single rejection makes the entire set unreachable
                    return true;
                } else {
                    // For OR logic, count rejections to check if all are rejected
                    rejectCount++;
                }
            }
            unchecked {
                i++;
            }
        }
        
        // For OR logic, conditions are unreachable only if all are rejected
        return rejectCount == conditionsLength;
    }

_changeNFTStatus ->     function _changeNFTStatus(uint256 nftId, NFTMetadata storage nft, NFTStatus status) private {
        NFTStatus preStatus = nft.status;
        if (preStatus == status) {
            return;
        }
        nft.status = status;
        emit NFTStatusChanged(nftId, status, preStatus);
    }

isMet ->         function isMet(NFTMetadata storage nft, uint40 timestamp) internal view returns (bool, uint256) {
            NFTCondition[] storage conditions = nft.conditions;
            LogicType logic = nft.logic;
            uint256 conditionsLength = conditions.length;
            if (conditionsLength == 0) {
                return (true, nft.amount);
            }
            uint256 maximumBenefit;
            uint256 approvedCount;
            for (uint8 i = 0; i < conditionsLength;) {
                NFTCondition memory cond = conditions[i];
                bool ret;
                if (cond.allowedAction == AllowedAction.ApproveOrReject) {
                    if (cond.action == Action3.Approve) {
                        ret = true;
                    } else if (cond.action == Action3.None) {
                        ret = false;
                    } else {
                        ret = false;
                    }
                } else {
                    if (cond.action == Action3.Approve) {
                        ret = true;
                    } else if (cond.action == Action3.None) {
                        ret = timestamp >= cond.date.endTime;
                    } else {
                        ret = false;
                    }
                }
                if (ret) {
                    approvedCount++;
                    uint256 myAmount = cond.isPartial ? cond.confirmedAmount : nft.amount;
                    maximumBenefit = max(maximumBenefit, myAmount);
                }
                unchecked {
                    i++;
                }
            }
            if (logic == LogicType.AND) {
                // AND
                return (approvedCount == conditionsLength, maximumBenefit);
            } else {
                // OR
                return (approvedCount > 0, maximumBenefit);
            }
        }

minUint256 ->     function minUint256(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

_settle ->     /// @dev Internal function to settle an NFT - burns the NFT and transfers tokens to the account
    /// Also updates the activity ledger to record the realized amount
    /// @param nftId The ID of the NFT to settle
    /// @param account The address receiving the settlement
    /// @param amount The amount to settle
    function _settle(uint256 nftId, address account, uint256 amount) internal {
        _burn(account, nftId, amount);
        IERC20(tokenAddress).safeTransfer(account, amount);
        _getNFTStorage().nftActivityLedger[nftId][account][NFTStatisticsType.REALIZED] += amount;
        emit NFTRealized(nftId, account, amount);
    }

_triggerTime ->     function _triggerTime(NFTMetadata storage nft) private view returns (uint40) {
        (uint40 maxTime,) = nft.conditions.getMaxTime();
        maxTime = _maxTime(maxTime, nft.executionDate.startTime);
        return maxTime;
    }

_refund ->     /// @notice Internal function to refund tokens to an account
    function _refund(uint256 nftId, address account, uint256 amount) internal {
        IERC20(tokenAddress).safeTransfer(account, amount);
        emit NFTRefunded(nftId, account, amount);
    }
```
