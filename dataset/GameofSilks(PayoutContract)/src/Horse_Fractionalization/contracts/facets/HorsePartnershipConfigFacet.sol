// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

import "@gnus.ai/contracts-upgradeable-diamond/contracts/token/ERC1155/ERC1155Storage.sol";
import "@gnus.ai/contracts-upgradeable-diamond/contracts/proxy/utils/Initializable.sol";
import "@gnus.ai/contracts-upgradeable-diamond/contracts/security/PausableStorage.sol";
import "@gnus.ai/contracts-upgradeable-diamond/contracts/utils/AddressUpgradeable.sol";
import { AccessControlStorage } from "@gnus.ai/contracts-upgradeable-diamond/contracts/access/AccessControlStorage.sol";
import "../libraries/LibHorsePartnership.sol";
import "../libraries/LibAccessControl.sol";
import "../mocks/ContractGlossary.sol";

contract HorsePartnershipConfigFacet is
    Initializable
{
    using AccessControlStorage for AccessControlStorage.Layout;
    using AddressUpgradeable for address;
    
    function __HorsePartnershipConfig_init()
    internal
    onlyInitializing {
        __HorsePartnershipConfig_init_unchained();
    }
    
    function __HorsePartnershipConfig_init_unchained()
    internal
    onlyInitializing {}
    
    function maxPartnershipShares()
    external
    view
    returns (
        uint
    )
    {
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        return hps.maxPartnershipShares;
    }
    
    function setMaxPartnershipShares(
        uint num
    )
    external
    {
        LibAccessControl.enforceHasConfigurationAdminRole();
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        hps.maxPartnershipShares = num;
    }
    
    function setContractGlossary(
        address contractGlossaryAddress
    )
    external
    {
        LibAccessControl.enforceHasConfigurationAdminRole();
        require(
            contractGlossaryAddress.isContract(),
            "INVALID-INDEX-CONTRACT-ADDRESS"
        );
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        hps.indexContract = ContractGlossary(contractGlossaryAddress);
    }
    
    function setURI(
        string memory newUri
    )
    external
    {
        LibAccessControl.enforceHasConfigurationAdminRole();
        ERC1155Storage.layout()._uri = newUri;
    }
    
}