# Infinite-loop DoS via uint8 index overflow in isConditionsUnreachable


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

Vulnerability Identification:
The function iterates over nft.conditions using a uint8 loop index (i) but compares it to conditionsLength (uint256). If conditions.length exceeds 255, i will overflow from 255 back to 0 and the loop’s exit condition (i < conditionsLength) remains true indefinitely. This is a logical flaw in the reachability check that turns into an infinite loop rather than terminating.

Exploit Demonstration:
1. Prepare an NFTMetadata struct with LogicType = AND (or OR) and append at least 256 NFTCondition entries.  
2. For AND logic: ensure none of the first 256 conditions have action == Action3.Reject (so the function does not early-return).  For OR logic: ensure rejectCount < conditionsLength during the first 256 iterations (e.g., only reject some of the first 256).  
3. Invoke any contract function that internally calls isConditionsUnreachable (for example a status check, refund eligibility or finalization call).  
4. Execution enters the for loop:
   • i starts at 0 and increments to 255, checking each condition.  
   • On i=255, it increments to 256, overflows to 0 (uint8), and since 0 < conditionsLength (256+), the loop continues.  
   • This repeats forever, consuming gas until the transaction runs out-of-gas and reverts.

Impact: An attacker who can create or set an NFT with more than 255 conditions can permanently block any operation that relies on this reachability check, resulting in a denial-of-service on that NFT’s lifecycle.

## Vulnerable Code

```
function isConditionsUnreachable(NFTMetadata storage nft) internal view returns (bool) {
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
```
