// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { ERC721Base } from "@solidstate/contracts/token/ERC721/base/ERC721Base.sol";
import { ERC1155Base } from "@solidstate/contracts/token/ERC1155/base/ERC1155Base.sol";
import { EnumerableSet } from "@solidstate/contracts/data/EnumerableSet.sol";

import "../../SilksMarketplaceStorage.sol";

// Struct for a marketplace listing type.
    struct ListingType {
        address contractAddress;
        string description;
        uint256 ercStandard;
        bool active;
        bool valid;
    }
    
// Struct for a marketplace listing.
    struct Listing {
        bytes32 listingId;       // Unique identifier for the listing.
        address listingAddress;  // Address for listing's contract.
        address seller;          // Address of the seller.
        address buyer;           // Address of the buyer.
        uint256 tokenId;         // Token ID associated with the listing.
        uint256 numListed;        // Quantity Of token listed
        uint256 pricePer;        // Price per token of the listing.
        uint256 royaltyBasePoints;      // Royalty percentage.
        bool active;             // Status of the listing (active/inactive).
        bool valid;              // Validity of the listing.
    }

bytes32 constant LISTING_ADMIN_ROLE = keccak256("silks.contracts.roles.ListingAdminRole");
bytes32 constant LISTINGS_PAUSED = keccak256('silks.contracts.paused.Listings');
    
    error InvalidListing(bytes32 listingId);
    error ListingAlreadyPurchased(bytes32 listingId);
    error InvalidListingType(address listingAddress);
    error InactiveListingType(address listingAddress);
    error UnsupportedERCStandard(uint256 ercStandard);
    error CreateListingFailed(string reason, bytes32 listingId, address listingAddress, address seller, address buyer, uint256 tokenId, uint256 numListed, uint256 pricePer, uint256 royaltyBasePoints, bool active);

library ListingStorage {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    
    // Storage slot for the layout.
    bytes32 internal constant STORAGE_SLOT = keccak256('silks.contracts.storage.SilksMarketplaceListings');
    
    // Struct for the layout of the marketplace.
    struct Layout {
        mapping(address => ListingType) listingTypes;
        
        mapping(bytes32 => Listing) listings;
        mapping(address => EnumerableSet.Bytes32Set) purchasesByAddress;
        mapping(address => EnumerableSet.UintSet) tokensListedByListingAddress;
        EnumerableSet.Bytes32Set activeListings;
        EnumerableSet.UintSet supportedERCStandards;
    }
    
    // Function to retrieve the layout.
    function layout()
    internal
    pure
    returns (
        Layout storage _l
    ) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            _l.slot := slot
        }
    }
    
    /**
     * @dev Internal function to verify if an asset can be sold.
     * @param _listingAddress Contract address for the listing.
     * @param _addressToCheck The address to check for ownership and approval.
     * @param _tokenId The token ID of the asset.
     */
    function verifyAssetCanBeSold(
        address _listingAddress,
        address _addressToCheck,
        uint256 _tokenId,
        uint256 _quantity
    )
    internal
    view
    {
        // Access marketplace layout
        ListingType storage listingType = layout().listingTypes[_listingAddress];
        
        // Validate listing type and address
        if (!listingType.valid) {
            revert InvalidListingType(_listingAddress);
        }

        // Validate token ownership and approval
        if (listingType.ercStandard == 721){
            ERC721Base assetContract = ERC721Base(listingType.contractAddress);
            if (assetContract.ownerOf(_tokenId) != _addressToCheck) {
                revert NotTokenOwner(_listingAddress, _addressToCheck, _tokenId);
            }
            if (!assetContract.isApprovedForAll(_addressToCheck, address(this))) {
                revert ApprovalNotSetForMarketplace();
            }
        } else if (listingType.ercStandard == 1155){
            ERC1155Base assetContract = ERC1155Base(listingType.contractAddress);
            uint256 numOwned = assetContract.balanceOf(_addressToCheck, _tokenId);
            if (numOwned == 0){
                revert NotTokenOwner(_listingAddress, msg.sender, _tokenId);
            }
            if (_quantity > numOwned){
                revert InvalidIntValue("INV_QTY", _quantity, numOwned);
            }
            if (!assetContract.isApprovedForAll(_addressToCheck, address(this))) {
                revert ApprovalNotSetForMarketplace();
            }
        } else {
            revert("UNSUPPORTED_ERC_STANDARD");
        }
    }
    
    /**
     * @dev Internal function to create a listing.
     * @param _listing The listing structure containing listing details.
     */
    function createListing(
        Listing memory _listing
    )
    internal
    {
        // Verify asset can be sold
        verifyAssetCanBeSold(_listing.listingAddress, _listing.seller, _listing.tokenId, _listing.numListed);
        
        // Validate price is not zero
        if (_listing.pricePer == 0) {
            revert CreateListingFailed("INV_PRICE", _listing.listingId, _listing.listingAddress, _listing.seller, _listing.buyer, _listing.tokenId, _listing.numListed, _listing.pricePer, _listing.royaltyBasePoints, _listing.active);
        }
        
        // Access marketplace layout and check if token is already listed
        ListingType storage listingType = layout().listingTypes[_listing.listingAddress];
        if (!listingType.active){
            revert InactiveListingType(_listing.listingAddress);
        }
        
        EnumerableSet.UintSet storage supportedERCStandards = layout().supportedERCStandards;
        if (!supportedERCStandards.contains(listingType.ercStandard)){
            revert UnsupportedERCStandard(listingType.ercStandard);
        }
    
        EnumerableSet.UintSet storage tokensListedForListingAddress = layout().tokensListedByListingAddress[_listing.listingAddress];
        if (tokensListedForListingAddress.contains(_listing.tokenId)){
            revert CreateListingFailed("TOKEN_ALREADY_LISTED", _listing.listingId, _listing.listingAddress, _listing.seller, _listing.buyer, _listing.tokenId, _listing.numListed, _listing.pricePer, _listing.royaltyBasePoints, _listing.active);
        }
        
        // Add token to the listing and emit event
        tokensListedForListingAddress.add(_listing.tokenId);
        layout().listings[_listing.listingId] = Listing(
            _listing.listingId,
            _listing.listingAddress,
            _listing.seller,
            _listing.buyer,
            _listing.tokenId,
            _listing.numListed,
            _listing.pricePer,
            _listing.royaltyBasePoints,
            _listing.active,
            true
        );
        layout().activeListings.add(_listing.listingId);
    }
    
    function updateListing(
        Listing memory _listing
    )
    internal
    {
        Listing storage storedListing = layout().listings[_listing.listingId];
        
        if (!storedListing.valid){
            revert InvalidListing(_listing.listingId);
        }
    
        layout().listings[_listing.listingId] = _listing;
    }
    
    function transferTokens(
        address _contractAddress,
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _quantity
    )
    internal
    {
        // Transfer the token to the buyer
        ListingType storage listingType = layout().listingTypes[_contractAddress];
        if (listingType.ercStandard == 721){
            ERC721Base assetContract = ERC721Base(listingType.contractAddress);
            assetContract.safeTransferFrom(_from, _to, _tokenId);
        } else if (listingType.ercStandard == 1155){
            ERC1155Base assetContract = ERC1155Base(listingType.contractAddress);
            assetContract.safeTransferFrom(_from, _to, _tokenId, _quantity, "");
        } else {
            revert("UNSUPPORTED_ERC_STANDARD");
        }
    }
}