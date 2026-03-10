// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Importing necessary libraries and contracts
import { AccessControlInternal } from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";
import { AccessControlStorage } from "@solidstate/contracts/access/access_control/AccessControlStorage.sol";
import { PausableInternal } from "@solidstate/contracts/security/pausable/PausableInternal.sol";
import { SolidStateDiamond } from "@solidstate/contracts/proxy/diamond/SolidStateDiamond.sol";

// Import custom library
import "./SilksMarketplaceStorage.sol";
import "./facets/listing/ListingStorage.sol";

contract SilksMarketplaceDiamond is
AccessControlInternal,
PausableInternal,
SolidStateDiamond
{
    using AccessControlStorage for AccessControlStorage.Layout;
    using EnumerableSet for EnumerableSet.UintSet;
    
    constructor(
        address _contractOwner
    )
    SolidStateDiamond()
    {
        // Setting the contract owner and pausing the contract initially
        _setOwner(_contractOwner);
        _pause();
        
        // Granting roles to the contract owner
        _grantRole(AccessControlStorage.DEFAULT_ADMIN_ROLE, _contractOwner);
        
        // Defining and granting admin roles for the contract
        _setRoleAdmin(CONTRACT_ADMIN_ROLE, AccessControlStorage.DEFAULT_ADMIN_ROLE);
        _grantRole(CONTRACT_ADMIN_ROLE, _contractOwner);
        
        ListingStorage.Layout storage ll = ListingStorage.layout();
        ll.supportedERCStandards.add(721);
        ll.supportedERCStandards.add(1155);
    }
}
