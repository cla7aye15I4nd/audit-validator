// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './LibraryAC.sol';

/// @dev Decouples role management from a larger featureset
// prettier-ignore
interface IRoleMgr {
    function getRole(address account) external view returns(AC.Role);
}
