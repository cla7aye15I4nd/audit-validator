// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

/// @dev Unifies the interface for all proxy deployer contracts
interface IProxyDeployer {
    event ProxyCreated(address proxy, address logic, string name, bytes data);

    function deployProxy(address logic, string memory name, bytes calldata initData) external returns (address proxy);
}
