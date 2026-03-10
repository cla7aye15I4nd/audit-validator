// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Import necessary contracts and libraries
import { AccessControl } from "@solidstate/contracts/access/access_control/AccessControl.sol";
import { AccessControlStorage } from "@solidstate/contracts/access/access_control/AccessControlStorage.sol";
import { OwnableInternal } from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import { ERC2981Storage } from "@solidstate/contracts/token/common/ERC2981/ERC2981Storage.sol";
import { ERC721BaseInternal } from "@solidstate/contracts/token/ERC721/base/ERC721BaseInternal.sol";
import { ERC721MetadataStorage } from "@solidstate/contracts/token/ERC721/metadata/ERC721MetadataStorage.sol";
import { PartiallyPausableInternal } from "@solidstate/contracts/security/partially_pausable/PartiallyPausableInternal.sol";
import { Pausable } from "@solidstate/contracts/security/pausable/Pausable.sol";
import { AddressUtils } from "@solidstate/contracts/utils/AddressUtils.sol";

import "../libraries/LibSilksHorseDiamond.sol";

/**
 * @title WriteableFacet
 * @dev A Solidity smart contract representing the Writeable Facet of the SilksHorseDiamond contract.
 * This facet provides functions to set roles, season and payout tier information, base URI, horse payout tiers,
 * token reference numbers, pausing, and contract admin/mint admin role members, as well as royalty information.
 */
