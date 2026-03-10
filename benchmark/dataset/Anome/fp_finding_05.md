# Profit Claim Can Be Blocked by Airdropping an NFT


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | The use can transfer the NFT |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./src/projects/anome 2/og_nft/guild/GameGuildInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/og_nft/guild/GameGuildInternal.sol
- **Lines:** 82–110

## Description

The `_claimProfit` function contains a check, `_balanceOf(account) > 1`, that prevents a user from claiming profit if they own more than one OG NFT. This restriction, intended to enforce a 'one-NFT-per-claimer' rule, introduces a denial-of-service vulnerability. A malicious actor can exploit this by transferring an additional, potentially worthless, OG NFT to a victim who holds a single NFT with accrued profits. This action increases the victim's NFT balance to more than one, thereby blocking them from accessing the `_claimProfit` function and freezing their claimable profit. The victim must then take action to reduce their NFT count, such as transferring or selling one of their NFTs, before they can access their funds.

**Exploit Demonstration:**
1. A victim account holds a single OG NFT with `ogId=10`, which has accumulated a significant amount of claimable profit (e.g., 10,000 USDA).
2. An attacker, holding another OG NFT (`ogId=99`), transfers their NFT to the victim's address.
3. The victim now holds two OG NFTs, and their balance according to `_balanceOf(victim_address)` becomes 2.
4. The victim attempts to call the public function that executes `_claimProfit` for their `ogId=10`.
5. The function's initial check `if (_balanceOf(victim_address) > 1)` now evaluates to true, causing the transaction to revert with the `HoldMoreThanOneOg` error.
6. As a result, the victim is unable to claim their 10,000 USDA profit. Their funds are effectively frozen until they transfer one of the NFTs out of their wallet.

## Vulnerable Code

```
function _claimProfit(address account, uint256 ogId) internal {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();

        if (_balanceOf(account) == 0) {
            revert OgNftNotOwner();
        }

        if (_balanceOf(account) > 1) {
            revert HoldMoreThanOneOg();
        }

        if (_tokenOfOwnerByIndex(account, 0) != ogId) {
            revert OgNftNotOwner();
        }

        if (lg.ogClaimableProfit[ogId] == 0) {
            revert NoClaimableProfit();
        }

        uint256 amount = lg.ogClaimableProfit[ogId];
        lg.ogClaimableProfit[ogId] = 0;
        lg.ogClaimProfitRecord[ogId].push(
            GameGuildStorage.OgClaimProfitRecord({amount: amount, timestamp: block.timestamp})
        );

        IUSDA(lg.config.usda()).transfer(account, amount);

        emit ClaimOgProfit(ogId, account, amount);
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

usda -> None
```
