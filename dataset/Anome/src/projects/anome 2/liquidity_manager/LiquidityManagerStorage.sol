// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import {IERC20} from "../../lib/openzeppelin/token/ERC20/IERC20.sol";
import {IConfig} from "../config/IConfig.sol";

library LiquidityManagerStorage {
    struct Layout {
        ////// Global Params //////
        IConfig config;
        IERC20 tokenStaking;
        IERC20 tokenReward;

        uint256 rewardEndsAt;                                 // 奖励结束时间
        uint256 rewardPerDay;                                 // 每天奖励数量
        uint256 lastRewardTime;                               // 上次奖励时间

        uint256 totalRewardWeight;                            // 总权重
        uint256 totalRewardWeightExtra;                       // 总权重额外奖励
        uint256 accRewardPerShare;                            // 每份额奖励

        ////// Account Params //////
        mapping(address => uint256) stakedAmount;             // 质押数量
        mapping(address => uint256) accountLastUpdateTime;    // 账户上次奖励时间
        mapping(address => uint256) referralReward;           // 下级推广收益

        mapping(address => uint256) rewardWeight;             // 用户权重
        mapping(address => uint256) paidRewardPerShare;       // 用户已领取每份额奖励
        mapping(address => uint256) storedPendingReward;      // 已经记录的待发放奖励

        mapping(address => uint256) extraRewardWeight;        // 用户额外权重, 承诺质押一定时间得到的额外权重
        mapping(address => uint256) paidRewardPerShareExtra;  // 用户已领取额外权重每份额奖励
        mapping(address => uint256) storedPendingRewardExtra; // 已经记录的待发放额外奖励

        ////// Statistics //////
        uint256 totalStaked;                                  // 总质押数量
        uint256 totalReward;                                   // 总奖励数量
        uint256 totalSponsorReward;                            // 总推广奖励数量
        mapping(address => uint256) accountTotalReward;        // 账户总奖励数量
        mapping(address => uint256) accountTotalSponsorReward; // 账户总推广奖励数量
        mapping(address => StakeRecord[]) accountStakeRecord;  // 账户质押记录
        mapping(address => ClaimRecord[]) accountClaimRecord; // 账户领取记录
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("anome.liquidity_manager.pool.contracts.storage.v1");
    uint256 constant DIVIDEND = 10000;
    address constant HOLE = address(0xdead);

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    struct StakeRecord {
        uint256 index;
        bool isWithdrawn;
        StakeDuration stakingDuration;
        uint256 amount;
        uint256 extraRewardWeight;
        uint256 timestamp;
        uint256 expirationTimestamp;
    }

    struct ClaimRecord {
        uint256 rewardType; // 1: weight, 2: extra, 3: sponsor
        uint256 amount;
        uint256 timestamp;
    }

    enum StakeDuration {
        ONE_MONTHS,
        THREE_MONTHS,
        SIX_MONTHS,
        ONE_YEAR,
        TWO_YEARS
    }

    function extraRewardWeight(uint256 stakeAmount, StakeDuration duration) internal pure returns (uint256) {
        if (duration == StakeDuration.ONE_MONTHS) {
            // 质押一个月额外奖励为0
            return 0;
        } else if (duration == StakeDuration.THREE_MONTHS) {
            // 质押三个月额外奖励为10%
            return stakeAmount * 1 / 10;
        } else if (duration == StakeDuration.SIX_MONTHS) {
            // 质押六个月额外奖励为30%
            return stakeAmount * 3 / 10;
        } else if (duration == StakeDuration.ONE_YEAR) {
            // 质押一年额外奖励为50%
            return stakeAmount * 5 / 10;
        } else if (duration == StakeDuration.TWO_YEARS) {
            // 质押两年额外奖励为100%
            return stakeAmount;
        }
        revert("Invalid stake duration");
    }

    function expirationTimestamp(uint256 timestamp, StakeDuration duration) internal pure returns (uint256) {
        if (duration == StakeDuration.ONE_MONTHS) {
            return timestamp + 30 days;
        } else if (duration == StakeDuration.THREE_MONTHS) {
            return timestamp + 90 days;
        } else if (duration == StakeDuration.SIX_MONTHS) {
            return timestamp + 180 days;
        } else if (duration == StakeDuration.ONE_YEAR) {
            return timestamp + 360 days;
        } else if (duration == StakeDuration.TWO_YEARS) {
            return timestamp + 720 days;
        } else {
            revert("Invalid stake duration");
        }
    }
}
