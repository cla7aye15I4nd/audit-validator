# Membership Check Uses Stale Investor State, Blocking Single-Deposit Pool Entry


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟢 Minor |
| Triage Verdict | ✅ Valid |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./source_code/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

In _checkAndAddInvestorToPool, the code tests the three membership criteria (totalDeposit, directRefsCount and directRefsDeposit) against a memory‐copied InvestorInfo snapshot. However, in the deposit flow the contract calls _updatePoolRewards (which invokes _checkAndAddInvestorToPool) before it ever updates investor.totalDeposit in storage. As a result: on the very transaction that pushes an investor’s totalDeposit across the personalInvestRequired threshold, the in-memory InvestorInfo still shows the old (too low) totalDeposit, so the investor fails the check and is not added to the pool. The investor only enters the pool on a subsequent deposit, when the updated totalDeposit is picked up in the fresh memory snapshot.

Exploit (to reproduce and confirm the bug):
1. Identify a pool (poolId = N) whose personalInvestRequired you can meet exactly with a single deposit.  
2. From a fresh EOA, call deposit(amount = personalInvestRequired + fee, referer = address(0)).  
   - The deposit succeeds and investor.totalDeposit in storage becomes ≥ personalInvestRequired.  
   - However, because _updatePoolRewards ran first, it saw an in-memory totalDeposit of zero and did not add you to pool N.  
   - Confirm by reading isInvestorInPool[yourAddress][N] → false, and pools[N].participantsCount unchanged.
3. Wait out depositDelay (4 hours).  
4. Call deposit(amount = 1 wei, referer = address(0)).  
   - Now _updatePoolRewards sees investor.totalDeposit ≥ personalInvestRequired (from step 2) in the new memory snapshot, so _checkAndAddInvestorToPool passes.  
   - The mapping isInvestorInPool[yourAddress][N] flips to true, pools[N].participantsCount increments by 1, and poolRewardPerInvestorPaid[N] is initialized.

Impact: An investor who meets the personal investment requirement in one large deposit cannot join the pool until making a second (even trivial) deposit. This misplaced use of a stale memory snapshot introduces a two-step requirement where a single deposit should suffice.

## Vulnerable Code

```
function _checkAndAddInvestorToPool(
        PoolInfo memory poolInfo,
        uint8 poolId,
        InvestorInfo memory investorInfo,
        address investor
    ) internal returns(bool) {
        if (!isInvestorInPool[investor][poolId]) {
            if (
                investorInfo.totalDeposit >= poolInfo.personalInvestRequired &&
                investorInfo.directRefsCount >= poolInfo.directRefsRequired && 
                investorInfo.directRefsDeposit >= poolInfo.totalDirectInvestRequired
            ) {
                isInvestorInPool[investor][poolId] = true;
                pools[poolId].participantsCount += 1;
                accountToInvestorInfo[investor].poolRewardPerInvestorPaid[poolId] = poolInfo.rewardPerInvestorStored;
                return true;
            }
        }

        return false;
    }
```
