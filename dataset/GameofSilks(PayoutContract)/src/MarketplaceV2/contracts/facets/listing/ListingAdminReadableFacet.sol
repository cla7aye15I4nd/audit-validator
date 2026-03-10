// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { AccessControlInternal } from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";

import "./ListingStorage.sol";

contract ListingAdminReadableFacet is
    AccessControlInternal
{
    function hasListingAdminRole(
        address _account
    )
    public
    view
    returns(
        bool
    )
    {
        return _hasRole(LISTING_ADMIN_ROLE, _account);
    }
}