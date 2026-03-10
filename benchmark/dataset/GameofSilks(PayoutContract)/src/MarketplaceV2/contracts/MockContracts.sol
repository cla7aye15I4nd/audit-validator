// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import  {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

import {ERC721PresetMinterPauserAutoId} from "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";

contract MockNFT is ERC721PresetMinterPauserAutoId {
    constructor(string memory name, string memory symbol, string memory baseTokenURI)
        ERC721PresetMinterPauserAutoId(name, symbol, baseTokenURI)
    {
        // You can perform additional setup here if needed
    }

    // Additional functions specific to your mock can be added here
}


contract MarketplaceMock {
    using ECDSA for bytes32;
    using Counters for Counters.Counter;

    // Define a struct for the Listing
    struct Listing {
        address seller;
        uint256 tokenId;
        uint256 price;
        address tokenAddress;
        bytes32 listingId;
    }

    // State variables
    IERC721 public nftContract;
    address public royaltyWallet;
    Counters.Counter private listingCounter; // To keep track of processed listings

    // Events
    event ListingProcessed(address buyer, address seller, uint256 tokenId, uint256 price, bytes32 listingId);

    // Constructor to set the royalty wallet and NFT contract
    constructor(address _royaltyWallet, address _nftContract) {
        royaltyWallet = _royaltyWallet;
        nftContract = IERC721(_nftContract);
    }

    // Function to process a listing
    function purchaseListing(
        Listing memory listing,
        bytes memory signature,
        uint256 royaltyAmount
    ) public payable {
        // Step 3: Recreate signed message and compare it to the signature provided
        bytes32 messageHash = keccak256(abi.encodePacked(
            listing.seller,
            listing.tokenId,
            listing.price,
            listing.tokenAddress,
            listing.listingId
        ));
        require(messageHash.toEthSignedMessageHash().recover(signature) == listing.seller, "Invalid signature");

        // Step 4: Check if the seller still owns the token
        require(nftContract.ownerOf(listing.tokenId) == listing.seller, "Seller no longer owns the token");

        // Step 5: Check if the correct amount of ETH was sent for purchase
        require(msg.value >= listing.price, "Incorrect amount of ETH sent");

        // Step 6: Check that the contract can transfer the NFT on the seller's behalf
        require(nftContract.isApprovedForAll(listing.seller, address(this)), "Marketplace not approved to transfer NFT");

        // Step 7: Check if the listing ID has already been processed
        require(!isListingProcessed(listing.listingId), "Listing already processed");

        // Step 8: Store listing ID in already processed listings array
        listingCounter.increment();
        bytes32 processedListingId = keccak256(abi.encodePacked(listingCounter.current()));

        // Step 9: Calculate and transfer royalty to the royalty wallet
        (bool royaltySent,) = royaltyWallet.call{value: royaltyAmount}("");
        require(royaltySent, "Failed to send royalty");

        // Step 10: Calculate and transfer amount that goes to seller
        uint256 sellerAmount = msg.value - royaltyAmount;
        (bool sellerSent,) = listing.seller.call{value: sellerAmount}("");
        require(sellerSent, "Failed to send seller amount");

        // Step 11: Transfer asset to buyer
        nftContract.transferFrom(listing.seller, msg.sender, listing.tokenId);

        // Emit an event
        emit ListingProcessed(msg.sender, listing.seller, listing.tokenId, listing.price, listing.listingId);
    }

    // Helper function to check if a listing has been processed
    function isListingProcessed(bytes32 listingId) public view returns (bool) {
        // Implement the logic to check if the listing ID has been processed
        // For simulation purposes, we can assume it just returns false
        // In a real scenario, this would check against a mapping or array of processed listing IDs
        return false;
    }
}
