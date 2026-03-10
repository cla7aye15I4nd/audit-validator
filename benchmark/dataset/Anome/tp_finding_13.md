# Incorrect HighBorrowLTVLimit Decrement Enables Over-Borrowing


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

- **Local path:** `./source_code/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/borrow/BorrowShopInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/borrow/BorrowShopInternal.sol
- **Lines:** 23–74

## Description

Vulnerability: The function checks if highBorrowLTVLimit ≥ price, then computes borrowAmount = price * highBorrowLTV / DIVIDEND but subtracts this smaller borrowAmount from highBorrowLTVLimit. Since highBorrowLTV < 100%, borrowAmount < price, so the limit is consumed more slowly than intended, allowing more high-LTV borrowing than the original limit.

Exploit Steps:
1. Precondition: Choose a card pool where each card’s price is 50 USDA. Parameters: highBorrowLTV = 8000 (80%), borrowLtv = 5000 (50%). Attacker’s highBorrowLTVLimit = 100.
2. Borrow Card #1:
   - highBorrowLTVLimit (100) ≥ price (50) → branch 1.
   - borrowAmount = 50 * 8000 / 10000 = 40.
   - highBorrowLTVLimit = 100 – 40 = 60.
   - Attacker receives 40 USDA.
3. Borrow Card #2:
   - highBorrowLTVLimit (60) ≥ price (50) → branch 1.
   - borrowAmount = 50 * 8000 / 10000 = 40.
   - highBorrowLTVLimit = 60 – 40 = 20.
   - Attacker receives 40 more USDA (total 80).
4. Borrow Card #3:
   - highBorrowLTVLimit (20) < price (50) → branch 2.
   - High-LTV portion = 20 * 8000 / 10000 = 16.
   - Remaining = 50 – 20 = 30.
   - Base-LTV portion = 30 * 5000 / 10000 = 15.
   - borrowAmount = 16 + 15 = 31.
   - highBorrowLTVLimit = 0.
   - Attacker receives 31 more USDA (total 111).
5. Result: The attacker borrows 111 USDA against an initial highBorrowLTVLimit of 100, over-extracting 11 USDA beyond the intended cap.

## Vulnerable Code

```
function _borrow(address card, uint256 cardId) internal commonCheck noContractCall updateBorrowIndex {
        checkCardAndId(card, cardId);

        address account = msg.sender;
        ShopStorage.Layout storage data = ShopStorage.layout();
        uint256 poolIndex = data.cardsIndex[card];
        ShopTypes.CardPool storage pool = data.pools[poolIndex];

        // 执行借贷操作
        uint256 price = _priceOf(poolIndex);
        uint256 borrowAmount;
        if (data.highBorrowLTVLimit[account] >= price) {
            borrowAmount = (price * data.highBorrowLTV) / ShopStorage.DIVIDEND;
            data.highBorrowLTVLimit[account] -= borrowAmount;
        } else {
            borrowAmount = (data.highBorrowLTVLimit[account] * data.highBorrowLTV) / ShopStorage.DIVIDEND;
            uint256 remaining = price - data.highBorrowLTVLimit[account];
            borrowAmount += (remaining * data.borrowLtv) / ShopStorage.DIVIDEND;
            data.highBorrowLTVLimit[account] = 0;
        }

        pool.card.safeTransferFrom(account, address(this), cardId);
        pool.cardDecreaseVirtualBalance += 1;

        // 转走锚定物, 并且记录数量
        IUSDA(data.config.usda()).transfer(account, borrowAmount);

        // 创建订单
        ShopTypes.BorrowOrder[] storage orders = data.borrowOrderBook[account];
        data.borrowOrderIndex[account][card][cardId] = orders.length;

        // 创建订单
        ShopTypes.BorrowOrder memory order = ShopTypes.BorrowOrder({
            index: orders.length,
            pool: poolIndex,
            isRepaid: false,
            card: pool.card,
            cardId: cardId,
            cardPrice: price,
            borrowIndex: data.borrowIndex,
            borrowAmount: borrowAmount,
            borrowInterest: data.borrowRate,
            createsAt: block.timestamp,
            repayPrice: 0,
            repayIndex: 0,
            repayAmount: 0,
            repayAt: 0
        });
        orders.push(order);

        emit Borrowed(account, order);
    }
```

## Related Context

```
checkCardAndId ->     function checkCardAndId(address card, uint256 cardId) internal {
        if (!_isCardInPool(card)) {
            revert InvalidCardAddress();
        }

        if (!_isCardIdValid(card, cardId)) {
            revert InvalidCardId();
        }
    }

layout ->     function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

_priceOf ->     /**
     * 价格 = BaseToken余额 / Card流通量
     * Card流通量 = Card总量 - Card合约余额 - Card销毁量
     *
     * 购买卡牌时, 流通量+1, BaseToken余额 + 价格, 所以价格不变
     * 卖出卡牌时, 流通量-1 -> 池子, BaseToken余额 - 价格, 所以价格不变
     * 销毁卡牌时, 流通量-1 -> 池子, BaseToken余额 - (价格 * 60%), 所以价格上涨
     */
    function _priceOf(uint256 index) internal view returns (uint256 price) {
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

usda -> None
```
