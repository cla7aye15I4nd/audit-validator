# Miscalculated high‐LTV limit consumption enables over‐borrowing across multiple cards


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

- **Local path:** `./src/projects/anome 2/shop/borrow/BorrowShop.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/borrow/BorrowShop.sol
- **Lines:** 14–18

## Description

Vulnerability Details
The internal _borrow routine uses two pieces of state to enforce a high‐LTV borrowing cap: data.highBorrowLTVLimit[account] (the remaining allowance for high‐LTV debt) and the price of the NFT collateral (price). However, the code checks “if highBorrowLTVLimit >= price” but then deducts borrowAmount = price × highBorrowLTV / DIVIDEND from highBorrowLTVLimit. Since price × highBorrowLTV < price, the high‐LTV allowance is consumed more slowly than intended. When _borrow is called repeatedly (via multiBorrow), an attacker can borrow at the high LTV rate on more total collateral than the initial limit should permit.

Exploit Steps
1. Preconditions
   • The attacker’s account has staked enough Bnome (or equivalent) so that data.highBorrowLTVLimit[msg.sender] = 150 USD.
   • Protocol parameters: highBorrowLTV = 80% (0.8), borrowLtv = 50% (0.5), DIVIDEND = 1.  (All values in USD for clarity.)
   • The attacker holds two NFTs (NFT1 and NFT2), each priced at 100 USD as returned by _priceOf.

2. Construct the array
   • Prepare an array of two Card721 structs:
       cards[0] = { card: NFT1_contract, id: NFT1_id }
       cards[1] = { card: NFT2_contract, id: NFT2_id }

3. Call multiBorrow(cards)
   • The for-loop invokes _borrow on NFT1 first, then NFT2.

4. First iteration (_borrow on NFT1)
   • highBorrowLTVLimit (150) >= price (100) ⇒ high-LTV branch.
   • borrowAmount1 = 100 × 0.8 = 80 USDA.
   • highBorrowLTVLimit := 150 – 80 = 70.
   • NFT1 is transferred in; USDA 80 is minted to the attacker.

5. Second iteration (_borrow on NFT2)
   • highBorrowLTVLimit (70) < price (100) ⇒ partial high-LTV branch.
   • highPortion = 70 × 0.8 = 56 USDA.
   • remaining = 100 – 70 = 30.
   • lowPortion = 30 × 0.5 = 15 USDA.
   • borrowAmount2 = 56 + 15 = 71 USDA.
   • highBorrowLTVLimit := 0.
   • NFT2 is transferred in; USDA 71 is minted to the attacker.

6. Outcome
   • Total USDA minted = 80 + 71 = 151.
   • Under a correct high‐LTV limit, the attacker should never have been able to borrow more than 150 × 0.8 = 120 USDA at the high rate, plus at most 150 × 0.5 = 75 USDA at the low rate (if the logic had been applied to the full 150 USD of collateral). Instead the attacker obtains 151 USDA against only 150 USD of high‐LTV allowance—exceeding the intended cap.

Why It’s a Logical Bug
• The check uses highBorrowLTVLimit >= price (collateral units) but then decrements by borrowAmount (debt units), mixing units and under‐consuming the allowance.
• Sequential execution over multiple cards (via multiBorrow) compounds the under-consumption, allowing more high-LTV debt than permitted by the initial limit.

Practical Confirmation
1. Fund an account to set highBorrowLTVLimit to 150.
2. Acquire two 100 USD-valued cards.
3. Invoke multiBorrow([card1, card2]).
4. Observe that total USDA out > 150 USD × highBorrowLTV.
5. Conclude that the high-LTV cap is bypassed due to incorrect limit consumption.

## Vulnerable Code

```
function multiBorrow(ShopTypes.Card721[] memory cards) external {
        for (uint i = 0; i < cards.length; i++) {
            _borrow(cards[i].card, cards[i].id);
        }
    }
```

## Related Context

```
_borrow ->     function _borrow(address card, uint256 cardId) internal commonCheck noContractCall updateBorrowIndex {
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
