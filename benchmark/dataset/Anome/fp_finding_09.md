# lossBattleCost Inflated by Net Losses from Winning Games During Migration


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Intended design |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./source_code/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/mining/BattleMiningInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/mining/BattleMiningInternal.sol
- **Lines:** 212–228

## Description

The `_migrateLossBattleCostAndIncome` function incorrectly calculates a user's historical loss by using the formula `l.battleCost[account] - l.battleIncome[account]`. This formula calculates the user's total net loss across all games, including wins. The result, `historyLoss`, is then used to set `l.lossBattleCost[account]`, which is intended to track only the sum of costs from games the user has lost. If a user achieves a 'pyrrhic victory'—a win where the net result is a loss (i.e., `destroyValue > loserCost`)—the net loss from that winning game is improperly factored into `lossBattleCost` during the one-time migration. This artificially inflates the value used for calculating loss compensation, allowing a user to claim more compensation than they are legitimately entitled to.

**Exploit Demonstration:**

An attacker can exploit this flaw by first winning a game that results in a net loss, and then losing another game to trigger the flawed migration.

1.  **Initial State:** The attacker starts with a new account where `battleCost = 0`, `battleIncome = 0`, `lossBattleCost = 0`, and `isAccountBattleMiningMigrated = false`.

2.  **Execute a 'Pyrrhic Victory':** The attacker plays and wins a game where the parameters result in a net loss for the winner. For example, assume a game with `winnerCost=100`, `loserCost=50`, and `destroyValue=60`. 
    *   The winner's net income for this game is `loserCost - destroyValue`, which is `50 - 60 = -10`. 
    *   After this game, the attacker's state becomes `battleCost = 100` and `battleIncome = 90`. Since the account started at zero, the migration logic was skipped.

3.  **Trigger the Flawed Migration:** The attacker then plays a second game and intentionally loses. Assume the cost of this loss is `100`.
    *   The `_setCostIncome` function is called for the attacker as the `loser`. It immediately calls `_migrateLossBattleCostAndIncome`.
    *   The migration function sees that the attacker's `battleCost` (100) is now greater than their `battleIncome` (90), so it proceeds.
    *   It calculates `historyLoss = 100 - 90 = 10`. This value represents the net loss from the 'winning' game.
    *   It sets `l.lossBattleCost[account] = UtilsLib.max(historyLoss, l.lossBattleCost[account])`, resulting in `lossBattleCost` becoming `10`.
    *   The migration flag `isAccountBattleMiningMigrated` is set to `true`.

4.  **Confirm Inflated Loss Value:** Control returns to `_setCostIncome`, which proceeds to account for the current loss.
    *   It adds the cost of the lost game to the newly migrated `lossBattleCost`: `l.lossBattleCost[account] += 100`.
    *   The attacker's final `lossBattleCost` becomes `10 (from migration) + 100 (from the actual loss) = 110`.

5.  **Result:** The attacker has only truly lost one game with a cost of `100`, but their `lossBattleCost` is recorded as `110`. This inflated value allows them to call `_claimLossCompensation` and receive rewards based on losses they never actually incurred in losing games.

## Vulnerable Code

```
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
```

## Related Context

```
layout ->     function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

max ->     function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
```
