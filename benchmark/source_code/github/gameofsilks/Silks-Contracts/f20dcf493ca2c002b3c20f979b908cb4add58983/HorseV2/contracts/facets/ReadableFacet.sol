// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Import necessary contract and library
import { AccessControlInternal } from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";
import { ERC721MetadataStorage } from "@solidstate/contracts/token/ERC721/metadata/ERC721MetadataStorage.sol";
import { PartiallyPausableInternal } from "@solidstate/contracts/security/partially_pausable/PartiallyPausableInternal.sol";
import "../libraries/LibSilksHorseDiamond.sol";

/**
 * @title ReadableFacet
 * @dev A Solidity smart contract representing the Readable Facet of the SilksHorseDiamond contract.
 * This facet provides read-only functions to query information about seasons, payout tiers, horses, and pausing status.
 */
contract ReadableFacet is
    AccessControlInternal,
    PartiallyPausableInternal
{
    /**
     * @dev Get information about a specific season.
     * @param _seasonId The ID of the season to query.
     * @return seasonId The ID of the season.
     * @return description The description of the season.
     * @return paused A boolean indicating whether the season is paused.
     * @return valid A boolean indicating whether the season is valid.
     */
    function seasonInfo(
        uint256 _seasonId
    )
    public
    view
    returns (
        uint256 seasonId,
        string memory description,
        bool paused,
        bool valid
    ){
        SeasonInfo storage ci = LibSilksHorseDiamond.layout().seasonInfos[_seasonId];
        return (
        ci.seasonId,
        ci.description,
        ci.paused,
        ci.valid
        );
    }
    
    /**
    * @dev Get information about the season associated with a specific horse token.
    * @param _tokenId The ID of the horse token to query.
    * @return tokenId The ID of the horse token.
    * @return seasonId The ID of the associated season.
    * @return description The description of the associated season.
    * @return paused A boolean indicating whether the associated season is paused.
    * @return valid A boolean indicating whether the associated season is valid.
    */
    function horseSeasonInfo(
        uint256 _tokenId
    )
    public
    view
    returns (
        uint256 tokenId,
        uint256 seasonId,
        string memory description,
        bool paused,
        bool valid
    ){
        // Retrieve season information associated with the provided horse token ID
        SeasonInfo storage ci = LibSilksHorseDiamond.layout().horseSeasonInfo[_tokenId];
        
        // Return the requested information as a tuple
        return (
            _tokenId,
            ci.seasonId,
            ci.description,
            ci.paused,
            ci.valid
        );
    }
    
    /**
     * @dev Get information about a specific payout tier.
     * @param _payoutTier The ID of the payout tier to query.
     * @return tierId The ID of the payout tier.
     * @return description The description of the payout tier.
     * @return price The price of the payout tier.
     * @return maxPerTx The maximum quantity allowed per transaction for the payout tier.
     * @return payoutPct The payout percentage for the payout tier.
     * @return maxSupply The maximum number of horse for this tier.
     * @return paused A boolean indicating whether the payout tier is paused.
     * @return valid A boolean indicating whether the payout tier is valid.
     */
    function payoutTier(
        uint256 _payoutTier
    )
    public
    view
    returns (
        uint256 tierId,
        string memory description,
        uint256 price,
        uint256 maxPerTx,
        uint256 payoutPct,
        uint256 maxSupply,
        bool paused,
        bool valid
    ){
        PayoutTier storage pt = LibSilksHorseDiamond.layout().payoutTiers[_payoutTier];
        return (
        pt.tierId,
        pt.description,
        pt.price,
        pt.maxPerTx,
        pt.payoutPct,
        pt.maxSupply,
        pt.paused,
        pt.valid
        );
    }
    
    /**
     * @dev Get information about the payout tier associated with a specific horse token.
     * @param _tokenId The ID of the horse token to query.
     * @return tokenId The ID of the horse token.
     * @return tierId The ID of the associated payout tier.
     * @return description The description of the payout tier.
     * @return price The price of the payout tier.
     * @return maxPerTx The maximum quantity allowed per transaction for the payout tier.
     * @return payoutPct The payout percentage for the payout tier.
     * @return maxSupply The maximum number of horse for this tier.
     * @return paused A boolean indicating whether the payout tier is paused.
     * @return valid A boolean indicating whether the payout tier is valid.
     */
    function horsePayoutTier(
        uint256 _tokenId
    )
    public
    view
    returns (
        uint256 tokenId,
        uint256 tierId,
        string memory description,
        uint256 price,
        uint256 maxPerTx,
        uint256 payoutPct,
        uint256 maxSupply,
        bool paused,
        bool valid
    ){
        PayoutTier storage pt = LibSilksHorseDiamond.layout().horsePayoutTier[_tokenId];
        return (
        _tokenId,
        pt.tierId,
        pt.description,
        pt.price,
        pt.maxPerTx,
        pt.payoutPct,
        pt.maxSupply,
        pt.paused,
        pt.valid
        );
    }
    
    /**
    * @dev Get the base URI for metadata of NFTs.
    * @return uri The base URI used for constructing the metadata URI of NFTs.
    */
    function baseURI()
    public
    view
    returns (
        string memory uri
    )
    {
        return ERC721MetadataStorage.layout().baseURI;
    }
    
    /**
    * @dev Get the maximum number of horses allowed per wallet.
    * @return maxHorsesPerWallet The maximum number of horses allowed per wallet.
    */
    function maxHorsesPerWallet()
    public
    view
    returns (
        uint256 maxHorsesPerWallet
    )
    {
        // Retrieve the maximum number of horses per wallet from the contract's storage
        return LibSilksHorseDiamond.layout().maxHorsesPerWallet;
    }
    
    /**
     * @dev Check if horse purchases are paused.
     * @return paused A boolean indicating whether horse purchases are paused.
     */
    function horsePurchasesPaused()
    public
    view
    returns (
        bool paused
    ){
        return _partiallyPaused(HORSE_PURCHASING_PAUSED);
    }

    /**
    * @dev Checks if an external address is allowed to perform external minting of horses.
    * @param _externalAddress The external address to check.
    * @return allowed A boolean indicating whether the address is allowed for external minting.
    */
    function isAllowedExternalMintAddress(
        address _externalAddress
    ) public
    view
    returns (
        bool allowed
    )
    {
        // Retrieve the allowed status of the external address from the contract storage
        return LibSilksHorseDiamond.layout().allowedExternalMintAddresses[_externalAddress];
    }
    
    /**
     * @dev Check if an address has the CONTRACT_ADMIN_ROLE.
     * @param _admin The address to check for the CONTRACT_ADMIN_ROLE.
     * @return hasRole A boolean indicating whether the address has the CONTRACT_ADMIN_ROLE.
     */
    function hasContractAdminRole(
        address _admin
    )
    public
    view
    returns (
        bool hasRole
    )
    {
        return _hasRole(CONTRACT_ADMIN_ROLE, _admin);
    }
    
    /**
     * @dev Check if an address has the MINT_ADMIN_ROLE.
     * @param _admin The address to check for the MINT_ADMIN_ROLE.
     * @return hasRole A boolean indicating whether the address has the MINT_ADMIN_ROLE.
     */
    function hasMintAdminRole(
        address _admin
    )
    public
    view
    returns (
        bool hasRole
    )
    {
        return _hasRole(MINT_ADMIN_ROLE, _admin);
    }
    
    /**
     * @dev Get the next available token ID for minting horses.
     * @return nextAvailableTokenId The next available token ID.
     */
    function nextAvailableTokenId()
    public
    view
    returns (
        uint256 nextAvailableTokenId
    )
    {
        // Retrieve the next available token ID from the contract's storage.
        return LibSilksHorseDiamond.layout().nextAvailableTokenId;
    }
}
