// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

import "@gnus.ai/contracts-upgradeable-diamond/contracts/access/AccessControlEnumerableUpgradeable.sol";
import { LibDiamond } from  "../libraries/LibDiamond.sol";
import "../libraries/LibAccessControl.sol";

contract HorsePartnershipAccessControlFacet is
    AccessControlEnumerableUpgradeable
{
    bytes32 public constant CONTRACT_ADMIN_ROLE = LAC_CONTRACT_ADMIN_ROLE;
    bytes32 public constant CONFIG_ADMIN_ROLE = LAC_CONFIG_ADMIN_ROLE;
    bytes32 public constant FRACTIONALIZATION_ADMIN_ROLE = LAC_FRACTIONALIZATION_ADMIN_ROLE;
    bytes32 public constant RECONSTITUTION_ADMIN_ROLE = LAC_RECONSTITUTION_ADMIN_ROLE;
    bytes32 public constant BURNER_ROLE = LAC_BURNER_ROLE;
    
    function __HorsePartnershipsAccessControl_init()
    internal
    onlyInitializing {
        __HorsePartnershipsAccessControl_init_unchained();
    }
    
    function __HorsePartnershipsAccessControl_init_unchained()
    internal
    onlyInitializing {}
    
    function supportsInterface(
        bytes4 interfaceId
    )
    public
    view
    override
    (
        AccessControlEnumerableUpgradeable
    )
    returns (
        bool
    ) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.supportedInterfaces[interfaceId];
    }
    
}