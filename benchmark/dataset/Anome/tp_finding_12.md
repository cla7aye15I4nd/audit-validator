# Missing LTV reduction on BNOME unstake enables collateral‐free borrowing


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

- **Local path:** `./src/projects/anome 2/shop/stake/BnomeStakeInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/stake/BnomeStakeInternal.sol
- **Lines:** 60–80

## Description

Vulnerability:
The `_unstakeBnome` function returns the user’s staked BNOME tokens but never decreases the `highBorrowLTVLimit` (or the mirror `bnomeAccountTotalHighBorrowLTVLimit`) that was granted when those tokens were staked. As a result, after calling `unstakeBnome`, a user recovers their BNOME but still retains the full LTV allowance.

Exploit Demonstration:
1. Attacker approves and calls `stakeBnome(X)` with X BNOME. This transfers X BNOME into the contract and increases `highBorrowLTVLimit[msg.sender]` by a value V (derived from X).
2. Immediately call `unstakeBnome(0)` (the index of the newly created stake order). The contract transfers X BNOME back to the attacker, but leaves `highBorrowLTVLimit[msg.sender] == V` unchanged.
3. With zero BNOME locked, call the borrowing function (e.g. `borrowUsda`) to draw up to V worth of assets. The system sees a non‐zero LTV limit and permits borrowing despite the attacker having no collateral.

Result:
The attacker can repeatedly borrow against the residual LTV allowance without posting any collateral, draining the protocol’s available borrowable assets.

## Vulnerable Code

```
function _unstakeBnome(uint256 index) internal commonCheck noContractCall {
        ShopStorage.Layout storage l = ShopStorage.layout();
        IConfig config = IConfig(l.config);
        address account = msg.sender;
        ShopTypes.BnomeStakeOrder storage order = l.bnomeStakeOrders[account][index];

        if (order.unstakedAmount >= order.bnomeAmount) {
            revert AlreadyUnstaked();
        }

        uint256 unlockedBnome = _getUnlockedBnome(index);
        if ((unlockedBnome + order.unstakedAmount) > order.bnomeAmount) {
            unlockedBnome = order.bnomeAmount - order.unstakedAmount;
        }

        IERC20(config.bnome()).safeTransfer(account, unlockedBnome);

        order.unstakedAmount += unlockedBnome;
        l.bnomeTotalUnstaked += unlockedBnome;
        l.bnomeAccountTotalUnstaked[account] += unlockedBnome;
    }
```

## Related Context

```
layout -> function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

bnome -> None

_getUnlockedBnome ->     function _getUnlockedBnome(uint256 index) internal view returns (uint256) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        ShopTypes.BnomeStakeOrder storage order = l.bnomeStakeOrders[msg.sender][index];
        (uint256 supply, , uint256 destruction, ) = _circulationInfoOf(order.anchorCard);
        uint256 orderDestruction = destruction - order.anchorCardInitialDestruction;
        uint256 totalUnlocked = (order.bnomeAmount * orderDestruction) / supply;
        return totalUnlocked - order.unstakedAmount;
    }
```
