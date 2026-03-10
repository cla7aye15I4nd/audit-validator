# Reentrancy in `_createNFT` Leads to Inconsistent Ledger State


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | — |
| Triage Verdict | ✅ Valid |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./src/GLDB Pulse Contracts/ENT&Swap/NFT.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/NFT.sol
- **Lines:** 1–1

## Description

The `_createNFT` function is vulnerable to a reentrancy attack that causes the internal accounting ledger to become permanently inconsistent with the actual NFT balances. The function first mints NFTs to `partyA` via the `_swap` function and then updates an internal ledger, `TOTAL_HOLD`, via `_updateTotalHold`. The `_mint` operation within `_swap` can trigger an `onERC1155Received` hook on `partyA` if it is a contract. An attacker can use this hook to re-enter the `NFT` contract and call `processCondition`, leading to the settlement of the newly minted NFTs. The `_settle` function burns the NFTs and pays out the corresponding tokens but fails to update the `TOTAL_HOLD` ledger. When control returns to `_createNFT`, it proceeds to increment the `TOTAL_HOLD` for `partyA`, creating a record of ownership for NFTs that have already been burned. This results in a permanent discrepancy where the internal ledger shows a balance that does not exist, potentially misleading any party that relies on this accounting.

**Exploit Demonstration:**

1. Attacker deploys a malicious contract, `AttackerContract`, which will act as `partyA`.
2. Attacker, as the `sender`, calls `createNFTsFromTokens`, specifying `AttackerContract` as `partyA` (the receiver). The NFT is configured such that `_createNFT` is not called immediately, and `AttackerContract` is the operator of a condition.
3. `AttackerContract` calls `setConditionStartTimestamp` (or `setExecutionStartTimestamp`) to trigger the execution of `_createNFT`.
4. The `_createNFT` function begins execution:
    a. It calls `_changeNFTStatus`, setting the NFT's status to `CREATED`.
    b. It calls `_swap`, which mints the NFTs to `AttackerContract`. This triggers the `onERC1155Received` function on `AttackerContract`.
5. Inside `onERC1155Received`, `AttackerContract` re-enters the `NFT` contract by calling `processCondition`.
6. `processCondition` validates the call and proceeds to `_triggerPay`, which determines the conditions are met and calls `_settle`.
7. The `_settle` function burns the NFTs just minted to `AttackerContract` and transfers the underlying ERC20 tokens to it.
8. Control returns to `_createNFT`, which was paused at the `_swap` call.
9. `_createNFT` executes its next line: `_updateTotalHold(nftId, nft.partyA, nft.amount, true)`. This increments the `TOTAL_HOLD` ledger for `AttackerContract`.

**Outcome:** The `AttackerContract` has successfully redeemed the NFTs for tokens. However, the `TOTAL_HOLD` ledger now incorrectly shows that `AttackerContract` holds a balance of NFTs, even though they were burned. The contract's internal accounting is now permanently out of sync with the actual state of NFT ownership.

## Vulnerable Code

```
function _createNFT(uint256 nftId, NFTMetadata storage nft) private {
        _changeNFTStatus(nftId, nft, NFTStatus.CREATED);
        nft.nftCreatedAt = uint40(block.timestamp);
        _swap(nft.sender, nft.partyA, nftId, nft.amount);
        _updateTotalHold(nftId, nft.partyA, nft.amount, true);
    }
```

## Related Context

```
_changeNFTStatus ->     function _changeNFTStatus(uint256 nftId, NFTMetadata storage nft, NFTStatus status) private {
        NFTStatus preStatus = nft.status;
        if (preStatus == status) {
            return;
        }
        nft.status = status;
        emit NFTStatusChanged(nftId, status, preStatus);
    }

_swap ->     function _swap(address from, address to, uint256 nftId, uint256 amount) internal {
        IERC20(tokenAddress).safeTransferFrom(from, address(this), amount);
        super._mint(to, nftId, amount, "");
        emit NFTMinted(nftId, from, to, amount);
    }

_updateTotalHold -> function _updateTotalHold(uint256 nftId, address account, uint256 amount, bool increase) internal {
        mapping(NFTStatisticsType => uint256) storage r = _getNFTStorage().nftActivityLedger[nftId][account];
        if (increase) {
            r[NFTStatisticsType.TOTAL_HOLD] += amount;
        } else {
            r[NFTStatisticsType.TOTAL_HOLD] -= amount;
        }
    }
```
