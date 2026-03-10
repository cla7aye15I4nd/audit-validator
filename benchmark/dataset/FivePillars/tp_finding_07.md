# Users Who Claim Rewards Before First Deposit Are Permanently Blocked from Setting a Referer


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./src/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The system determines if a deposit is a 'first deposit' by checking if `investor.totalDeposit == 0`. A referer can only be assigned during this first deposit. However, the `claimReward` function also increases an investor's `totalDeposit` through its redistribution mechanism. A user can earn referral or pool rewards and have a non-zero `accumulatedReward` without ever making a deposit. If such a user calls `claimReward()`, the redistribution logic will increase their `investor.totalDeposit`, making it greater than zero. Consequently, when this user later decides to make their actual first deposit by calling the `deposit()` function, the system will no longer consider it a 'first deposit' because their `totalDeposit` is already non-zero. This permanently prevents them from setting a referer, as the `RefererAlreadySetted` check will always fail for any subsequent deposit attempt with a non-zero referer address.

**Exploit Demonstration:**
1. User A is a new user who has not deposited any tokens yet (`accountToInvestorInfo[A].totalDeposit == 0`).
2. User B makes a deposit and sets User A as their referer. This causes User A to earn referral rewards, resulting in `accountToInvestorInfo[A].accumulatedReward > 0`.
3. User A calls the `claimReward()` function to claim their referral rewards. Part of these rewards are redistributed, increasing User A's `totalDeposit`. Now, `accountToInvestorInfo[A].totalDeposit > 0`.
4. User A decides to make their first real deposit and wants to set User C as their referer. User A calls `deposit(amount, C_address)`.
5. The transaction reverts with `RefererAlreadySetted`. This is because the check `if (investor.totalDeposit > 0)` inside the `deposit` function is now true, and the provided referer address is not `address(0)`. User A is now permanently unable to set a referer.

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
