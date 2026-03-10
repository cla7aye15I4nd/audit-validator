# Denial-of-Service on profit claims by sending extra OG NFT


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | The use can transfer the NFT |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./src/projects/anome 2/og_nft/guild/GameGuild.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/og_nft/guild/GameGuild.sol
- **Lines:** 18–20

## Description

In _claimProfit the code insists that msg.sender must hold exactly one OG NFT (balance == 1) and will revert with HoldMoreThanOneOg if the balance exceeds one. Because OG NFTs follow the standard ERC-721 transfer logic, an attacker who owns at least one OG NFT can gift or transfer an extra OG NFT to any target address. Once that address holds two NFTs, any call to claimProfit(…) by that address will fail at the “> 1” check, trapping all future profit claims for any OG ID until the extra NFT is removed.

Exploit Steps:
1. Attacker acquires any OG NFT (e.g. by minting or purchasing).
2. Attacker calls safeTransferFrom(attacker, victim, extraOgId) to transfer their NFT to the victim’s address.
3. The victim’s balance is now 2. Any call to claimProfit(ogId) (for either of their two NFTs) executes _claimProfit:
   • _balanceOf(victim) == 2 → triggers revert HoldMoreThanOneOg()
4. As long as the victim’s balance remains > 1, they cannot ever reach the branch that pays out profit, effectively denying them service.

This is purely a logical flaw in the balance check: by gating profit on holding exactly one NFT, the contract can be put into a permanent denial-of-service state for any user who is sent an extra OG NFT.

## Vulnerable Code

```
function claimProfit(uint256 ogId) external override {
        _claimProfit(msg.sender, ogId);
    }
```

## Related Context

```
_claimProfit ->     function _claimProfit(address account, uint256 ogId) internal {
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
