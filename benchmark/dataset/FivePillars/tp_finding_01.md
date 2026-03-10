# Premature Pool Participation Check in claimReward Function Leads to Missed Pool Enrollment


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Source | scanner.smart_audit |
| Scan Model | grok-4 |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./source_code/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The claimReward function updates the investor's rewards and calculates the amount to be redistributed as an addition to the investor's totalDeposit. However, the function calls _updatePoolRewards, which checks for pool participation using the current (old) totalDeposit value, before adding the redistributed amount to totalDeposit. This logic flaw prevents investors from being added to pools they qualify for after the redistribution, resulting in missed pool rewards until the next interaction that triggers a pool check (such as another deposit or claim, or a global criteria update by the owner).

Exploit Demonstration:

1. An investor acquires enough referral deposits and count to qualify for a pool once their personal totalDeposit reaches the required threshold.
2. The investor ensures their current totalDeposit is below the threshold for a particular pool, but the expected toRedistribute from claiming will push it above the threshold.
3. The investor calls the claimReward function.
4. During the call, _updatePoolRewards uses the old totalDeposit, so the investor is not added to the pool.
5. After the call, the totalDeposit is updated with toRedistribute, now meeting the threshold, but the investor is not enrolled in the pool.
6. The investor misses out on pool rewards from that point until they call deposit or claimReward again, which would then add them to the pool.

## Vulnerable Code

```
function claimReward() external NotInPoolCriteriaUpdate {
        address investorAddress = _msgSender();
        _updateInvestorRewards(investorAddress);
        InvestorInfo memory investor = accountToInvestorInfo[investorAddress];
        _checkDepositOrClaimAmount(investor.accumulatedReward);

        accountToInvestorInfo[investorAddress].accumulatedReward = 0;
        accountToInvestorInfo[investorAddress].lastClaimTimestamp = uint32(block.timestamp);

        (uint256 toInvestor, uint256 fee) = _calcFee(investor.accumulatedReward, claimFeeInBp);
        uint256 toRedistribute = toInvestor * 50 / 100;
        toInvestor -= toRedistribute;
        fivePillarsToken.mint(address(this), fee);
        fivePillarsToken.mint(investorAddress, toInvestor);

        // Redistribute half user reward
        if (investor.totalDeposit == 0) {
            _investors.push(investorAddress);
            if (isWhitelisted[investorAddress][7] || isWhitelisted[investorAddress][8]) onlyWhitelistedInvestorsCount -= 1;
        }
        if (investor.referer != address(0)) _updateReferers(investor.referer, toRedistribute, false);
        _updatePoolRewards(toRedistribute, investorAddress, investor.referer);
        accountToInvestorInfo[investorAddress].totalDeposit += toRedistribute;
        totalDepositAmount += toRedistribute;

        emit Redistribute(investorAddress, toRedistribute);

        emit ClaimReward(investorAddress, toInvestor);

        _trySendFees();
    }
```

## Related Context

```
_updateInvestorRewards ->     function _updateInvestorRewards(address investor) internal {
        InvestorInfo memory investorInfo = accountToInvestorInfo[investor];
        (uint256 totalDailyReward, uint256 roundReward) = _calcInvestorDailyReward(investorInfo);
        accountToInvestorInfo[investor].accumulatedReward += totalDailyReward;
        if (totalDailyReward > 0) {
            accountToInvestorInfo[investor].lastDailyReward = roundReward;
        }
        _updateInvestorRefReward(investor);
        _updatePoolRewards();
        _updateInvestorPoolRewards(investor);
    }

_checkDepositOrClaimAmount ->     function _checkDepositOrClaimAmount(uint256 amount) internal pure {
        if (amount < 10 ** 18) revert SmallDepositOrClaimAmount();
    }

_calcFee ->     function _calcFee(uint256 amount, uint256 feeInBp) internal pure returns(uint256 toInvestor, uint256 fee) {
        fee = amount * feeInBp / BASIS_POINTS;
        toInvestor = amount - fee;
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

_updatePoolRewards ->     function _updatePoolRewards() internal {
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(uint32(lastUpdatePoolRewardTimestamp));

        for (uint8 i = 0; i < pools.length; i++) {
            if (pools[i].isActive) _updatePoolReward(pools[i], endedRounds);
        }

        lastUpdatePoolRewardTimestamp = block.timestamp;
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
