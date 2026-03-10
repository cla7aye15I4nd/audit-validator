// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../../lib/openzeppelin/token/ERC20/IERC20.sol";
import {ERC20} from "../../../lib/openzeppelin/token/ERC20/ERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {LiquidityManagerStorage} from "../LiquidityManagerStorage.sol";
import {IConfig} from "../../config/IConfig.sol";
import {IShop} from "../../shop/IShop.sol";

import {ILiquidityPoolInternal} from "./ILiquidityPoolInternal.sol";

contract LiquidityPoolInternal is ILiquidityPoolInternal {
    using SafeERC20 for IERC20;

    function _stake(
        address account,
        uint256 amount,
        LiquidityManagerStorage.StakeDuration stakingDuration
    ) internal {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();

        if (amount == 0) {
            revert StakeAmountIsZero();
        }

        l.tokenStaking.safeTransferFrom(account, address(this), amount);

        l.stakedAmount[account] += amount;
        l.rewardWeight[account] += amount;
        l.totalRewardWeight += amount;
        l.totalStaked += amount;

        uint256 extraRewardWeight = LiquidityManagerStorage.extraRewardWeight(amount, stakingDuration);
        l.extraRewardWeight[account] += extraRewardWeight;
        l.totalRewardWeightExtra += extraRewardWeight;

        l.accountStakeRecord[account].push(
            LiquidityManagerStorage.StakeRecord({
                index: l.accountStakeRecord[account].length,
                isWithdrawn: false,
                stakingDuration: stakingDuration,
                amount: amount,
                extraRewardWeight: extraRewardWeight,
                timestamp: block.timestamp,
                expirationTimestamp: LiquidityManagerStorage.expirationTimestamp(block.timestamp, stakingDuration)
            })
        );

        emit Staked(account, amount);
    }

    function _unstake(address account, uint256 recordIndex) internal {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();
        LiquidityManagerStorage.StakeRecord storage record = l.accountStakeRecord[account][recordIndex];

        if (record.isWithdrawn) {
            revert StakeAlreadyWithdrawn();
        }

        if (record.amount == 0) {
            revert StakeAmountIsZero();
        }

        if (record.amount > l.stakedAmount[account]) {
            revert StakeAmountIsGreaterThanStaked();
        }

        _claimReward(account);
        _claimRewardExtra(account, record);

        record.isWithdrawn = true;
        l.rewardWeight[account] -= (l.rewardWeight[account] * record.amount) / l.stakedAmount[account];
        l.totalRewardWeight -= (l.totalRewardWeight * record.amount) / l.stakedAmount[account];
        l.stakedAmount[account] -= record.amount;
        l.totalStaked -= record.amount;

        l.totalRewardWeightExtra -=
            (l.totalRewardWeightExtra * record.extraRewardWeight) /
            l.extraRewardWeight[account];
        l.extraRewardWeight[account] -= record.extraRewardWeight;

        l.tokenStaking.safeTransfer(account, record.amount);

        emit Withdrawn(account, record.amount);
    }

    function _claimReward(address account) internal returns (uint256 pendingReward) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();

        pendingReward = l.storedPendingReward[account];
        if (pendingReward == 0) {
            return 0;
        }
        uint256 sponsorReward = _rewardSponsor(account, pendingReward);

        l.storedPendingReward[account] = 0;
        l.totalReward += pendingReward - sponsorReward;
        l.accountTotalReward[account] += pendingReward - sponsorReward;
        l.accountClaimRecord[account].push(
            LiquidityManagerStorage.ClaimRecord({
                rewardType: 1,
                amount: pendingReward - sponsorReward,
                timestamp: block.timestamp
            })
        );

        l.tokenReward.safeTransfer(account, pendingReward - sponsorReward);

        emit RewardPaid(account, pendingReward);
    }

    function _claimRewardExtra(
        address account,
        LiquidityManagerStorage.StakeRecord storage record
    ) internal returns (uint256 pendingRewardExtra) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();

        if (block.timestamp < record.expirationTimestamp || record.extraRewardWeight == 0) {
            return 0;
        }

        // 因为额外奖励只有在满足质押期后才能领取
        // 所以每个订单解压时, 按照此订单的权重比例领取额外奖励
        pendingRewardExtra =
            (l.storedPendingRewardExtra[account] * record.extraRewardWeight) /
            l.extraRewardWeight[account];
        if (pendingRewardExtra == 0) {
            return 0;
        }

        uint256 sponsorReward = _rewardSponsor(account, pendingRewardExtra);

        l.storedPendingRewardExtra[account] -= pendingRewardExtra;
        l.totalReward += pendingRewardExtra - sponsorReward;
        l.accountTotalReward[account] += pendingRewardExtra - sponsorReward;
        l.accountClaimRecord[account].push(
            LiquidityManagerStorage.ClaimRecord({
                rewardType: 2,
                amount: pendingRewardExtra,
                timestamp: block.timestamp
            })
        );

        l.tokenReward.safeTransfer(account, pendingRewardExtra - sponsorReward);

        emit RewardPaidExtra(account, pendingRewardExtra);
    }

    function _claimSponsorReward(address account) internal {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();
        uint256 sponsorReward = l.referralReward[account];
        if (sponsorReward == 0) {
            return;
        }

        l.referralReward[account] = 0;
        l.accountClaimRecord[account].push(
            LiquidityManagerStorage.ClaimRecord({rewardType: 3, amount: sponsorReward, timestamp: block.timestamp})
        );

        l.tokenReward.safeTransfer(account, sponsorReward);

        emit RewardPaidSponsor(account, sponsorReward);
    }

    function _rewardSponsor(address account, uint256 amount) internal returns (uint256 sponsorReward) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();
        IShop shop = IShop(l.config.shop());
        address sponsor = shop.getSponsor(account);
        if (sponsor == address(0)) {
            return 0;
        }

        sponsorReward = (amount * 5) / 100;
        l.referralReward[sponsor] += sponsorReward;
        l.accountTotalSponsorReward[sponsor] += sponsorReward;
        l.totalSponsorReward += sponsorReward;

        emit RewardSponsor(account, sponsor, sponsorReward);
    }

    modifier updatePoolAndAccount(address account) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();
        (, uint256 poolWeight, uint256 poolWeightExtra) = _totalRewardWeight();
        (uint256 accountWeight, uint256 accountWeightExtra) = _currentAccountRewardWeight(account);

        _updatePool();
        _updateAccount(account);

        // 计算过后保存当前的总权重
        l.totalRewardWeight = poolWeight - accountWeight + l.rewardWeight[account];
        l.totalRewardWeightExtra = poolWeightExtra - accountWeightExtra + l.extraRewardWeight[account];

        _;
    }

    function _updatePool() internal {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();
        l.accRewardPerShare = _rewardPerToken();
        l.lastRewardTime = _lastRewardTimeApplicable();
    }

    function _updateAccount(address account) internal {
        if (account == address(0)) {
            return;
        }

        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();
        l.storedPendingReward[account] = _pendingReward(account);
        l.paidRewardPerShare[account] = l.accRewardPerShare;

        l.storedPendingRewardExtra[account] = _pendingRewardExtra(account);
        l.paidRewardPerShareExtra[account] = l.accRewardPerShare;

        l.accountLastUpdateTime[account] = _lastRewardTimeApplicable();
    }

    function _pendingReward(address account) internal view returns (uint256 pendingReward) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();

        (uint256 weight, ) = _currentAccountRewardWeight(account);
        if (weight == 0) {
            return 0;
        }

        uint256 rewardPerToken = _rewardPerToken();
        uint256 rewardPerTokenPaid = l.paidRewardPerShare[account];
        pendingReward = (weight * (rewardPerToken - rewardPerTokenPaid)) / 1e18;
        pendingReward += l.storedPendingReward[account];
    }

    function _pendingRewardExtra(address account) internal view returns (uint256 pendingRewardExtra) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();

        (, uint256 extraWeight) = _currentAccountRewardWeight(account);
        if (extraWeight == 0) {
            return 0;
        }

        uint256 rewardPerToken = _rewardPerToken();
        uint256 rewardPerTokenPaid = l.paidRewardPerShareExtra[account];
        pendingRewardExtra = (extraWeight * (rewardPerToken - rewardPerTokenPaid)) / 1e18;
        pendingRewardExtra += l.storedPendingRewardExtra[account];
    }

    function _rewardPerToken() internal view returns (uint256 rewardPerToken) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();

        (uint256 totalWeight, , ) = _totalRewardWeight();
        if (totalWeight == 0) {
            return l.accRewardPerShare;
        }

        if (_lastRewardTimeApplicable() <= l.lastRewardTime) {
            return l.accRewardPerShare;
        }

        uint256 timeElapsed = _lastRewardTimeApplicable() - l.lastRewardTime;
        uint256 newReward = (timeElapsed * l.rewardPerDay) / 1 days;
        uint256 newRewardPerToken = (newReward * 1e18) / totalWeight;
        rewardPerToken = l.accRewardPerShare + newRewardPerToken;
    }

    function _lastRewardTimeApplicable() internal view returns (uint256 lastRewardTime) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();

        if (block.timestamp >= l.rewardEndsAt) {
            return l.rewardEndsAt;
        }

        lastRewardTime = block.timestamp;
    }

    function _totalRewardWeight()
        internal
        view
        returns (uint256 totalWeight, uint256 totalRewardWeight, uint256 totalRewardWeightExtra)
    {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();
        totalRewardWeight = l.totalRewardWeight;
        totalRewardWeightExtra = l.totalRewardWeightExtra;
        totalWeight = totalRewardWeight + totalRewardWeightExtra;

        if (l.lastRewardTime == 0) {
            revert PoolNotStarted();
        }

        uint256 poolDayElapsed = (_lastRewardTimeApplicable() - l.lastRewardTime) / 1 days;
        if (poolDayElapsed < 1) {
            return (totalWeight, totalRewardWeight, totalRewardWeightExtra);
        }
        poolDayElapsed -= 1;

        totalRewardWeight = totalRewardWeight + (totalRewardWeight * poolDayElapsed * 1) / 100;
        totalRewardWeightExtra = totalRewardWeightExtra + (totalRewardWeightExtra * poolDayElapsed * 1) / 100;
        totalWeight = totalRewardWeight + totalRewardWeightExtra;
    }

    function _currentAccountRewardWeight(
        address account
    ) internal view returns (uint256 rewardWeight, uint256 extraRewardWeight) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();

        if (account == address(0)) {
            return (0, 0);
        }

        rewardWeight = l.rewardWeight[account];
        extraRewardWeight = l.extraRewardWeight[account];

        if (l.accountLastUpdateTime[account] == 0) {
            return (rewardWeight, extraRewardWeight);
        }

        uint256 accountDayElapsed = (_lastRewardTimeApplicable() - l.accountLastUpdateTime[account]) / 1 days;
        if (accountDayElapsed < 1) {
            return (rewardWeight, extraRewardWeight);
        }
        accountDayElapsed -= 1;

        rewardWeight = rewardWeight + (rewardWeight * accountDayElapsed * 1) / 100;
        extraRewardWeight = extraRewardWeight + (extraRewardWeight * accountDayElapsed * 1) / 100;
    }
}
