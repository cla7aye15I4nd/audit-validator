# Missing Checks For the Input `_quantity`


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `3b0e52d0-c146-11ee-ae19-71a31a818f9a` |
| Commit | `fcd5c03bac962563da1a26c5eaf66e9bb148c9b2` |

## Location

- **Local path:** `./src/MarketplaceV2/contracts/facets/listing/ListingWriteableFacet.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/3b0e52d0-c146-11ee-ae19-71a31a818f9a/source?file=$/github/gameofsilks/Silks-Contracts/f20dcf493ca2c002b3c20f979b908cb4add58983/MarketplaceV2/contracts/facets/listing/ListingWriteableFacet.sol
- **Lines:** 98–98

## Description

In the `_purchaseListing()` function, the contract uses the `_quantity` to calculate the required native tokens. It is noted that `_quantity` is input by the user and the contract does not compare the `_quantity` with the `Listing.numListed`. If a malicious user passes the **zero** to the `_quantity` to buy an ERC721 token, since the `_listing.pricePer * _quantity` equals 0 and the validation and transfer of ERC721 token is not related to the `_quantity`, the user can get the listed ERC721 token with `msg.value=0`.

In addition, there is another scenario, that may cause the result of trade not to align with the seller's expectation.
1. A seller named Amy owns 10 of an ERC1155 token(ID:100) and created a listing with `numListed=5` since Amy still wants to hold part of this token.
2. The buyer named Bob also likes this token(tokenID: 100) and purchases this listing with the `_quantity=10`.
3. Amy holds 0, and Bob holds 10 of this token. 
4. The result does not align with his expectations.

## Recommendation

We recommend adding sanity checks for the input `_quantity`.

## Vulnerable Code

```
public
    whenNotPaused
    whenNotPartiallyPaused(LISTINGS_PAUSED)
    {
        ListingStorage.Layout storage ll = ListingStorage.layout();
        Listing storage listing = ll.listings[_listingId];
        
        if (listing.seller != msg.sender || listing.buyer != address(0)){
            revert("INV_UPDATE_REQUEST");
        }
        
        ListingStorage.updateListing(Listing(
            _listingId,
            _listingAddress,
            msg.sender,
            address(0), // Initial buyer is set to address 0 (no buyer yet)
            _tokenId,
            _numListed,
            _pricePer,
            _royaltyPct,
            _active,
            true // Set the listing as valid upon creation
        ));
        
        emit ListingUpdated(_listingId, _listingAddress, msg.sender, address(0), _tokenId, _numListed, _pricePer, _royaltyPct, _active);
    }

    function _purchaseListing(
        Listing memory _listing,
        uint256 _quantity
    )
    internal
    {
        ListingStorage.Layout storage ll = ListingStorage.layout();
        
        // Ensure the asset can be legally sold
        ListingStorage.verifyAssetCanBeSold(_listing.listingAddress, _listing.seller, _listing.tokenId, _quantity);
        
        // Check if the sent value matches the listing price
        if ((_listing.pricePer * _quantity) != msg.value) {
            revert InvalidIntValue("INV_ETH_TOTAL", msg.value, (_listing.pricePer * _quantity));
        }
        
        // Update the purchase record and mark the listing as sold
        ll.purchasesByAddress[msg.sender].add(_listing.listingId);
        _listing.buyer = msg.sender;
        _listing.active = false;
        
        ll.listings[_listing.listingId] = _listing;
        
        ll.activeListings.remove(_listing.listingId);
        
        // Remove the token from the set of tokens listed under this listing type
        EnumerableSet.UintSet storage tokensListedForListing = ll.tokensListedByListingAddress[_listing.listingAddress];
        tokensListedForListing.remove(_listing.tokenId);
        
        SilksMarketplaceStorage.Layout storage lmp = SilksMarketplaceStorage.layout();
        
        // Calculate and transfer royalty amount
        uint256 royaltyAmt = (msg.value * _listing.royaltyBasePoints) / 10000;
```
