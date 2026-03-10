// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import {ICard} from "../token/card/ICard.sol";

library ShopTypes {
    ////////////////// Common //////////////////

    // 卡牌参数, Card合约和Game合约使用
    struct CardAttributes {
        string name;
        uint256 level;
        uint256 top;
        uint256 bottom;
        uint256 left;
        uint256 right;
    }

    // 接收者信息, 通用
    struct Receiver {
        address receiver;
        uint256 ratio;
    }

    ////////////////// CardShop //////////////////

    /**
     * 卡牌核心信息, CardShop使用
     * AdjustedBalance 为调整余额
     * 余额 = 真实余额 + AdjustedBalance
     *
     * cardDecreaseVirtualBalance Card库存量减少量
     * usdaIncreaseVirtualBalance USDA库存量增加量
     */
    struct CardPool {
        uint256 index;
        ICard card;
        uint256 usdaBalance;
        uint256 cardDecreaseVirtualBalance;
        uint256 usdaIncreaseVirtualBalance;
        uint256 ipRevenue;
    }

    // 卡牌列表返回的数据, CardShop使用
    struct CardItem {
        uint256 index;
        ICard card;
        uint256 initialPrice;
        uint256 currentPrice;
        string tokenUri;
        uint256 supply;
        uint256 stock;
        uint256 destruction;
        uint256 circulation;
        uint256 userBalance;
        uint256 ipRevenue;
        CardAttributes attr;
    }

    // 简单卡牌列表返回的数据, CardShop使用
    struct CardItemSimple {
        uint256 index;
        ICard card;
    }

    ////////////////// BorrowShop //////////////////

    // 卡牌的地址和721卡牌ID, 用于BorrowShop合约
    struct Card721 {
        address card;
        uint256 id;
    }

    // 借款订单, BorrowShop使用
    struct BorrowOrder {
        uint256 index;
        uint256 pool;
        bool isRepaid;
        ICard card;
        uint256 cardId;
        uint256 cardPrice;
        uint256 borrowIndex;
        uint256 borrowAmount;
        uint256 borrowInterest;
        uint256 createsAt;
        uint256 repayPrice;
        uint256 repayIndex;
        uint256 repayAmount;
        uint256 repayAt;
    }

    ////////////////// BnomeStake //////////////////

    struct BnomeStakeOrder {
        uint256 index;
        uint256 createdAt;
        uint256 bnomeAmount;
        uint256 unstakedAmount;
        uint256 anchorCard;
        uint256 anchorCardInitialDestruction;
    }

    ////////////////// BattleService //////////////////

    // 用户从下级对战获得的奖励, BattleService使用
    struct BattleRewardRecord {
        address junior;
        uint256 amount;
        uint256 timestamp;
    }

    // 用户对战奖, BattleService使用
    struct BattleRewardInfo {
        uint256 reward;
        uint256 level;
        uint256 exp;
    }

    ////////////////// ShopUser //////////////////

    // 用户信息, ShopUser使用
    struct UserProfile {
        string avatar;
        string nickname;
    }

    ////////////////// BattleMining //////////////////

    // 补偿类型, BattleMining使用
    enum CompensationType {
        Xnome,
        Vnome
    }

    // 补偿记录, BattleMining使用
    struct CompensationClaimRecord {
        uint256 timestamp;
        CompensationType compensationType;
        uint256 amount;
    }

    ////////////////// Referral //////////////////

    // 下线(非直推)信息, 用于Referral合约
    struct Downline {
        address account;
        DownlineItem[] downlines;
        uint256 level;
    }

    // 下级信息, 用于Referral合约
    struct DownlineItem {
        address account;
        uint256 level;
    }

    // 直推信息, 用于Referral合约
    struct Recruit {
        address account;
        uint256 timestamp;
    }
}
