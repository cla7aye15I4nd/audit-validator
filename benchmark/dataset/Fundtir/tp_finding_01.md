# Dividend eligibility miscalculation in `_eligibleAt()`


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `e7e5e820-8d8b-11f0-9082-8d49bdd37ed2` |
| Commit | `69237546050132f2b550a0e4c766770c981a7341` |

## Location

- **Local path:** `./source_code/github/CertiKProject/certik-audit-projects/69237546050132f2b550a0e4c766770c981a7341/projects/fundtir/base/contracts/FundtirStaking.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e7e5e820-8d8b-11f0-9082-8d49bdd37ed2/source?file=$/github/CertiKProject/certik-audit-projects/69237546050132f2b550a0e4c766770c981a7341/projects/fundtir/base/contracts/FundtirStaking.sol
- **Lines:** 537–538

## Description

The function `_eligibleAt(user, atTimestamp)` returns true if the user has at least one unwithdrawn stake past the `MIN_DIVIDEND_LOCK`. This is compatible with the natspec given in the body of `claimFromDistribution()`:
```solidity=513
        // Eligibility: user must have at least one active stake whose startTime + MIN_DIVIDEND_LOCK <= distribution timestamp
```
However:
- `_computeEligibleTotalAt()` counts the entire `_currentStaked` balance once `_eligibleAt()` passes, independently of which stakes have reached `MIN_DIVIDEND_LOCK`. 
- `claimFromDistribution()` then calculates a user’s share using `stakedAtBlock(user, d.snapshotBlock)`, again including all stake amounts  independently of  which stakes have reached `MIN_DIVIDEND_LOCK`.

This design is dangerous, as it allows front- and back-running, and lets a user pass eligibility with a minimal matured stake, but compute dividends based on all newly added stakes, diluting rewards for long-term stakers. Privileged actors can also exploit snapshot timing to favor specific users.

Additionally, `_eligibleAt()` scans the full `stakes[user]` array but only returns a boolean, wasting gas and negating some of the efficiency potentially allowed by checkpointing.

## Recommendation

We recommend that the dividend eligibility and distribution logic be redesigned to ensure that only matured, unwithdrawn stakes are considered when computing both eligibility and dividend shares. This avoids accidental over-allocation, removes systemic incentives for participants to exploit timing, and ensures consistent and fair treatment across all users.

## Vulnerable Code

```
function claimFromDistribution(uint256 distributionId) external nonReentrant {
        Distribution memory d = distributions[distributionId];
        require(d.exists, "No such distribution");
        require(!hasClaimed[distributionId][msg.sender], "Already claimed");

        // Eligibility: user must have at least one active stake whose startTime + MIN_DIVIDEND_LOCK <= distribution timestamp
        require(_eligibleAt(msg.sender, d.timestamp), "Not eligible for this distribution");

        // Determine stake at snapshot
        uint256 userStake = stakedAtBlock(msg.sender, d.snapshotBlock);
        require(userStake > 0, "No stake at snapshot");

        uint256 share = (userStake * d.totalAmount) / d.eligibleTotal;
        require(share > 0, "Zero share");

        hasClaimed[distributionId][msg.sender] = true;

        // Always pay dividends in USDT
        usdtToken.safeTransfer(msg.sender, share);

        emit DividendClaimed(distributionId, msg.sender, share);
    }

    /**
     * @dev Internal function to check if a user is eligible for dividend at a specific timestamp
     * @param user Address of the user
     * @param atTimestamp Timestamp to check eligibility at
     * @return True if user is eligible (has stake >= MIN_DIVIDEND_LOCK)
     */
    function _eligibleAt(address user, uint256 atTimestamp) internal view returns (bool) {
        Stake[] memory arr = stakes[user];
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i].withdrawn) continue;
            if (arr[i].startTime + MIN_DIVIDEND_LOCK <= atTimestamp) return true;
        }
        return false;
    }

    /**
     * @dev Internal function to compute total eligible stake amount at a specific timestamp
     * @param atTimestamp Timestamp to compute eligible total at
     * @return Total amount of eligible stakes
     */
    function _computeEligibleTotalAt(uint256 atTimestamp) internal view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < stakeHolders.length; i++) {
            address u = stakeHolders[i];
            if (_eligibleAt(u, atTimestamp)) {
                sum += _currentStaked[u];
            }
        }
        return sum;
    }

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Allows admin to deposit tokens to the contract (used for dividend distributions)
     * @param tokenAddr Address of the token to deposit
     * @param amount Amount of tokens to deposit
     *
```
