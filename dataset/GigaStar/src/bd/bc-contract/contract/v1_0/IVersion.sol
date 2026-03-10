// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

/// @dev Unified interface for version management
interface IVersion {
    function getVersion() external pure returns (uint);
}
