# Unbounded Loop in batchTransfer Potentially Causes Gas Exhaustion


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ❌ Invalid |
| Triage Reason | not important enough |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The batchTransfer function loops over the entire dynamic toList array without any limit, allowing for unbounded iteration that can consume all gas.Impose a maximum limit on the batch size (e.g., cap toList length) or process transfers in fixed-size chunks with pull-based claims.1. Attacker prepares two arrays: toList and amountList of length 10000.
2. Calls batchTransfer(toList, amountList) with 10000 entries.
3. The loop will attempt 10000 transfers in one transaction, exceeding the block gas limit and reverting.
4. Normal users can no longer execute batchTransfer at all, causing denial of service.

## Recommendation

Impose a maximum limit on the batch size (e.g., cap toList length) or process transfers in fixed-size chunks with pull-based claims.

## Vulnerable Code

```
function batchTransfer(address[] memory toList, uint256[] memory amountList) external whenNotPaused {
    uint256 len = toList.length;
    if (len != amountList.length) {
        revert InvalidRecipientAndAmount();
    }
    for (uint256 i = 0; i < len;) {
        transfer(toList[i], amountList[i]);
        unchecked {
            i++;
        }
    }
}
```
