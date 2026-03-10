// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../../lib/openzeppelin/token/ERC20/IERC20.sol";

import {IShop} from "../../shop/IShop.sol";
import {LiquidityManagerStorage} from "../LiquidityManagerStorage.sol";

import {ILiquidityPool} from "./ILiquidityPool.sol";
import {LiquidityPoolInternal} from "./LiquidityPoolInternal.sol";
import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";

contract LiquidityPool is ILiquidityPool, LiquidityPoolInternal, SafeOwnableInternal {
    function stake(
        uint256 amount,
        LiquidityManagerStorage.StakeDuration stakingDuration
    ) external updatePoolAndAccount(msg.sender) {
        _stake(msg.sender, amount, stakingDuration);
    }

    function unstake(uint256 recordIndex) external updatePoolAndAccount(msg.sender) {
        _unstake(msg.sender, recordIndex);
    }

    function claimReward() external updatePoolAndAccount(msg.sender) {
        _claimReward(msg.sender);
    }

    function claimSponsorReward() external {
        _claimSponsorReward(msg.sender);
    }

    function getPendingReward(
        address account
    ) external view returns (uint256 pendingReward, uint256 pendingRewardExtra) {
        // 如果有上级则不展示上级收益
        IShop shop = IShop(LiquidityManagerStorage.layout().config.shop());
        address sponsor = shop.getSponsor(account);
        if (sponsor == address(0)) {
            pendingReward = _pendingReward(account);
            pendingRewardExtra = _pendingRewardExtra(account);
        } else {
            pendingReward = (_pendingReward(account) * 95) / 100;
            pendingRewardExtra = (_pendingRewardExtra(account) * 95) / 100;
        }
    }

    function getStakeRecordList(
        address account
    ) external view returns (LiquidityManagerStorage.StakeRecord[] memory) {
        return LiquidityManagerStorage.layout().accountStakeRecord[account];
    }

    function getClaimRecordList(
        address account
    ) external view returns (LiquidityManagerStorage.ClaimRecord[] memory) {
        return LiquidityManagerStorage.layout().accountClaimRecord[account];
    }

    function getExtraRewardWeight() external pure override returns (uint256[] memory) {
        uint256[] memory extraRewardWeight = new uint256[](5);
        extraRewardWeight[0] = 0; // 1 month
        extraRewardWeight[1] = 1e17; // 3 months
        extraRewardWeight[2] = 3e17; // 6 months
        extraRewardWeight[3] = 5e17; // 1 year
        extraRewardWeight[4] = 1e18; // 2 years
        return extraRewardWeight;
    }

    function getPoolInfo() external view returns (PoolInfo memory poolInfo) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();
        (, uint256 totalRewardWeight, uint256 totalRewardWeightExtra) = _totalRewardWeight();
        poolInfo.tokenStaking = address(l.tokenStaking);
        poolInfo.tokenReward = address(l.tokenReward);
        poolInfo.rewardEndsAt = l.rewardEndsAt;
        poolInfo.rewardPerDay = l.rewardPerDay;
        poolInfo.lastRewardTime = l.lastRewardTime;
        poolInfo.totalRewardWeight = totalRewardWeight;
        poolInfo.totalRewardWeightExtra = totalRewardWeightExtra;
        poolInfo.totalStaked = l.totalStaked;
        poolInfo.totalReward = l.totalReward;
        poolInfo.totalSponsorReward = l.totalSponsorReward;
    }

    function getAccountInfo(address account) external view returns (AccountInfo memory accountInfo) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();
        (uint256 totalWeight, , ) = _totalRewardWeight();
        (uint256 rewardWeight, uint256 extraRewardWeight) = _currentAccountRewardWeight(account);
        accountInfo.lastUpdateTime = l.accountLastUpdateTime[account];
        accountInfo.referralReward = l.referralReward[account];
        accountInfo.stakedAmount = l.stakedAmount[account];
        accountInfo.rewardWeight = rewardWeight;
        accountInfo.extraRewardWeight = extraRewardWeight;
        accountInfo.accountTotalReward = l.accountTotalReward[account];
        accountInfo.accountTotalSponsorReward = l.accountTotalSponsorReward[account];
        accountInfo.pendingReward = _pendingReward(account);
        accountInfo.pendingRewardExtra = _pendingRewardExtra(account);
        accountInfo.currentTime = block.timestamp;
        accountInfo.expectedRewardPerSecond =
            ((((accountInfo.rewardWeight + accountInfo.extraRewardWeight) * 1e18) / totalWeight) *
                l.rewardPerDay) /
            86400 /
            1e18;
    }

    function setRewardToken(address rewardToken) external override onlyOwner {
        LiquidityManagerStorage.layout().tokenReward = IERC20(rewardToken);
    }
}
