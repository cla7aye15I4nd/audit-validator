# Infinite Loop in isMet Causing Denial-of-Service for >255 Conditions


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Context not considerred |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/lib/Types.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/lib/Types.sol
- **Lines:** 1–1

## Description

Vulnerability Description:
The for-loop in isMet uses a uint8 counter `i` but compares it against a uint256 `conditionsLength`. When `conditionsLength` exceeds 255, the unchecked `i++` wraps back to 0 after hitting 255, and the condition `i < conditionsLength` remains true indefinitely. As a result, any call that invokes isMet on an NFT with 256 or more conditions will loop infinitely until gas is exhausted, causing the transaction (or view call) to run out of gas and revert. Because isMet is the gatekeeper for all on-chain flows that check condition satisfaction, an attacker can permanently block any functionality that relies on it (e.g., settlement or status transitions).

Exploit Demonstration Steps:
1. In a test or script, construct an NFTMetadata struct whose `conditions` array has length 256 (the contents of each NFTCondition can be dummy/valid objects; their fields don’t matter for triggering the loop).
2. Invoke any external/public function on the contract that internally calls isMet(nft, <someTimestamp>). If no public wrapper exists, call isMet directly via a test harness or by adding a temporary public wrapper for testing.
3. Observe that the transaction (or view call) does not return and eventually consumes all gas, reverting with an out-of-gas error.
4. Confirm that reducing `conditions.length` to 255 or fewer allows the function to complete normally, demonstrating that the uint8 counter overflow is the root cause.

Impact:
An attacker can create or supply an NFT with at least 256 conditions and then invoke any operation that requires condition checking, causing a denial-of-service by permanently preventing those operations from succeeding.

## Vulnerable Code

```
function isMet(NFTMetadata storage nft, uint40 timestamp) internal view returns (bool, uint256) {
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
```

## Related Context

```
max ->     function max(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a : b;
    }
```
