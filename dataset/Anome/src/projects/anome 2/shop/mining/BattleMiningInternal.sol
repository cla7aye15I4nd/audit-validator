// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../../lib/openzeppelin/token/ERC20/IERC20.sol";
import {IUniswapV2Router01} from "../../../lib/uniswap_v2/interfaces/IUniswapV2Router01.sol";

import {UtilsLib} from "../../utils/UtilsLib.sol";
import {IConfig} from "../../config/IConfig.sol";
import {IOgNFT} from "../../og_nft/IOgNFT.sol";
import {ShopStorage} from "../ShopStorage.sol";
import {ShopTypes} from "../ShopTypes.sol";

import {IBattleMiningInternal} from "./IBattleMiningInternal.sol";
import {ShopCommonInternal} from "../common/ShopCommonInternal.sol";

contract BattleMiningInternal is IBattleMiningInternal, ShopCommonInternal {
    // Xnome代表每局游戏销毁那一张卡牌的补偿, 因为Xnome和Bnome1:1兑换, 所以直接发放Bnome, 并计入总盈利
    // 亏损补偿代表对每局游戏输掉的四张卡牌的补偿, 亏损补偿每天只能领取一次, 每次领取千分之五, 并计入总盈利

    function _distributeXnome(address to, uint256 destroyValueUsda) internal commonCheck returns (uint256) {
        // 发放Xnome, Xnome数量和销毁卡牌的价值有关
        // Xnome数量 = 每局游戏销毁卡牌的金本位价值 / Nome价格
        // 所得到的Xnome分50天逐步释放
        ShopStorage.Layout storage l = ShopStorage.layout();
        uint256 totalXnome = _getSwapOutBnomeFromUsda(_getCurrentXnomeDistributionAmount(destroyValueUsda));

        for (uint256 i = 0; i < 50; i++) {
            uint256 day = _currentDay() + i + 1;
            l.xnomeDailyUnlocked[to][day] += totalXnome / 50;
        }
        l.xnomeTotal[to] += totalXnome;
        l.xnomeTotalLocked[to] += totalXnome;
        l.xnomeTotalValue[to] += destroyValueUsda;

        if (l.xnomeDailyLatestClaimDay[to] == 0 || l.xnomeDailyLatestClaimDay[to] > _currentDay()) {
            l.xnomeDailyLatestClaimDay[to] = _currentDay() - 1;
        }

        emit SentXnome(
            to,
            totalXnome,
            totalXnome / 50,
            _currentDay() + 1,
            _currentDay() + 50,
            l.xnomeTotal[to],
            l.xnomeTotalLocked[to],
            l.xnomeTotalValue[to]
        );

        return totalXnome;
    }

    function _getCurrentXnomeDistributionAmount(uint256 destroyValueUsda) internal view returns (uint256) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        uint256 currentDay = _currentDay();
        uint256 productionCutStartAt = l.xnomeProductionCutStartAt;
        uint256 productionCutRatioPerDay = l.xnomeProductionCutRatioPerDay;
        uint256 minXnomeRatio = l.minXnomeRatio;

        if (currentDay <= productionCutStartAt) {
            return destroyValueUsda;
        }

        uint256 dayDiff = currentDay - productionCutStartAt;
        uint256 reduction = productionCutRatioPerDay * dayDiff;

        uint256 ratio = reduction >= (ShopStorage.DIVIDEND - minXnomeRatio)
            ? minXnomeRatio
            : ShopStorage.DIVIDEND - reduction;

        return (destroyValueUsda * ratio) / ShopStorage.DIVIDEND;
    }

    function _claimXnome(address from, address to) internal commonCheck {
        if (from == address(0)) {
            revert ReceiverAddressIsZero();
        }

        if (to == address(0)) {
            revert ReceiverAddressIsZero();
        }

        ShopStorage.Layout storage l = ShopStorage.layout();
        IConfig config = IConfig(l.config);

        // 如果用户没有绑定OG, 则不发放Xnome
        if (!IOgNFT(config.ogNFT()).isAccountBoundSponsor(from)) {
            revert NotBoundOg();
        }

        uint256 latestClaimDay = l.xnomeDailyLatestClaimDay[from];

        // 如果最后一次领取日期是0, 则说明没有领取过, 从50天前开始领取即可
        if (latestClaimDay == 0) {
            latestClaimDay = _currentDay() - 50;
        }
        // 如果最后一次领取日期大于当前日期, 则说明是错误的情况, 只需要从前一天开始领取即可
        if (latestClaimDay > _currentDay()) {
            latestClaimDay = _currentDay() - 1;
        }

        uint256 totalAmount = 0;
        for (uint256 i = latestClaimDay + 1; i <= _currentDay(); i++) {
            uint256 amount = l.xnomeDailyUnlocked[from][i];
            if (amount == 0) {
                continue;
            }

            l.xnomeDailyUnlocked[from][i] = 0;
            totalAmount += amount;
        }
        l.xnomeDailyLatestClaimDay[from] = _currentDay();

        if (totalAmount != 0) {
            l.xnomeTotalLocked[from] -= totalAmount;
            l.xnomeTotalClaimed[from] += totalAmount;
            IERC20(config.bnome()).transfer(to, totalAmount);

            l.compensationClaimRecords[from].push(
                ShopTypes.CompensationClaimRecord({
                    timestamp: block.timestamp,
                    compensationType: ShopTypes.CompensationType.Xnome,
                    amount: totalAmount
                })
            );
        }

        emit ClaimedXnome(from, to, latestClaimDay, _currentDay(), totalAmount);
    }

    function _getUnlockedXnome(address account) internal view returns (uint256 totalAmount) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        uint256 latestClaimDay = l.xnomeDailyLatestClaimDay[account];
        if (latestClaimDay == 0) {
            latestClaimDay = _currentDay();
        }
        if (latestClaimDay > _currentDay()) {
            return 0;
        }

        for (uint256 i = latestClaimDay + 1; i <= _currentDay(); i++) {
            uint256 amount = l.xnomeDailyUnlocked[account][i];
            if (amount == 0) {
                continue;
            }

            totalAmount += amount;
        }
    }

    function _getUnlockedXnomeByDayRange(
        address account,
        uint256 startDay,
        uint256 endDay
    ) internal view returns (uint256 totalAmount) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        for (uint256 i = startDay; i <= endDay; i++) {
            uint256 amount = l.xnomeDailyUnlocked[account][i];
            if (amount == 0) {
                continue;
            }

            totalAmount += amount;
        }
    }

    function _setCostIncome(
        address winner,
        address loser,
        uint256 winnerCost,
        uint256 loserCost,
        uint256 destroyValue
    ) internal commonCheck {
        ShopStorage.Layout storage l = ShopStorage.layout();

        // Migrate, 处理lossBattleCost和lossBattleIncome的初始化
        _migrateLossBattleCostAndIncome(winner);
        _migrateLossBattleCostAndIncome(loser);

        l.battleCost[winner] += winnerCost;
        l.battleIncome[winner] += winnerCost + loserCost - destroyValue;
        l.battleWinCount[winner]++;

        l.battleCost[loser] += loserCost;
        l.battleIncome[loser] += 0;
        l.battleLossCount[loser]++;

        // 只记录用户输的游戏的成本和收益, 并且输的局收益为0
        l.lossBattleCost[loser] += loserCost;

        emit BattleMiningCostChanged(
            winner,
            loser,
            winnerCost,
            loserCost,
            destroyValue,
            BattleMiningCostParams({
                currentCost: l.battleCost[winner],
                currentIncome: l.battleIncome[winner],
                lossCost: l.lossBattleCost[winner],
                lossIncome: l.lossBattleIncome[winner]
            }),
            BattleMiningCostParams({
                currentCost: l.battleCost[loser],
                currentIncome: l.battleIncome[loser],
                lossCost: l.lossBattleCost[loser],
                lossIncome: l.lossBattleIncome[loser]
            })
        );
    }

    function _migrateLossBattleCostAndIncome(address account) internal {
        // 使用lossBattleCost代替battleCost和battleIncome的主要目的是
        // 为了让用户只要输了游戏就得到补偿
        ShopStorage.Layout storage l = ShopStorage.layout();

        if (l.isAccountBattleMiningMigrated[account]) {
            return;
        }

        if (l.battleCost[account] <= l.battleIncome[account]) {
            return;
        }

        uint256 historyLoss = l.battleCost[account] - l.battleIncome[account];
        l.lossBattleCost[account] = UtilsLib.max(historyLoss, l.lossBattleCost[account]);
        l.isAccountBattleMiningMigrated[account] = true;
    }

    function _claimLossCompensation(address from, address to) internal commonCheck noContractCall {
        // 补偿 = min(总补偿的千分之五, 每日最大补偿)

        if (from == address(0)) {
            revert ReceiverAddressIsZero();
        }

        if (to == address(0)) {
            revert ReceiverAddressIsZero();
        }

        ShopStorage.Layout storage l = ShopStorage.layout();
        IConfig config = IConfig(l.config);

        // 如果用户没有绑定OG, 则不发放补偿
        if (!IOgNFT(config.ogNFT()).isAccountBoundSponsor(from)) {
            revert NotBoundOg();
        }

        // 每日只能领取一次补偿
        if (l.isCompensationClaimed[from][_currentDay()]) {
            revert AlreadyClaimed();
        }

        // 计算每日应当补偿额, 总补偿的千分之五, 单位USDA
        if (l.lossBattleCost[from] <= _totalIncome(from)) {
            revert NoLossCompensation();
        }

        uint256 totalLoss = l.lossBattleCost[from] - _totalIncome(from);
        uint256 dailyCompensation = (totalLoss * 5) / 1000;

        if (dailyCompensation == 0) {
            revert DailyCompensationIsZero();
        }

        // 计算每日应当补偿额, 总补偿的千分之五, 单位Bnome
        uint256 dailyCompensationBnome = _getSwapOutBnomeFromUsda(dailyCompensation);

        // 应用今日剩余最大补偿, 单位Bnome
        uint256 dailyMaxCompensation = _dailyMaxCompensation(from);
        uint256 compensation = dailyCompensationBnome > dailyMaxCompensation
            ? dailyMaxCompensation
            : dailyCompensationBnome;

        // 补偿Bnome
        IERC20(config.bnome()).transfer(to, compensation);

        // 记录已领取状态
        l.dailyCompensation[from][_currentDay()] += compensation;
        l.totalCompensation[from] += compensation;
        l.isCompensationClaimed[from][_currentDay()] = true;
        // 此处使用应用上限前的值, 是因为BNome最低锚定价为0.1, 如果低于0.1事实上用户会拿到更多
        // 所以使用一个更大的值来计算, 避免超发奖励
        l.totalCompensationValue[from] += _getSwapOutUsdaFromBnome(dailyCompensationBnome);

        l.compensationClaimRecords[from].push(
            ShopTypes.CompensationClaimRecord({
                timestamp: block.timestamp,
                compensationType: ShopTypes.CompensationType.Vnome,
                amount: compensation
            })
        );

        emit ClaimedLossCompensation(
            from,
            to,
            dailyCompensation,
            dailyCompensationBnome,
            dailyMaxCompensation,
            compensation
        );
    }

    function _getLossCompensation(address from) internal view returns (uint256) {
        ShopStorage.Layout storage l = ShopStorage.layout();

        // 每日只能领取一次补偿
        if (l.isCompensationClaimed[from][_currentDay()]) {
            return 0;
        }

        // 计算每日应当补偿额, 总补偿的千分之五, 单位USDA
        if (l.lossBattleCost[from] <= _totalIncome(from)) {
            return 0;
        }

        uint256 totalLoss = l.lossBattleCost[from] - _totalIncome(from);
        uint256 dailyCompensation = (totalLoss * 5) / 1000;

        // 计算每日应当补偿额, 总补偿的千分之五, 单位Bnome
        uint256 dailyCompensationBnome = _getSwapOutBnomeFromUsda(dailyCompensation);

        // 应用今日剩余最大补偿, 单位Bnome
        uint256 dailyMaxCompensation = _dailyMaxCompensation(from);
        uint256 compensation = dailyCompensationBnome > dailyMaxCompensation
            ? dailyMaxCompensation
            : dailyCompensationBnome;

        return compensation;
    }

    function _dailyMaxCompensation(address account) internal view returns (uint256) {
        // 计算每日最大补偿
        // 每日最大补偿 = 用户Vnome持有量 * 每日产出 * 5% / Vnome总供应量
        ShopStorage.Layout storage l = ShopStorage.layout();
        IConfig config = IConfig(l.config);
        IERC20 vnome = IERC20(config.vnome());
        uint256 accountVnome = vnome.balanceOf(account);
        uint256 dailyBnome = _getCurrentBnomeDistribution();
        return (accountVnome * dailyBnome) / vnome.totalSupply();
    }

    function _getCurrentBnomeDistribution() internal view returns (uint256) {
        // 每日Vnome挖矿释放量, 三个月一减半
        uint256 QUARTER_SECONDS = 90 days;
        ShopStorage.Layout storage l = ShopStorage.layout();

        // 计算从开始时间到现在经过了多少个季度（3个月）
        uint256 timeElapsed = block.timestamp - l.bnomeDistributionStartTime;
        uint256 quartersElapsed = timeElapsed / QUARTER_SECONDS;

        // 计算当前的分发量: initialValue / (2^quartersElapsed)
        // 注意: 如果quarters > 256，这可能会溢出，但这种情况实际上不太可能发生
        if (quartersElapsed == 0) {
            return l.initialBnomeDistribution;
        }

        // 使用位移操作计算2的幂，最大支持到2^256
        uint256 halvingFactor = 1 << (quartersElapsed > 255 ? 255 : quartersElapsed);
        return l.initialBnomeDistribution / halvingFactor;
    }

    function _getSwapOutBnomeFromUsda(uint256 usdaAmount) internal view returns (uint256) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        IConfig config = IConfig(l.config);
        uint256 swapOutBnome = _getSwapTokenOut(
            config.baseToken(),
            config.bnome(),
            UtilsLib.convertDecimals(usdaAmount, config.usda(), config.baseToken())
        );
        // BNome最低价为0.1USDA
        uint256 maxBnome = usdaAmount * 10;
        return UtilsLib.min(swapOutBnome, maxBnome);
    }

    function _getSwapOutUsdaFromBnome(uint256 bnomeAmount) internal view returns (uint256) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        IConfig config = IConfig(l.config);
        uint256 swapOutUsda = UtilsLib.convertDecimals(
            _getSwapTokenOut(config.bnome(), config.baseToken(), bnomeAmount),
            config.baseToken(),
            config.usda()
        );
        // BNome最低价为0.1USDA
        uint256 minUsda = bnomeAmount / 10;
        return UtilsLib.max(swapOutUsda, minUsda);
    }

    function _getSwapTokenOut(address tokenA, address tokenB, uint256 amountA) internal view returns (uint256) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        IConfig config = IConfig(l.config);
        IUniswapV2Router01 router = IUniswapV2Router01(config.anomeDexRouter());
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        return router.getAmountsOut(amountA, path)[1];
    }

    function _isProfitable(address account) internal view returns (bool) {
        // 是否处于盈利状态
        ShopStorage.Layout storage l = ShopStorage.layout();
        return _totalIncome(account) >= l.lossBattleCost[account];
    }

    function _totalIncome(address account) internal view returns (uint256) {
        // 用户的总收入, 含补偿, 金本位
        ShopStorage.Layout storage l = ShopStorage.layout();
        return l.lossBattleIncome[account] + l.xnomeTotalValue[account] + l.totalCompensationValue[account];
    }

    function _currentDay() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }
}
