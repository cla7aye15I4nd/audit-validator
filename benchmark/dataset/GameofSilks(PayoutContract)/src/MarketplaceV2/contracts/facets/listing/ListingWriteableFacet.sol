// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { PartiallyPausableInternal } from "@solidstate/contracts/security/partially_pausable/PartiallyPausableInternal.sol";
import { PausableInternal } from "@solidstate/contracts/security/pausable/PausableInternal.sol";
import { EnumerableSet } from "@solidstate/contracts/data/EnumerableSet.sol";
import { ERC721Base } from "@solidstate/contracts/token/ERC721/base/ERC721Base.sol";
import { AddressUtils } from "@solidstate/contracts/utils/AddressUtils.sol";

import "../../SilksMarketplaceStorage.sol";
import "./ListingStorage.sol";

/**
 * @dev Contract for creating and managing listings in a marketplace.
 *      Inherits Access Control, PartiallyPausable, and Pausable functionality.
 */
contract ListingWriteableFacet is
    PartiallyPausableInternal,
    PausableInternal
{
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;
    
    // Events for listing creation and purchase.
    event ListingCreated(bytes32 listingId, address listingAddress, address seller, address buyer, uint256 tokenId, uint256 _numListed, uint256 pricePer, uint256 royaltyBasePoints, bool active);
    event ListingUpdated(bytes32 listingId, address listingAddress, address seller, address buyer, uint256 tokenId, uint256 _numListed, uint256 pricePer, uint256 royaltyBasePoints, bool active);
    event ListingPurchased(bytes32 listingId, address listingAddress, address seller, address buyer, uint256 tokenId, uint256 _quantity, uint256 price, uint256 royaltyBasePoints, bool active);
    
    function createListing(
        bytes32 _listingId,
        address _listingAddress,
        uint256 _tokenId,
        uint256 _numListed,
        uint256 _pricePer,
        uint256 _royaltyPct,
        bool _active
    )
    public
    whenNotPaused
    whenNotPartiallyPaused(LISTINGS_PAUSED)
    {
        // Delegate the creation of the listing to the internal function _createListing.
        // The buyer is initially set to address(0), indicating that the listing is available for purchase.
        ListingStorage.createListing(Listing(
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
        
        emit ListingCreated(_listingId, _listingAddress, msg.sender, address(0), _tokenId, _numListed, _pricePer, _royaltyPct, _active);
    }
    
    function updateListing(
        bytes32 _listingId,
        address _listingAddress,
        uint256 _tokenId,
        uint256 _numListed,
        uint256 _pricePer,
        uint256 _royaltyPct,
        bool _active
    )
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
        AddressUtils.sendValue(payable(lmp.royaltyReceiver), royaltyAmt);
        
        // Transfer remaining amount to the seller
        uint256 amountToSeller = msg.value - royaltyAmt;
        AddressUtils.sendValue(payable(_listing.seller), amountToSeller);
        
        // Transfer tokens from seller to buyer
        ListingStorage.transferTokens(_listing.listingAddress, _listing.seller, _listing.buyer, _listing.tokenId, _quantity);
        
        // Emit an event for the listing purchase
        emit ListingPurchased(_listing.listingId, _listing.listingAddress, _listing.seller, msg.sender, _listing.tokenId, _quantity, _listing.pricePer, _listing.royaltyBasePoints, _listing.active);
    }
    
    function purchaseListingStoredOnContract(
        bytes32 _listingId,
        uint256 _quantity
    )
    public
    payable
    whenNotPaused
    whenNotPartiallyPaused(LISTINGS_PAUSED)
    {
        ListingStorage.Layout storage ll = ListingStorage.layout();
        Listing storage listing = ll.listings[_listingId];
        
        // Check if the listing is valid for purchase
        if (!listing.active || !listing.valid || listing.buyer != address(0)) {
            revert InvalidListing(_listingId);
        }
        
        if (listing.seller == msg.sender){
            revert("BUYER_SELLER_MATCH");
        }
        
        _purchaseListing(listing, _quantity);
    }
    
    function purchaseListingStoredOffContract(
        Listing memory _listing,
        uint256 _quantity,
        string memory _message,
        bytes memory _signature
    )
    public
    payable
    whenNotPaused
    whenNotPartiallyPaused(LISTINGS_PAUSED)
    {
        ListingStorage.Layout storage ll = ListingStorage.layout();
        
        // Check if the listing is valid for purchase
        if (ll.listings[_listing.listingId].valid) {
            revert ListingAlreadyPurchased(_listing.listingId);
        }
        
        bool isValidSignature = SilksMarketplaceStorage.isValidateSignature(_listing.seller, _message, _signature);
        
        if (!isValidSignature){
            revert InvalidSignature(_signature);
        }
        
        _purchaseListing(_listing, _quantity);
    }
}
