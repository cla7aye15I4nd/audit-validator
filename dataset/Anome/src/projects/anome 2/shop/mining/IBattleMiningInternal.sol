// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBattleMiningInternal {
    struct BattleMiningAccountParams {
        uint256 battleCost;
        uint256 battleIncome;
        uint256 totalCompensation;
        uint256 xnomeTotal;
        uint256 xnomeTotalLocked;
        uint256 xnomeTotalClaimed;
        uint256 xnomeDailyLatestClaimDay;
        uint256 battleWinCount;
        uint256 battleLossCount;
        uint256 xnomeTotalValue;
        uint256 totalCompensationValue;
        uint256 totalIncome;
        uint256 lossBattleCost;
        uint256 lossBattleIncome;
    }

    error ReceiverAddressIsZero();
    error CurrentDayNotEnoughXnome();
    error AlreadyProfitable();
    error AlreadyClaimed();
    error DailyCompensationIsZero();
    error NoLossCompensation();
    error NotBoundOg();

    event SentXnome(
        address indexed to,
        uint256 totalAmount,
        uint256 dailyAmount,
        uint256 startDay,
        uint256 endDay,
        uint256 accountTotal,
        uint256 accountLocked,
        uint256 accountValue
    );

    event ClaimedXnome(
        address indexed from,
        address indexed to,
        uint256 latestClaimDay,
        uint256 currentDay,
        uint256 totalAmount
    );

    struct BattleMiningCostParams {
        uint256 currentCost;
        uint256 currentIncome;
        uint256 lossCost;
        uint256 lossIncome;
    }

    event BattleMiningCostChanged(
        address indexed winner,
        address indexed loser,
        uint256 winnerCost,
        uint256 loserCost,
        uint256 destroyValue,
        BattleMiningCostParams winnerCostParams,
        BattleMiningCostParams loserCostParams
    );

    event ClaimedLossCompensation(
        address indexed from,
        address indexed to,
        uint256 dailyCompensationUsda,
        uint256 dailyCompensationBnome,
        uint256 dailyMaxCompensation,
        uint256 compensation
    );
}
