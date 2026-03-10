# Missing Pool Balance Validation Allows USDA Overdraw


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

- **Local path:** `./source_code/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/battle/BattleServiceInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/battle/BattleServiceInternal.sol
- **Lines:** 233–248

## Description

Vulnerability:
_transferPoolUsda deducts from the pool’s internal usdaBalance but never prevents |amount| from exceeding that balance. If pool.usdaBalance < amount, it simply zeroes the balance and still calls IUSDA.transfer(receiver, amount). This disconnect between the recorded pool balance and the actual transfer lets the contract pay out more USDA than the pool holds, drawing against the contract’s general USDA reserves.

Exploit Demonstration:
1. Pick a cardId whose pool.usdaBalance has been drained below the expected destruction payout (e.g. pool.usdaBalance = 10 USDA).
2. Call the public destroyCard entry point (via the game contract) for that cardId. This invokes _destroyCardToIP, _destroyCardToTreasury and _destroyCardToSponsor in sequence.
3. In _destroyCardToIP:
   • releasedUsda = 100
   • ipAmount = (100 * 30%) = 30
   • pool.usdaBalance (10) < 30 ⇒ pool.usdaBalance = 0
   • IUSDA.transfer(IPReceiver, 30) still executes, sending 30 USDA
4. In _destroyCardToTreasury:
   • treasuryAmount = (100 * 25%) = 25
   • pool.usdaBalance (0) < 25 ⇒ pool.usdaBalance = 0
   • IUSDA.transfer(treasuryPayee, 25) still executes, sending 25 USDA
5. In _destroyCardToSponsor:
   • sponsorAmount = (100 * 2.5%) = 2.5
   • For each sponsor: pool.usdaBalance (0) < 2.5 ⇒ zero and transfer 2.5 USDA twice
6. The contract transfers a total of 30 + 25 + 2.5 + 2.5 = 60 USDA, despite the pool having only 10. Repeating this against any depleted pool lets you drain the contract’s USDA reserves beyond what was allocated to that pool. Continuous monitoring of the contract’s USDA token balance before and after each destroyCard call confirms the overdraw.

## Vulnerable Code

```
function _transferPoolUsda(uint256 cardId, address receiver, uint256 amount) internal {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.CardPool storage pool = data.pools[cardId];

        if (pool.usdaBalance > amount) {
            pool.usdaBalance -= amount;
        } else {
            pool.usdaBalance = 0;
        }

        if (receiver == address(0)) {
            receiver = data.config.cardDestroyPayee();
        }

        IUSDA(data.config.usda()).transfer(receiver, amount);
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

cardDestroyPayee -> None

usda -> None
```
