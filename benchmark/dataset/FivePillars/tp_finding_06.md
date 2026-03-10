# Gross Deposit Amount Used for Pool Rewards Instead of Net


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

In the `deposit` function, after collecting the fee and burning the net deposit (`toInvestor = amount – fee`), the contract calls:

    _updatePoolRewards(amount, investorAddress, investor.referer);

– Using the full original `amount` (including the deducted fee) to calculate pool rewards.  In effect, pools are credited on tokens that were never actually credited to the user’s deposit balance.

Exploit (practical demonstration):

1. Pre-condition: An address (Attacker) has already qualified for a pool (e.g. Pool 0) by making a one-time large deposit so that `accountToInvestorInfo[Attacker].totalDeposit >= personalInvestRequired`.
2. Wait at least `depositDelay` (4 h) since the last deposit.
3. Call `deposit(1 token, address(0))`:
   • The contract computes `fee = 1 token × depositFeeInBp/BASIS_POINTS` and `toInvestor = 1 token – fee`.
   • It burns `toInvestor` and holds the `fee`.
   • Because the attacker is already in the pool, `_updatePoolRewards` runs for Pool 0 and does:
       pool0.curReward += 1 token × pool0.share / BASIS_POINTS
     (i.e. it credits rewards on the full 1 token, not the net ~0.9 token).
4. Wait one full reward round (24 h) for pool rewards to accrue.
5. Call `claimReward()`:
   • The attacker’s only unclaimed reward is the inflated pool reward (because they are the sole Pool 0 participant).
   • They receive the entire `curReward` minted back to them.
6. Repeat steps 2–5 every 4 h to continuously inflate and harvest small extra pool rewards on tokens that were never actually retained as a deposit.

Because pool rewards are calculated on the pre-fee `amount` instead of the net `toInvestor`, an already-qualified participant can repeatedly deposit minimal net value but trigger rewards as if they had deposited the full amount.

## Vulnerable Code

```
function deposit(uint256 amount, address referer) external NotInPoolCriteriaUpdate {
        address investorAddress = _msgSender();
        InvestorInfo storage investor = accountToInvestorInfo[investorAddress];
        if (
            block.timestamp < startTimestamp ||
            block.timestamp - investor.lastDepositTimestamp < depositDelay
        ) revert DepositNotYetAvailable();

        (uint256 toInvestor, uint256 fee) = _calcFee(amount, depositFeeInBp);
        fivePillarsToken.transferFrom(investorAddress, address(this), fee);
        fivePillarsToken.burnFrom(investorAddress, toInvestor);

        if (referer != address(0)) {
            if (investor.totalDeposit > 0) revert RefererAlreadySetted();
            if (investorAddress == referer) revert InvalidReferer();
            investor.referer = referer;
        }
        bool isFirstDeposit = investor.totalDeposit == 0;
        if (isFirstDeposit) {
            _checkDepositOrClaimAmount(amount);
            investor.referer = referer;
            _checkRefererCirculation(referer);
            _investors.push(investorAddress);
            if (isWhitelisted[investorAddress][7] || isWhitelisted[investorAddress][8]) onlyWhitelistedInvestorsCount -= 1;
        }
        if (investor.referer != address(0)) _updateReferers(investor.referer, toInvestor, isFirstDeposit);
        _updatePoolRewards(amount, investorAddress, investor.referer);

        (uint256 totalDailyReward, uint256 lastDailyReward) = _calcInvestorDailyReward(investor);
        if (totalDailyReward > 0) {
            investor.lastDailyReward = lastDailyReward;
        }
        investor.accumulatedReward += totalDailyReward;
        investor.lastDepositTimestamp = uint32(block.timestamp);
        investor.totalDeposit += toInvestor;
        totalDepositAmount += toInvestor;

        emit Deposit(investorAddress, investor.referer, toInvestor);

        _trySendFees();
    }
```

## Related Context

