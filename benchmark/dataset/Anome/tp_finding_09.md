# Integer Division Remainder Permanently Locked in Xnome Distribution


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | — |
| Triage Verdict | ✅ Valid |
| Triage Reason | Valid finding |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./source_code/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/mining/BattleMiningInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/mining/BattleMiningInternal.sol
- **Lines:** 20–51

## Description

Vulnerability:
In _distributeXnome, totalXnome is divided evenly into 50 daily installments using integer division (totalXnome / 50). Any remainder (totalXnome % 50) is still added to xnomeTotal and xnomeTotalLocked but is never scheduled in xnomeDailyUnlocked. Those leftover tokens remain in locked state and can never be claimed.

Exploit Demonstration:
1. Arrange a battle (or otherwise invoke the call path) so that destroyValueUsda and the current swap rates yield totalXnome = 101.
2. Call the public function that triggers internal _distributeXnome(to, destroyValueUsda).
3. Inside _distributeXnome, the loop adds (101 / 50) = 2 tokens per day to l.xnomeDailyUnlocked[to][day] for the next 50 days. The single-token remainder (101 % 50 = 1) is never scheduled.
4. Over the next 50 days, call the Xnome claim function each day. Each claim transfers 2 tokens, for a total of 100 tokens claimed.
5. After 50 days, no further xnomeDailyUnlocked entries exist; the remaining 1 token stays in l.xnomeTotalLocked[to] with no way to unlock it.

Result: Out of 101 minted tokens the user only ever can claim 100; the 1-token remainder is effectively unrecoverable.

## Vulnerable Code

```
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
```

## Related Context

```
layout ->     function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

_getCurrentXnomeDistributionAmount ->     function _getCurrentXnomeDistributionAmount(uint256 destroyValueUsda) internal view returns (uint256) {
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

_getSwapOutBnomeFromUsda ->     function _getSwapOutBnomeFromUsda(uint256 usdaAmount) internal view returns (uint256) {
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

_currentDay ->     function _currentDay() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }
```
