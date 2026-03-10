// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Import necessary interfaces and contracts
import { ERC165BaseInternal } from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import { IAccessControl } from "@solidstate/contracts/access/access_control/IAccessControl.sol";
import { IDiamondBase } from "@solidstate/contracts/proxy/diamond/base/IDiamondBase.sol";
import { IPartiallyPausable } from "@solidstate/contracts/security/partially_pausable/IPartiallyPausable.sol";
import { IPausable } from "@solidstate/contracts/security/pausable/IPausable.sol";
import { ISolidStateDiamond } from "@solidstate/contracts/proxy/diamond/ISolidStateDiamond.sol";
import { AccessControlInternal } from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";
import { AccessControlStorage } from "@solidstate/contracts/access/access_control/AccessControlStorage.sol";
import { OwnableStorage } from "@solidstate/contracts/access/ownable/OwnableStorage.sol";

import "../SilksMarketplaceStorage.sol";
import "../facets/listing/ListingStorage.sol";
import "../facets/minting/SilksMinterStorage.sol";
import {MINTER_ADMIN_ROLE} from "../utils/constants.sol";

/**
 * @title SilksHorseDiamondInit
 * @dev A Solidity smart contract for initializing supported interfaces in a Diamond upgradeable contract.
 */
contract SilksMarketplaceDiamondInit is
    ERC165BaseInternal,
    AccessControlInternal
{
    /**
     * @dev Initialize supported interfaces within the Diamond contract.
     * @return success A boolean indicating whether the initialization was successful.
     */
    function init(
        ListingType[] memory _listingTypes,
        address _royaltyReceiver,
        uint256 _royaltyBasePoints, // 800 is 8%
        address _avatarAddress,
        address _priceFeedAddress
    )
    external
    returns (
        bool success
    ) {
        // Set support for multiple interfaces within the Diamond contract
        _setSupportsInterface(type(IAccessControl).interfaceId, true);
        _setSupportsInterface(type(IDiamondBase).interfaceId, true);
        _setSupportsInterface(type(IPartiallyPausable).interfaceId, true);
        _setSupportsInterface(type(IPausable).interfaceId, true);
        _setSupportsInterface(type(ISolidStateDiamond).interfaceId, true);
        
        // Defining and granting admin roles for listings and minting
        _setRoleAdmin(LISTING_ADMIN_ROLE, AccessControlStorage.DEFAULT_ADMIN_ROLE);
        OwnableStorage.Layout storage ownableStorageLayout = OwnableStorage.layout();
        _grantRole(LISTING_ADMIN_ROLE, ownableStorageLayout.owner);
        _grantRole(MINTER_ADMIN_ROLE, ownableStorageLayout.owner);
        
        ListingStorage.Layout storage ll = ListingStorage.layout();
        uint256 a = 0;
        for (; a < _listingTypes.length;){
            ll.listingTypes[_listingTypes[a].contractAddress] = _listingTypes[a];
            unchecked { a++; }
        }
        
        SilksMarketplaceStorage.Layout storage lmp = SilksMarketplaceStorage.layout();
        lmp.royaltyReceiver = _royaltyReceiver;
        lmp.royaltyBasePoints = _royaltyBasePoints;

        SilksMinterStorage.Layout storage ls = SilksMinterStorage.layout();
        ls.avatarAddress = _avatarAddress;
        ls.priceFeedAddress = _priceFeedAddress;
    
        return true;
    }
}
