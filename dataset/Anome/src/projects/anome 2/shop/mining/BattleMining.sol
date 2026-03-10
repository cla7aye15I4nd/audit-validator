// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopStorage} from "../ShopStorage.sol";
import {ShopTypes} from "../ShopTypes.sol";
import {IBattleMining} from "./IBattleMining.sol";
import {BattleMiningInternal} from "./BattleMiningInternal.sol";
import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";

contract BattleMining is IBattleMining, BattleMiningInternal, SafeOwnableInternal {
    function claimXnome(address to) external override {
        _claimXnome(msg.sender, to);
    }

    function getUnlockedXnome(address account) external view override returns (uint256) {
        return _getUnlockedXnome(account);
    }

    function getUnlockedXnomeByDayRange(
        address account,
        uint256 startDay,
        uint256 endDay
    ) external view override returns (uint256) {
        return _getUnlockedXnomeByDayRange(account, startDay, endDay);
    }

    function claimLossCompensation(address to) external override {
        _claimLossCompensation(msg.sender, to);
    }

    function getLossCompensation(address account) external view override returns (uint256) {
        return _getLossCompensation(account);
    }

    function getMiningParams(address account) external view override returns (BattleMiningAccountParams memory) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        BattleMiningAccountParams memory params = BattleMiningAccountParams({
            battleCost: l.battleCost[account],
            battleIncome: l.battleIncome[account],
            totalCompensation: l.totalCompensation[account],
            xnomeTotal: l.xnomeTotal[account],
            xnomeTotalLocked: l.xnomeTotalLocked[account],
            xnomeTotalClaimed: l.xnomeTotalClaimed[account],
            xnomeDailyLatestClaimDay: l.xnomeDailyLatestClaimDay[account],
            battleWinCount: l.battleWinCount[account],
            battleLossCount: l.battleLossCount[account],
            xnomeTotalValue: l.xnomeTotalValue[account],
            totalCompensationValue: l.totalCompensationValue[account],
            totalIncome: _totalIncome(account),
            lossBattleCost: l.lossBattleCost[account],
            lossBattleIncome: l.lossBattleIncome[account]
        });
        return params;
    }

    function getDailyCompensationParams(
        address account
    )
        external
        view
        override
        returns (uint256 dailyCompensation, uint256 dailyMaxCompensation, bool isCompensationClaimed)
    {
        ShopStorage.Layout storage l = ShopStorage.layout();
        return (
            l.dailyCompensation[account][_currentDay()],
            _dailyMaxCompensation(account),
            l.isCompensationClaimed[account][_currentDay()]
        );
    }

    function getCompensationClaimRecords(
        address account
    ) external view override returns (ShopTypes.CompensationClaimRecord[] memory) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        return l.compensationClaimRecords[account];
    }

    function getCurrentDay() external view override returns (uint256) {
        return _currentDay();
    }

    function setLatestClaimDay(address account, uint256 day) external override onlyOwner {
        ShopStorage.Layout storage l = ShopStorage.layout();
        l.xnomeDailyLatestClaimDay[account] = day;
    }

    function getCurrentXnomeDistributionAmount(uint256 destroyValueUsda) external view override returns (uint256) {
        return _getCurrentXnomeDistributionAmount(destroyValueUsda);
    }
}
