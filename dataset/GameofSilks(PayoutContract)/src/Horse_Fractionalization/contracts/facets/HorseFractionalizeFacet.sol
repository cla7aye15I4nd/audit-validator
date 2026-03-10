// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

import "@gnus.ai/contracts-upgradeable-diamond/contracts/proxy/utils/Initializable.sol";
import { AccessControlStorage } from "@gnus.ai/contracts-upgradeable-diamond/contracts/access/AccessControlStorage.sol";
import { ERC1155Storage } from "@gnus.ai/contracts-upgradeable-diamond/contracts/token/ERC1155/ERC1155Storage.sol";
import "../libraries/LibHorsePartnership.sol";
import "../libraries/LibAccessControl.sol";
import {Partnership} from "../libraries/LibHorsePartnership.sol";
import "../mocks/ERC721.sol";

contract HorseFractionalizeFacet is
    Initializable
{
    using AccessControlStorage for AccessControlStorage.Layout;
    using ERC1155Storage for ERC1155Storage.Layout;
    
    function __FractionalizeHorse_init() internal onlyInitializing {
        __FractionalizeHorse_init_unchained();
    }
    
    function __FractionalizeHorse_init_unchained() internal onlyInitializing {
    }
    
    function isFractionalized(
        uint horseId
    )
    external
    view
    returns (
        bool
    )
    {
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        return hps.partnerships[horseId].isFractionalized;
    }
    
    function partnershipCount()
    external
    view
    returns (
        uint
    ){
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        return hps.partnershipCount;
    }
    
    function getPartnership(
        uint horseId
    )
    external
    view
    returns (
        address[] memory, uint256[] memory
    )
    {
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        Partnership storage partnership = hps.partnerships[horseId];
        require(
            partnership.isFractionalized,
            "HORSE-NOT-FRACTIONALIZED"
        );
        
        address[] storage partners = partnership.partners;
        
        uint256 arrayLength = partners.length + 1;
        address[] memory partnerAddresses = new address[](arrayLength);
        uint256[] memory partnerShares = new uint256[](arrayLength);
        
        address ownerAddress = ERC721(hps.indexContract.getAddress("Horse")).ownerOf(horseId);
        uint pos = 0;
        for (uint256 i = 0; i < partners.length; i++){
            address partner = partners[i];
            if (partner != address(0)){
                partnerAddresses[pos] = partner;
                partnerShares[pos] = ERC1155Storage.layout()._balances[horseId][partner];
                pos++;
            }
        }
        
        uint256 ownerPosition = partnerAddresses.length - 1;
        partnerAddresses[ownerPosition] = ownerAddress;
        partnerShares[ownerPosition] = ERC1155Storage.layout()._balances[horseId][ownerAddress] + 1;
        
        return (partnerAddresses, partnerShares);
    }
 
    function fractionalizationPaused()
    external
    view
    returns (bool)
    {
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        return hps.fractionalizationPaused;
    }
    
    function pauseFractionalization()
    external
    {
        LibAccessControl.enforceHasFractionalizationAdminRole();
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        hps.fractionalizationPaused = true;
    }
    
    function unPauseFractionalization()
    external
    {
        LibAccessControl.enforceHasFractionalizationAdminRole();
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        hps.fractionalizationPaused = false;
    }
}