# Mismatched Count vs. NFT Transfer Allows Over-Payment


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | The cards are not NFT |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `e3c45370-51aa-11f0-bdd0-cbef849456d3` |
| Commit | `2a2826fcbafb5bed23f57406cc61e71a3ccffcf2` |

## Location

- **Local path:** `./source_code/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/card/CardShop.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e3c45370-51aa-11f0-bdd0-cbef849456d3/source?file=$/github/CertiKProject/certik-audit-projects/2a2826fcbafb5bed23f57406cc61e71a3ccffcf2/projects/anome 2/shop/card/CardShop.sol
- **Lines:** 40–42

## Description

The sellCard function computes the seller’s payout as _priceOf(index) × count, but calls safeTransferFrom with count × getUnit as a single tokenId. In other words, you pay for “count” cards yet only transfer one NFT. A malicious seller who owns the NFT with tokenId N can call sellCard(index, N):

1. Precondition: pool.card.getUnit() returns 1 (the usual unit for each NFT).  
2. The attacker acquires two cards in the pool (e.g. by calling buyCard(index, 2) and receiving tokenIds 1 and 2).  
3. Now call sellCard(index, 2).  
   - price = _priceOf(index) × 2  
   - pool.card.safeTransferFrom(msg.sender, this, 2 × 1 = tokenId 2)  
   - only the single NFT #2 is moved into the contract, but the attacker receives 2 × price worth of USDC.  
   - The attacker still owns tokenId 1.  
4. The attacker can repeat: buy back tokenId 2 (or mint/acquire it off-chain), then call sellCard(index, 2) again to pocket another unit-price of USDC without ever parting with more than one NFT per call.  

By mismatching the semantic meaning of count between price calculation and NFT transfer, an attacker can drain the pool’s USDC balance by repeatedly selling a single NFT for multiple card-prices.

## Vulnerable Code

```
function sellCard(uint256 index, uint256 count) external override {
        _sellCard(index, count);
    }
```

## Related Context

```
_sellCard ->     function _sellCard(uint256 index, uint256 count) internal commonCheck noContractCall {
        if (count == 0) revert InvalidShopAmount();

        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.CardPool storage pool = data.pools[index];

        if (data.sellStartsAt[index] > block.timestamp) revert CardRefundNotStarted();
        if (address(pool.card) == address(0)) revert InvalidCardAddress();

        uint256 price = _priceOf(index) * count;
        pool.usdaBalance -= price;
        IUSDA(data.config.usda()).transfer(data.config.treasury(), (price * 5) / 100);
        IUSDA(data.config.usda()).transfer(msg.sender, (price * 95) / 100);

        pool.card.safeTransferFrom(msg.sender, address(this), count * pool.card.getUnit(), "");

        emit CardSell(msg.sender, address(pool.card), count * pool.card.getUnit(), price);
    }
```
