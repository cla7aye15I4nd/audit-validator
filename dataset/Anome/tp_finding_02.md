# Fixed 1e18 Collateral Return Ignores Actual Deposit, Enabling Card‐Token Drain


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

- **Local path:** `./src/projects/anome 2/shop/borrow/BorrowShopInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/borrow/BorrowShopInternal.sol
- **Lines:** 110–139

## Description

In the _repay function, the contract returns exactly 1e18 units of the pool’s card token unconditionally:
    pool.card.transfer(account, 1e18);
It never uses order.cardId (the actual amount or NFT ID the borrower posted as collateral). As a result, an attacker can deposit a minimal collateral amount when borrowing, and then—after seeding the contract’s card‐token reserves by any prior borrow/repay cycle—call _repay to withdraw a full 1e18 units. This drains the contract of card tokens.

Exploit steps:
1. Pre-fund the contract’s card balance:
   • Call borrow(card, cardId = 1e18). That safeTransferFroms 1e18 units of card tokens into the contract.
   • Approve and call _repay(0) to repay the order. The contract transfers back exactly 1e18 units, restoring its balance (net zero).  
   (After this step the contract holds 1e18 from its own reserves; see step 4.)
2. Attack setup – seed reserves:
   • Repeat step 1 once more. Now the contract’s on-chain balance of card tokens is 1e18 (net gain of 1e18).  
3. Minimal collateral borrow:
   • Approve pool.card for an amount of just 1 (smallest unit).
   • Call borrow(card, cardId = 1). The contract safeTransferFroms only 1 token into itself, but records exactly one card "unit" in pool.cardDecreaseVirtualBalance.
4. Draining _repay:
   • Approve the required USDA for _repay(1) and invoke it.
   • _repay computes and collects your USDA, then calls pool.card.transfer(account, 1e18). Because the contract holds at least 1e18 from step 2, it sends you back 1e18 tokens despite your deposit being only 1.
5. Net result: you recover your 1e18 seed, plus an extra  (1e18 – 1) tokens from the contract’s reserves.

Repeatedly executing step 3–4 drains all of the pool.card token balance. This flaw stems from ignoring order.cardId and hard-coding a 1e18 return amount instead of returning the exact collateral posted.

## Vulnerable Code

```
function _repay(uint256 orderIndex) internal commonCheck noContractCall updateBorrowIndex {
        address account = msg.sender;
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.BorrowOrder storage order = data.borrowOrderBook[account][orderIndex];
        ShopTypes.CardPool storage pool = data.pools[order.pool];
        uint256 price = _priceOf(order.pool);

        if (order.isRepaid) {
            revert AlreadyRepaid();
        }

        // 滑扣USDA, 本金留在合约中
        (uint256 repayAmount, uint256 interest) = _getRepayAmount(account, orderIndex);
        IUSDA(data.config.usda()).safeTransferFrom(account, address(this), repayAmount);
        IUSDA(data.config.usda()).safeTransfer(data.config.treasury(), interest);

        // 转回卡牌
        pool.card.transfer(account, 1e18);
        pool.cardDecreaseVirtualBalance -= 1;

        // 清理数据状态
        delete data.borrowOrderIndex[account][address(order.card)][order.cardId];
        order.isRepaid = true;
        order.repayPrice = price;
        order.repayIndex = data.borrowIndex;
        order.repayAmount = repayAmount;
        order.repayAt = block.timestamp;

        emit Repaid(account, order);
    }
```

## Related Context

```
layout ->         function layout() internal pure returns (Layout storage l) {
            bytes32 slot = STORAGE_SLOT;
            assembly {
                l.slot := slot
            }
        }

_priceOf ->     function _priceOf(uint256 index) internal view returns (uint256 price) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.CardPool storage pool = data.pools[index];

        uint256 usdaBalance = pool.usdaBalance + pool.usdaIncreaseVirtualBalance;
        if (usdaBalance == 0) revert InvalidPriceUsdaBalance();

        (uint256 supply, uint256 stock, uint256 destruction, uint256 circulation) = _circulationInfoOf(index);
        if ((stock + destruction) > supply) revert InvalidPriceCardSupply();
        if (circulation == 0) revert InvalidPriceCardCirculation();

        price = usdaBalance / circulation;
        if (price == 0) revert InvalidPrice();

        return price;
    }

_getRepayAmount ->     function _getRepayAmount(
        address account,
        uint256 orderIndex
    ) internal view returns (uint256 repayAmount, uint256 interest) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.BorrowOrder memory order = data.borrowOrderBook[account][orderIndex];
        repayAmount = order.borrowAmount * 1e27;
        repayAmount = repayAmount.rayDiv(order.borrowIndex).rayMul(data.borrowIndex);
        repayAmount = repayAmount / 1e27;

        interest = repayAmount - order.borrowAmount;
    }
```
