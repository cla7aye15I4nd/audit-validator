# Minimum Net Deposit Requirement Bypass


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | 🟢 Minor |
| Triage Verdict | ❌ Invalid |
| Source | scanner.static_scanner |
| Scan Model | o4-mini |
| Project ID | `a41cefe0-4159-11f0-a06b-992008d4f8aa` |
| Commit | `9af8be2c4e53218770015a10ea269caa904fde19` |

## Location

- **Local path:** `./source_code/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/a41cefe0-4159-11f0-a06b-992008d4f8aa/source?file=$/github/fivepillarstoken/InvestmentManager/9af8be2c4e53218770015a10ea269caa904fde19/InvestmentManager.sol
- **Lines:** 1–1

## Description

The function enforces the minimum first-deposit requirement (_checkDepositOrClaimAmount) on the _gross_ amount parameter, not on the _net_ amount (toInvestor) actually credited. Because the deposit fee is deducted after this check, an attacker can make a first deposit that passes the gross threshold but results in a much smaller net deposit.

Exploit Steps:
1. Assume depositFeeInBp is non-zero (e.g. 50% = 5,000 bp) and the minimum deposit is 1 × 10¹⁸ (1 token).
2. Call deposit(amount = 1 × 10¹⁸, referer = address(0)).
   - _checkDepositOrClaimAmount sees amount ≥ 1 × 10¹⁸ and allows the deposit.
   - Fee = amount × 5,000 / 10,000 = 0.5 × 10¹⁸.
   - toInvestor = amount – fee = 0.5 × 10¹⁸.
   - Only 0.5 token is actually credited in totalDeposit.
3. The attacker is now a “first-time” depositor (isFirstDeposit) and gains whatever benefits are tied to being a participant (pool inclusion, referral eligibility, etc.) while only depositing 0.5 token net.

Impact: The attacker pays half a token net but obtains full participant rights (e.g. equal share in pool rewards or referral counts) as if they had deposited the full minimum. This allows under-funded participation and unfair reward extraction.

## Vulnerable Code

```
function deposit(uint256 amount, address referer) external NotInPoolCriteriaUpdate{
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
function _trySendFees() internal{
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

function _calcInvestorDailyReward(InvestorInfo memory investorInfo) internal view returns(uint256, uint256){
        uint32 lastUpdate = investorInfo.lastDepositTimestamp > investorInfo.lastClaimTimestamp ? investorInfo.lastDepositTimestamp : investorInfo.lastClaimTimestamp;
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(lastUpdate);
        uint256 roundReward = investorInfo.totalDeposit * 30000 / BASIS_POINTS;

        return (roundReward * endedRounds, roundReward);
    }

function _calcCountOfRoundsSinceLastUpdate(uint32 lastUpdate) internal view returns(uint256){
        uint256 startTime = startTimestamp;
        if (lastUpdate < startTime || block.timestamp < startTime) return 0;
        return (block.timestamp - startTime) / roundDuration - (lastUpdate - startTime) / roundDuration;
    }

function _updatePoolRewards() internal{
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(uint32(lastUpdatePoolRewardTimestamp));

        for (uint8 i = 0; i < pools.length; i++) {
            if (pools[i].isActive) _updatePoolReward(pools[i], endedRounds);
        }

        lastUpdatePoolRewardTimestamp = block.timestamp;
    }

function _updatePoolReward(PoolInfo storage poolInfo, uint256 endedRounds) internal{
        if (endedRounds > 0) {
            poolInfo.rewardPerInvestorStored += poolInfo.curReward * endedRounds / poolInfo.participantsCount;
            poolInfo.lastReward = poolInfo.curReward / poolInfo.participantsCount;
        }
    }

function _updateReferers(address referer, uint256 amount, bool isFirstDeposit) internal{
        _updateInvestorRefReward(referer);

        accountToInvestorInfo[referer].directRefsDeposit += amount;
        if (isFirstDeposit) accountToInvestorInfo[referer].directRefsCount += 1;

        for (uint i = 0; i < 9; i++) {
            referer = accountToInvestorInfo[referer].referer;
            if (referer == address(0)) break;
            _updateDownlineReferer(referer, amount, isFirstDeposit);
        }
    }

function _updateDownlineReferer(address referer, uint256 amount, bool isFirstDeposit) internal{
        _updateInvestorRefReward(referer);

        accountToInvestorInfo[referer].downlineRefsDeposit += amount;
        if (isFirstDeposit) accountToInvestorInfo[referer].downlineRefsCount += 1;
    }

function _updateInvestorRefReward(address investor) internal{
        InvestorInfo memory investorInfo = accountToInvestorInfo[investor];
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(investorInfo.updateRefRewardTimestamp);

        if (endedRounds > 0) {
            (uint256 totalRefRewards, uint256 lastRefReward) = _calcInvestorRefRewards(investorInfo, investor);
            accountToInvestorInfo[investor].lastRefReward = lastRefReward;
            accountToInvestorInfo[investor].accumulatedReward += totalRefRewards;
        }

        accountToInvestorInfo[investor].updateRefRewardTimestamp = uint32(block.timestamp);
    }

function _calcInvestorRefRewards(InvestorInfo memory investorInfo, address investor) internal view returns(uint256, uint256){
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(investorInfo.updateRefRewardTimestamp);
        uint256 roundReward = investorInfo.directRefsDeposit * 2500 / BASIS_POINTS;
        if (isInvestorInPool[investor][2]) {
            roundReward += investorInfo.downlineRefsDeposit * 675 / BASIS_POINTS;
        }

        return (roundReward * endedRounds, roundReward);
    }

function _checkRefererCirculation(address referer) internal view{
        address directReferer = referer;
        if (referer != address(0)) {
            for (uint i = 0; i < 9; i++) {
                referer = accountToInvestorInfo[referer].referer;
                if (referer == address(0)) break;
                if (referer == directReferer) revert RefererCirculationDetected();
            }
        }
    }

function _checkDepositOrClaimAmount(uint256 amount) internal pure{
        if (amount < 10 ** 18) revert SmallDepositOrClaimAmount();
    }

function burnFrom(address account, uint256 amount) external onlyInvestmentManager{
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

function _calcFee(uint256 amount, uint256 feeInBp) internal pure returns(uint256 toInvestor, uint256 fee){
        fee = amount * feeInBp / BASIS_POINTS;
        toInvestor = amount - fee;
    }
```
