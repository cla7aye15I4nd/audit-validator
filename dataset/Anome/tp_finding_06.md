# Flat Pricing Calculation Underprices Bulk Card Purchases


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

- **Local path:** `./src/projects/anome 2/shop/card/CardShopInternal.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/card/CardShopInternal.sol
- **Lines:** 26–49

## Description

Vulnerability: The _buyCard function computes the total purchase cost for count cards as a single call to _priceOf(index) multiplied by count. However, _priceOf(index) is designed to return a dynamic unit price that increases with each card sold (e.g. on a bonding curve or incremental pricing scheme). By calculating totalCost = unitPrice * count using only the initial unitPrice, the contract undercharges for every card after the first. The correct logic should accumulate the price for each card as the pool’s state (pool.usdaBalance) changes with each sale.

Exploit Demonstration: An attacker can buy multiple cards in one transaction and pay only the initial unit price for all of them, effectively receiving a bulk discount.  
1. Choose a card pool index where dynamic pricing is active and ensure selling is enabled (sellStartsAt[index] ≤ block.timestamp).  
2. Call the public buyCard wrapper that invokes _buyCard(index, count, attacker) with count > 1.  
   – The contract reads unitPrice = _priceOf(index) based on the current pool.usdaBalance.  
   – It calculates totalCost = unitPrice * count, undercharging for cards whose price should have risen.  
   – It transfers baseTokenAmount = convertDecimals(totalCost) from the attacker to buyCardPayee and mints totalCost USDA to the shop.  
   – It transfers count cards to the attacker.  
3. (Optional) If immediate selling is allowed, the attacker then calls sellCard(index, count):  
   – The contract now has pool.usdaBalance increased by totalCost, so _priceOf(index) returns a higher unitPriceAfter > unitPrice.  
   – sellCard computes refund = unitPriceAfter * count, deducts pool.usdaBalance by refund, and transfers 95% of refund in USDA back to the attacker.  
4. Profit arises because the attacker paid unitPrice * count but can sell at unitPriceAfter * count * 95%. Even without selling back, the attacker has acquired cards at below-market cost and can realize the gain by selling on secondary markets.  

By batching purchases via count > 1, the attacker exploits the flat-pricing logic to significantly underpay for cards whose price should have been higher after each incremental sale.

## Vulnerable Code

```
function _buyCard(uint256 index, uint256 count, address recipient) internal commonCheck {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.CardPool storage pool = data.pools[index];

        if (address(pool.card) == address(0)) revert InvalidCardAddress();
        if (data.isCardMintBanned[index] && msg.sender != data.config.caller()) revert CardMintBanned();

        (, uint256 stock, , ) = _circulationInfoOf(index);
        if (count == 0) revert InvalidShopAmount();
        if (count > stock) revert SoldOut();

        uint256 usdaPrice = _priceOf(index) * count;
        uint256 baseTokenAmount = UtilsLib.convertDecimals(usdaPrice, data.config.usda(), data.config.baseToken());
        pool.usdaBalance += usdaPrice;

        // 为了支持1:1兑换, 所以需要将baseToken转到合约
        // IERC20(data.config.baseToken()).safeTransferFrom(msg.sender, address(this), baseTokenAmount);
        IERC20(data.config.baseToken()).safeTransferFrom(msg.sender, data.config.buyCardPayee(), baseTokenAmount);
        IUSDA(data.config.usda()).mint(address(this), usdaPrice);

        pool.card.transfer(recipient, count * pool.card.getUnit());

        emit CardBought(recipient, address(pool.card), count * pool.card.getUnit(), baseTokenAmount);
    }
```
