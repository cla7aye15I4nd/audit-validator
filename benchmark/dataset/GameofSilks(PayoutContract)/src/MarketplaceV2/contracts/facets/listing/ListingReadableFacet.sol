// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { AccessControlInternal } from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";
import { EnumerableSet } from "@solidstate/contracts/data/EnumerableSet.sol";
import { PartiallyPausableInternal } from "@solidstate/contracts/security/partially_pausable/PartiallyPausableInternal.sol";

import "./ListingStorage.sol";

/**
 * @dev Contract for reading various aspects of listings in the Silks Marketplace.
 */
contract ListingReadableFacet is
    PartiallyPausableInternal
{
    
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;
    
    function getListing(
        bytes32 _listingId
    )
    public
    view
    returns (
        bytes32 listingId,
        address listingAddress,
        address seller,
        address buyer,
        uint256 tokenId,
        uint256 numListed,
        uint256 pricePer,
        uint256 royaltyBasePoints,
        bool active,
        bool valid
    ) {
        ListingStorage.Layout storage lmp = ListingStorage.layout();
        Listing storage listing = lmp.listings[_listingId];
        return (
            listing.listingId,
            listing.listingAddress,
            listing.seller,
            listing.buyer,
            listing.tokenId,
            listing.numListed,
            listing.pricePer,
            listing.royaltyBasePoints,
            listing.active,
            listing.valid
        );
    }
    
    function getActiveListingIds()
    public
    view
    returns (
        bytes32[] memory
    )
    {
        ListingStorage.Layout storage lmp = ListingStorage.layout();
        return lmp.activeListings.toArray();
    }
    
    function getTokensListedForListing(
        address _listingAddress
    )
    public
    view
    returns (
        uint256[] memory
    ){
        ListingStorage.Layout storage lmp = ListingStorage.layout();
        return lmp.tokensListedByListingAddress[_listingAddress].toArray();
    }
    
    function getPurchasesByAddress(
        address _buyer
    )
    public
    view
    returns (
        bytes32[] memory
    ){
        ListingStorage.Layout storage lmp = ListingStorage.layout();
        return lmp.purchasesByAddress[_buyer].toArray();
    }
    
    function getListingType(
        address _contractAddress
    )
    public
    view
    returns (
        address contractAddress,
        string memory description,
        uint256 ercStandard,
        bool active,
        bool valid
    ) {
        ListingStorage.Layout storage ll = ListingStorage.layout();
        ListingType storage listingType = ll.listingTypes[_contractAddress];
        return (
            listingType.contractAddress,
            listingType.description,
            listingType.ercStandard,
            listingType.active,
            listingType.valid
        );
    }
    
    function getSupportedERCStandards()
    public
    view
    returns(
        uint256[] memory standards
    ) {
        ListingStorage.Layout storage ll = ListingStorage.layout();
        return ll.supportedERCStandards.toArray();
    }
    
    function listingsPaused()
    public
    view
    returns(
        bool
    ){
        return _partiallyPaused(LISTINGS_PAUSED);
    }
}
