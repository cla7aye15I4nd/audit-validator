# Missing event on setPoolCriteria activation


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./source_code/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The function setPoolCriteria changes contract state by setting isUpdateCriteriaActive to true and updating lastUpdatePoolCriteriaTimestamp and _updateCriteriaPoolIds, but does not emit any event at this initial activation step.Emit a new event (e.g., PoolsCriteriaUpdateStarted) immediately after activating criteria update to log the beginning of the update process.1. Owner calls setPoolCriteria([0], [newCriteria], 100). 2. Observe that isUpdateCriteriaActive becomes true and pools[0] criteria updated. 3. No event is emitted to indicate activation of criteria update.

## Recommendation

Emit a new event (e.g., PoolsCriteriaUpdateStarted) immediately after activating criteria update to log the beginning of the update process.

## Vulnerable Code

```
function setPoolCriteria(...) external onlyOwner {
    if (!isUpdateCriteriaActive) {
        ...
        lastUpdatePoolCriteriaTimestamp = block.timestamp;
        isUpdateCriteriaActive = true;
        _updateCriteriaPoolIds = poolIds;
    }
    ...
}
```
