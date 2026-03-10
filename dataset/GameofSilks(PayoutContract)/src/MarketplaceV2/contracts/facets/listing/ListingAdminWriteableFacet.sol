// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { AccessControl } from "@solidstate/contracts/access/access_control/AccessControl.sol";
import { EnumerableSet } from "@solidstate/contracts/data/EnumerableSet.sol";
import { PartiallyPausableInternal } from "@solidstate/contracts/security/partially_pausable/PartiallyPausableInternal.sol";

import "../../SilksMarketplaceStorage.sol";
import "./ListingStorage.sol";

contract ListingAdminWriteableFacet is
    AccessControl,
    PartiallyPausableInternal
{
    using EnumerableSet for EnumerableSet.UintSet;
    
    // Events for listing creation and purchase.
    event ListingCreatedByAdmin(bytes32 listingId, address listingAddress, address seller, address buyer, uint256 tokenId, uint256 _numListed, uint256 pricePer, uint256 royaltyBasePoints, bool active);
    event ListingUpdatedByAdmin(bytes32 listingId, address listingAddress, address seller, address buyer, uint256 tokenId, uint256 _numListed, uint256 pricePer, uint256 royaltyBasePoints, bool active);
    
    function createListings(
        Listing[] memory _listings
    )
    public
    onlyRole(LISTING_ADMIN_ROLE)
    {
        // Iterate over the array of listings and create each one.
        // NOTE: JSH: I think it's better to do
        // uint256 a; // Defaults to 0 without having to assign it saving gas.
        // uint256 listingsLength = _listings.length; // Then use this in the
        // for loop.
        uint256 a = 0;
        for(; a < _listings.length;){
            // Delegate the creation of each listing to the internal _createListing function.
            ListingStorage.createListing(_listings[a]);
            emit ListingCreatedByAdmin(_listings[a].listingId, _listings[a].listingAddress, _listings[a].seller, _listings[a].buyer, _listings[a].tokenId, _listings[a].numListed, _listings[a].pricePer, _listings[a].royaltyBasePoints, _listings[a].active);
            unchecked { a++; } // Incrementing in an unchecked block to prevent overflow checking, which is unnecessary here.
        }
    }
    
    function updateListings(
        Listing[] memory _listings
    )
    public
    onlyRole(LISTING_ADMIN_ROLE)
    {
        uint a = 0;
        for(; a < _listings.length;){
            ListingStorage.updateListing(_listings[a]);
            emit ListingUpdatedByAdmin(_listings[a].listingId, _listings[a].listingAddress, _listings[a].seller, _listings[a].buyer, _listings[a].tokenId, _listings[a].numListed, _listings[a].pricePer, _listings[a].royaltyBasePoints, _listings[a].active);
            unchecked { a++; }
        }
    }
    
    function pauseListings()
    public
    onlyRole(LISTING_ADMIN_ROLE)
    {
        _partiallyPause(LISTINGS_PAUSED);
    }
    
    function unpauseListings()
    public
    onlyRole(LISTING_ADMIN_ROLE)
    {
        _partiallyUnpause(LISTINGS_PAUSED);
    }
    
    function grantListingAdminRole(
        address _account
    )
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        _grantRole(LISTING_ADMIN_ROLE, _account);
    }
    
    function setListingType(
        ListingType memory _listingType
    )
    public
    onlyRole(LISTING_ADMIN_ROLE)
    {
        ListingStorage.Layout storage ll = ListingStorage.layout();
        ll.listingTypes[_listingType.contractAddress] = _listingType;
    }
    
    function setSupportedERCStandard(
        uint256 _ercStandard,
        bool _state
    )
    public
    onlyRole(LISTING_ADMIN_ROLE)
    {
        EnumerableSet.UintSet storage supportedERCStandards = ListingStorage.layout().supportedERCStandards;
        if (_state){
            if (!supportedERCStandards.contains(_ercStandard)){
                supportedERCStandards.add(_ercStandard);
            }
        } else {
            if (supportedERCStandards.contains(_ercStandard)){
                supportedERCStandards.remove(_ercStandard);
            }
        }
    }
}