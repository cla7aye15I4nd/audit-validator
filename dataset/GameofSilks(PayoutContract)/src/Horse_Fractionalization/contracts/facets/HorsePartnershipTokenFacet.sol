// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

import "@gnus.ai/contracts-upgradeable-diamond/contracts/token/ERC1155/ERC1155Upgradeable.sol";
import "@gnus.ai/contracts-upgradeable-diamond/contracts/token/ERC1155/ERC1155Storage.sol";
import {AccessControlStorage} from "@gnus.ai/contracts-upgradeable-diamond/contracts/access/AccessControlStorage.sol";
import "../libraries/LibHorsePartnership.sol";
import "../libraries/LibAccessControl.sol";
import "../mocks/MarketPlace.sol";
import "../mocks/ContractGlossary.sol";
import "../mocks/ERC721.sol";
import "./DiamondLoupeFacet.sol";

contract HorsePartnershipTokenFacet is
    ERC1155Upgradeable,
    DiamondLoupeFacet
{
    using AccessControlStorage for AccessControlStorage.Layout;
    
    function __HorsePartnershipConfig_init()
    internal
    onlyInitializing
    {
        __HorsePartnershipConfig_init_unchained();
    }
    
    function __HorsePartnershipConfig_init_unchained()
    internal
    onlyInitializing
    {}
    
    function _afterTokenTransfer(
        address,
        address from,
        address to,
        uint[] memory ids,
        uint[] memory amounts,
        bytes memory
    )
    internal
    virtual
    override (
        ERC1155Upgradeable
    )
    {
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        for (uint i = 0; i < ids.length; i++){
            uint id = ids[i];
            address[] memory partnerAddresses = hps.partnerships[id].partners;
            // Don't perform these steps if this is a mint
            if (from != address(0)){
                if (ERC1155Storage.layout()._balances[id][from] <= 0){
                    if (partnerAddresses.length > 0){
                        // Delete partner from partners array if the share balance after transfer is <= 0
                        for(uint j = 0; j < partnerAddresses.length; j++){
                            if (partnerAddresses[j] == from){
                                delete partnerAddresses[j];
                            }
                        }
                    }
                }
                
                address marketPlaceContractAddress = hps.indexContract.getAddress("Marketplace");
                if (marketPlaceContractAddress != msg.sender){
                    MarketPlace marketPlaceContract = MarketPlace(marketPlaceContractAddress);
                    marketPlaceContract.extDeleteMarketItems("HorseFractionalization", from, id, amounts[i]);
                }
            }
            
            // Don't execute when token is being burned
            if (to != address(0)){
                // Don't execute when minting.
                if (from != address(0)){
                    bool addressExists = false;
                    for(uint j = 0; j < partnerAddresses.length; j++){
                        if (partnerAddresses[j] == to){
                            addressExists = true;
                            break;
                        }
                    }
                    
                    address owner = ERC721(hps.indexContract.getAddress("Horse")).ownerOf(id);
                    
                    // Add address to partnership array if address is not already a part of it and the transfer is not
                    // to the owner
                    if (!addressExists){
                        if (to != owner){
                            // Extend the array.
                            address[] memory newPartnerAddresses = new address[](partnerAddresses.length + 1);
                            for (uint j = 0; j < partnerAddresses.length; j++){
                                newPartnerAddresses[j] = partnerAddresses[j];
                            }
                            newPartnerAddresses[partnerAddresses.length] = to;
                            partnerAddresses = newPartnerAddresses;
                        }
                    }
                }
            }
            
            hps.partnerships[id].partners = partnerAddresses;
        }
    }
    
    function fractionalize(
        uint horseId
    )
    external
    {
        LibHorsePartnership.beforeFractionalization(msg.sender, horseId);
        _mint(msg.sender, horseId, LibHorsePartnership.horsePartnershipStorage().maxPartnershipShares, "");
        LibHorsePartnership.afterFractionalization(msg.sender, msg.sender, horseId);
    }
    
    function adminFractionalize(
        address[] memory accounts,
        uint[] memory horseIds
    )
    external
    {
        LibAccessControl.enforceHasFractionalizationAdminRole();
        
        require(
            accounts.length == horseIds.length,
            "ACCOUNTS-IDS-MISMATCH"
        );
        
        for (uint8 i = 0; i < accounts.length; i++){
            LibHorsePartnership.beforeFractionalization(accounts[i], horseIds[i]);
            _mint(accounts[i], horseIds[i], LibHorsePartnership.horsePartnershipStorage().maxPartnershipShares, "");
            LibHorsePartnership.afterFractionalization(msg.sender, accounts[i], horseIds[i]);
        }
    }
    
    function reconstitute(
        uint horseId
    )
    external
    {
        LibHorsePartnership.beforeReconstitution(msg.sender, horseId);
        _burn(msg.sender, horseId, balanceOf(msg.sender, horseId));
        LibHorsePartnership.afterReconstitution(msg.sender, msg.sender, horseId);
    }
    
    function adminReconstitute(
        address[] memory accounts,
        uint[] memory horseIds
    )
    external
    {
        LibAccessControl.enforceHasReconstitutionAdminRole();
        
        require(
            accounts.length == horseIds.length,
            "ACCOUNTS-IDS-MISMATCH"
        );
        for (uint8 i = 0; i < accounts.length; i++){
            LibHorsePartnership.beforeReconstitution(accounts[i], horseIds[i]);
            _burn(accounts[i], horseIds[i], balanceOf(accounts[i], horseIds[i]));
            LibHorsePartnership.afterReconstitution(msg.sender, accounts[i], horseIds[i]);
        }
    }
    
    function burn(
        address account,
        uint256 id,
        uint256 value
    )
    public
    virtual
    {
        LibAccessControl.enforceHasBurnerRole();
        
        require(
            isApprovedForAll(account, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        
        _burn(account, id, value);
    }
    
    function burnBatch(
        address account,
        uint256[] calldata ids,
        uint256[] calldata values
    )
    public
    virtual
    {
        LibAccessControl.enforceHasBurnerRole();
        
        require(
            isApprovedForAll(account, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        
        _burnBatch(account, ids, values);
    }
    
    function supportsInterface(
        bytes4 interfaceId
    )
    public
    view
    override
    (
        ERC1155Upgradeable,
        DiamondLoupeFacet
    )
    returns (
        bool
    ) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.supportedInterfaces[interfaceId];
    }
}