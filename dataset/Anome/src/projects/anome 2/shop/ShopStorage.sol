// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import {ShopTypes} from "./ShopTypes.sol";
import {IConfig} from "../config/IConfig.sol";

library ShopStorage {
    struct Layout {
        IConfig config;

        ////// 邀请码 //////
        mapping(uint256 => bool) codeStatus;
        mapping(address => uint256) accountCode;
        mapping(uint256 => address) accountByCode;
        mapping(address => address) accountSponsor;
        mapping(address => ShopTypes.Recruit[]) accountRecruits;

        ////// 卡牌商店 //////
        uint16 destroyRewardRatio;
        uint16 destroyPerSponsorRatio;
        ShopTypes.CardPool[] pools;
        mapping(uint256 => uint256[]) levelPools;
        mapping(address => uint256) cardsIndex;
        mapping(address => uint256) userCards;
        mapping(uint256 => uint256) sellStartsAt;
        mapping(uint256 => bool) isPoolHide;
        mapping(uint256 => bool) isCardMintBanned;

        ////// 贷款 //////
        uint256 borrowLtv;
        uint256 borrowIndex; // Index in ray
        uint256 borrowRate;  // APY in ray
        uint40 borrowIndexLastUpdateTimestamp;
        // account => cardAddress => id => borrowOrderBookIndex
        mapping(address => mapping(address => mapping(uint256 => uint256))) borrowOrderIndex; 
        mapping(address => ShopTypes.BorrowOrder[]) borrowOrderBook;
        mapping(address => mapping(uint256 => uint256)) cardUsdaAnchorAmount; // 已废弃

        ////// 用户头像和昵称 //////
        mapping(address => ShopTypes.UserProfile) userProfile;

        ////// WK排名, 已废弃 //////
        uint8 wkRankLength;                                          // 更新排名数量时, 需要扩容dayRanks
        mapping(uint256 => uint256) wkRankReward;                    // 累计的排行榜奖励数额
        uint256 wkRankExtraReward;                                   // 分发奖励时剩余的10%, 作为下一轮的额外奖励
        mapping(uint256 => address[]) wkDayRanks;                    // 每天的WK排行榜
        mapping(uint256 => mapping(address => uint256)) wkUserScore; // 每天的WK新增数量

        ////// 对战 //////
        mapping(address => uint16) battleExp; // 对战奖励, 每次对战奖励1exp, 3000exp升级为1级
        mapping(address => uint8) battleLevel;
        mapping(address => ShopTypes.BattleRewardRecord[]) battleRewardRecords; // 记录用户所得到的对战奖励
        mapping(address => uint256) battleReward;

        ////// 亏损挖矿 //////
        uint256 initialBnomeDistribution;                                   // 初始每日Bnome分发量
        uint256 bnomeDistributionStartTime;                                 // 分发开始时间戳
        mapping(address => uint256) battleCost;                             // 用户对战成本
        mapping(address => uint256) battleIncome;                           // 用户对战收入, 含成本, 但是这个只有对战的收入, 不含Xnome和Vnome补偿
        mapping(address => uint256) totalCompensation;                      // 用户累计补偿, 单位Bnome
        mapping(address => uint256) xnomeTotal;                             // 用户累计获得Xnome
        mapping(address => uint256) xnomeTotalLocked;                       // 用户Xnome总锁仓
        mapping(address => uint256) xnomeTotalClaimed;                      // 用户Xnome总领取
        mapping(address => mapping(uint256 => uint256)) xnomeDailyUnlocked; // 用户Xnome挖矿每日释放额
        mapping(address => uint256) xnomeDailyLatestClaimDay;               // 用户Xnome挖矿最新领取日
        mapping(address => mapping(uint256 => uint256)) dailyCompensation;  // 用户每日补偿
        mapping(address => uint256) battleWinCount;                         // 用户对战胜利次数
        mapping(address => uint256) battleLossCount;                        // 用户对战失败次数
        mapping(address => uint256) xnomeTotalValue;                        // 用户获得Xnome的总价值, 金本位
        mapping(address => uint256) totalCompensationValue;                 // 用户累计补偿, 金本位
        mapping(uint256 => bool) _b01; // 已废弃
        mapping(address => ShopTypes.CompensationClaimRecord[]) compensationClaimRecords; // 用户补偿领取记录
        mapping(address => mapping(uint256 => bool)) isCompensationClaimed;               // 用户每日的补偿是否已领取

        mapping(address => uint256) lossBattleCost;   // 输的对局的成本
        mapping(address => uint256) lossBattleIncome; // 输的对局的收入

        ////// BnomeStake //////
        uint256 highBorrowLTV;
        mapping(address => ShopTypes.BnomeStakeOrder[]) bnomeStakeOrders;
        mapping(address => uint256) highBorrowLTVLimit;
        uint256 bnomeTotalStaked;
        uint256 bnomeTotalUnstaked;
        mapping(address => uint256) bnomeAccountTotalStaked;
        mapping(address => uint256) bnomeAccountTotalUnstaked;
        mapping(address => uint256) bnomeAccountTotalHighBorrowLTVLimit;
        mapping(address => bool) isAccountBattleMiningMigrated;

        ////// Common //////
        mapping(address => bool) isAccountBanned;
        mapping(address => bool) isNoContractWhitelist;
        bool isShopPaused;
        mapping(address => bool) hasPausePermission;

        ////// XNome Production Cut //////
        uint256 xnomeProductionCutStartAt;     // 减产开始日期, 单位天
        uint256 xnomeProductionCutRatioPerDay; // 每日减产比例, 单位万
        uint256 minXnomeRatio;                 // 最低Xnome比例, 单位万
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("anome.shop.contracts.storage.v1");
    uint256 constant DIVIDEND = 10000;
    address constant HOLE = address(0xdead);

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