```
_calcFee ->     function _calcFee(uint256 amount, uint256 feeInBp) internal pure returns(uint256 toInvestor, uint256 fee) {
        fee = amount * feeInBp / BASIS_POINTS;
        toInvestor = amount - fee;
    }

_checkDepositOrClaimAmount ->     function _checkDepositOrClaimAmount(uint256 amount) internal pure {
        if (amount < 10 ** 18) revert SmallDepositOrClaimAmount();
    }

_checkRefererCirculation ->     function _checkRefererCirculation(address referer) internal view {
        address directReferer = referer;
        if (referer != address(0)) {
            for (uint i = 0; i < 9; i++) {
                referer = accountToInvestorInfo[referer].referer;
                if (referer == address(0)) break;
                if (referer == directReferer) revert RefererCirculationDetected();
            }
        }
    }

_updateReferers ->     function _updateReferers(address referer, uint256 amount, bool isFirstDeposit) internal {
        _updateInvestorRefReward(referer);

        accountToInvestorInfo[referer].directRefsDeposit += amount;
        if (isFirstDeposit) accountToInvestorInfo[referer].directRefsCount += 1;

        for (uint i = 0; i < 9; i++) {
            referer = accountToInvestorInfo[referer].referer;
            if (referer == address(0)) break;
            _updateDownlineReferer(referer, amount, isFirstDeposit);
        }
    }

_updatePoolRewards -> function _updatePoolRewards(uint256 amount, address investor, address referer) internal {
        InvestorInfo memory investorInfo = accountToInvestorInfo[investor];
        InvestorInfo memory refererInfo = accountToInvestorInfo[referer];
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(uint32(lastUpdatePoolRewardTimestamp));
        for (uint8 i = 0; i < 7; i++) {
            PoolInfo storage poolInfo = pools[i];
            bool isPoolActive = poolInfo.isActive;

            if (isPoolActive) _updatePoolReward(poolInfo, endedRounds);

            bool isAddedToPool = _checkAndAddInvestorToPool(poolInfo, i, investorInfo, investor);
            if (referer != address(0)) {
                isAddedToPool = isAddedToPool || _checkAndAddInvestorToPool(poolInfo, i, refererInfo, referer);
            }

            if (!isPoolActive) {
                if (isAddedToPool) {
                    poolInfo.isActive = true;
                } else {
                    break;
                }
            }

            poolInfo.curReward += amount * poolInfo.share / BASIS_POINTS;
        }
        for (uint8 i = 7; i < 9; i++) {
            PoolInfo memory poolInfo = pools[i];
            if (poolInfo.isActive) {
                _updatePoolReward(pools[i], endedRounds);
                pools[i].curReward += amount * poolInfo.share / BASIS_POINTS;
            }
        }

        lastUpdatePoolRewardTimestamp = block.timestamp;
    }

_calcInvestorDailyReward -> function _calcInvestorDailyReward(InvestorInfo memory investorInfo) internal view returns(uint256, uint256) {
    uint32 lastUpdate = investorInfo.lastDepositTimestamp > investorInfo.lastClaimTimestamp ? investorInfo.lastDepositTimestamp : investorInfo.lastClaimTimestamp;
    uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(lastUpdate);
    uint256 roundReward = investorInfo.totalDeposit * 30000 / BASIS_POINTS;

    return (roundReward * endedRounds, roundReward);
}

_trySendFees ->     function _trySendFees() internal {
        uint256 accumulatedFees = fivePillarsToken.balanceOf(address(this));
        uint256 amountOutMin = accumulatedFees * minSwapPrice / 10 ** 18;
        if(accumulatedFees > 0) {
            fivePillarsToken.approve(dexRouter, accumulatedFees);
            address[] memory path = new address[](2);
            path[0] = address(fivePillarsToken);
            path[1] = IPancakeRouter01(dexRouter).WETH();
            (bool success, ) = dexRouter.call(abi.encodeWithSelector(
                IPancakeRouter01.swapExactTokensForETH.selector,
                accumulatedFees,
                amountOutMin,
                path,
                address(this),
                block.timestamp
            ));
            if (!success) {
                fivePillarsToken.approve(dexRouter, 0);
                emit SwapFeesFailed(accumulatedFees);
                return;
            }

            uint256 firstTreasuryAmount = address(this).balance * 70 / 100;
            (success,) = payable(treasury).call{value: firstTreasuryAmount}("");
            if (!success) revert SendEtherFailed(treasury);

            (success,) = payable(treasury2).call{value: address(this).balance}("");
            if (!success) revert SendEtherFailed(treasury2);
        }
    }
```
