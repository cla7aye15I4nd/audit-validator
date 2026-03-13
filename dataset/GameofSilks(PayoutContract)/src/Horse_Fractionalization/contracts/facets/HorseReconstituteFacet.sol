// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

import "@gnus.ai/contracts-upgradeable-diamond/contracts/proxy/utils/Initializable.sol";
import { AccessControlStorage } from "@gnus.ai/contracts-upgradeable-diamond/contracts/access/AccessControlStorage.sol";
import "../libraries/LibHorsePartnership.sol";
import "../libraries/LibAccessControl.sol";

contract HorseReconstituteFacet is
    Initializable
{
    using AccessControlStorage for AccessControlStorage.Layout;
    
    function __ReconstituteHorse_init()
    internal
    onlyInitializing
    {
        __ReconstituteHorse_init_unchained();
    }
    
    function __ReconstituteHorse_init_unchained()
    internal
    onlyInitializing
    {}
    
    function reconstitutionPaused()
    external
    view
    returns (bool){
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        return hps.reconstitutionPaused;
    }
    
    function pauseReconstitution()
    external
    {
        LibAccessControl.enforceHasReconstitutionAdminRole();
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        hps.reconstitutionPaused = true;
    }
    
    function unPauseReconstitution()
    external
    {
        LibAccessControl.enforceHasReconstitutionAdminRole();
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        hps.reconstitutionPaused = false;
    }
}