contract WriteableFacet is
    AccessControl,
    ERC721BaseInternal,
    OwnableInternal,
    Pausable,
    PartiallyPausableInternal
{
    using AddressUtils for address;
    
    /**
     * @dev Set the admin role for a specified role.
     * @param role The role for which to set the admin role.
     * @param adminRole The new admin role to be set.
     */
    function setRoleAdmin(
        bytes32 role,
        bytes32 adminRole
    )
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        _setRoleAdmin(role, adminRole);
    }
    
    /**
     * @dev Set season information.
     * @param _seasonId The ID of the season to set information for.
     * @param _desc The description of the season.
     * @param _paused A boolean indicating whether the season is paused.
     * @param _valid A boolean indicating whether the season is valid.
     */
    function setSeasonInfo(
        uint256 _seasonId,
        string calldata _desc,
        bool _paused,
        bool _valid
    )
    public
    onlyRole(MINT_ADMIN_ROLE)
    {
        LibSilksHorseDiamond.Layout storage lhs = LibSilksHorseDiamond.layout();
        lhs.seasonInfos[_seasonId] = SeasonInfo(
            _seasonId,
            _desc,
            _paused,
            _valid
        );
    }
    
    /**
     * @dev Set payout tier information.
     * @param _payoutTierId The ID of the payout tier to set information for.
     * @param _desc The description of the payout tier.
     * @param _price The price of the payout tier.
     * @param _maxPerTx The maximum quantity allowed per transaction for the payout tier.
     * @param _payoutPct The payout percentage for the payout tier.
     * @param _maxSupply The maximum number of horses for this tier.
     * @param _paused A boolean indicating whether the payout tier is paused.
     * @param _valid A boolean indicating whether the payout tier is valid.
     */
    function setPayoutTier(
        uint256 _payoutTierId,
        string calldata _desc,
        uint256 _price,
        uint256 _maxPerTx,
        uint256 _payoutPct,
        uint256 _maxSupply,
        bool _paused,
        bool _valid
    )
    public
    onlyRole(MINT_ADMIN_ROLE)
    {
        LibSilksHorseDiamond.Layout storage lhs = LibSilksHorseDiamond.layout();
        lhs.payoutTiers[_payoutTierId] = PayoutTier(
            _payoutTierId,
            _desc,
            _price,
            _maxPerTx,
            _payoutPct,
            _maxSupply,
            _paused,
            _valid
        );
    }
    
    /**
     * @dev Set the base URI for metadata of NFTs.
     * @param _baseURI The new base URI to be set.
     */
    function setBaseURI(
        string calldata _baseURI
    )
    public
    onlyRole(MINT_ADMIN_ROLE)
    {
        ERC721MetadataStorage.layout().baseURI = _baseURI;
    }
    
    /**
     * @dev Set the payout tier for a specific horse token.
     * @param _tokenId The ID of the horse token to set the payout tier for.
     * @param _payoutTier The ID of the payout tier to set for the horse token.
     */
    function setHorsePayoutTier(
        uint256 _tokenId,
        uint256 _payoutTier
    )
    public
    onlyRole(MINT_ADMIN_ROLE){
        if (_ownerOf(_tokenId) == address(0)) {
            revert InvalidTokenId(
                _tokenId
            );
        }
        PayoutTier storage pt = LibSilksHorseDiamond.layout().payoutTiers[_payoutTier];
        if (!pt.valid){
            revert InvalidPayoutTier(
                _payoutTier
            );
        }
        LibSilksHorseDiamond.layout().horsePayoutTier[_tokenId]= pt;
    }
    
    /**
     * @dev Set the season for a specific horse token.
     * @param _tokenId The ID of the horse token to set the payout tier for.
     * @param _season The ID of the season info to set for the horse token.
     */
    function setHorseSeason(
        uint256 _tokenId,
        uint256 _season
    )
    public
    onlyRole(MINT_ADMIN_ROLE){
        if (_ownerOf(_tokenId) == address(0)) {
            revert InvalidTokenId(
                _tokenId
            );
        }
        SeasonInfo storage si = LibSilksHorseDiamond.layout().seasonInfos[_season];
        if (!si.valid){
            revert InvalidSeason(
                _season
            );
        }
        LibSilksHorseDiamond.layout().horseSeasonInfo[_tokenId]= si;
    }
    
    /**
    * @dev Sets the maximum number of horses allowed to be owned by a wallet.
    * @param _maxHorsesPerWallet The new maximum number of horses per wallet to be set.
    * Requirements:
    * - Caller must have the MINT_ADMIN_ROLE.
    */
    function setMaxHorsesPerWallet(
        uint256 _maxHorsesPerWallet
    )
    public
    onlyRole(MINT_ADMIN_ROLE)
    {
        // Update the maximum horses per wallet value in the contract's storage.
        LibSilksHorseDiamond.layout().maxHorsesPerWallet = _maxHorsesPerWallet;
    }
    
    /**
     * @dev Pause the contract.
     */
    function pause()
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        _pause();
    }
    
    /**
     * @dev Unpause the contract.
     */
    function unpause()
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        _unpause();
    }
    
    /**
     * @dev Pause horse purchases.
     */
    function pauseHorsePurchases()
    public
    onlyRole(MINT_ADMIN_ROLE)
    {
        _partiallyPause(HORSE_PURCHASING_PAUSED);
    }
    
    /**
     * @dev Unpause horse purchases.
     */
    function unpauseHorsePurchases()
    public
    onlyRole(MINT_ADMIN_ROLE)
    {
        _partiallyUnpause(HORSE_PURCHASING_PAUSED);
    }
    
    /**
    * @dev Allows a contract administrator to enable external address for minting horses.
    * @param _externalAddress The external address to be allowed for external minting.
    */
    function allowExternalMintAddress(
        address _externalAddress
    )
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        // Check if the provided address is a contract
        if (!_externalAddress.isContract()){
            revert AddressUtils.AddressUtils__NotContract();
        }
        
        // Set the external address as allowed for external minting in the contract storage
        LibSilksHorseDiamond.layout().allowedExternalMintAddresses[_externalAddress] = true;
    }
    
    
    /**
     * @dev Set or revoke the CONTRACT_ADMIN_ROLE for a specific address.
     * @param _admin The address to set or revoke the role for.
     * @param _grant A boolean indicating whether to grant or revoke the role.
     */
    function setContractAdminRole(
        address _admin,
        bool _grant
    )
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        if (_admin == address(0)){
            revert InvalidAddress(
                _admin
            );
        }
        
        if (_grant){
            _grantRole(CONTRACT_ADMIN_ROLE, _admin);
        } else {
            _revokeRole(CONTRACT_ADMIN_ROLE, _admin);
        }
    }
    
    /**
     * @dev Set or revoke the MINT_ADMIN_ROLE for a specific address.
     * @param _admin The address to set or revoke the role for.
     * @param _grant A boolean indicating whether to grant or revoke the role.
     */
    function setMintAdminRole(
        address _admin,
        bool _grant
    )
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        if (_admin == address(0)){
            revert InvalidAddress(
                _admin
            );
        }

        if (_grant){
            _grantRole(MINT_ADMIN_ROLE, _admin);
        } else {
            _revokeRole(MINT_ADMIN_ROLE, _admin);
        }
    }
    
    /**
     * @dev Set royalty information.
     * @param _royaltyReceiver The address of the royalty receiver.
     * @param _royaltyBasePoints The royalty base points to be set.
     */
    function setRoyaltyInfo(
        address _royaltyReceiver,
        uint16 _royaltyBasePoints
    )
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        if (_royaltyReceiver == address(0)){
            revert InvalidAddress(
                _royaltyReceiver
            );
        }

        ERC2981Storage.layout().defaultRoyaltyReceiver = _royaltyReceiver;
        ERC2981Storage.layout().defaultRoyaltyBPS = _royaltyBasePoints;
    }
    
    // Basic withdrawal of funds function in order to transfer ETH out of the smart contract
    function withdrawFunds(
        address payable _to
    )
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        if (_to == address(0)){
            revert InvalidAddress(
                _to
            );
        }
        AddressUtils.sendValue(_to, address(this).balance);
    }
}