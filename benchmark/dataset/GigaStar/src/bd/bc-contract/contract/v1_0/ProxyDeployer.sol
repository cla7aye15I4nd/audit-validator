// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

import './IProxyDeployer.sol';

/// @dev A generic proxy deployer to insulate a contract from the ERC1967Proxy contract size ~1.3K
/// - ERC1967Proxy interacts with:
///     - Proxy contract: Fixed address with state/storage. Calls are delgated to the logic contract.
///     - Logic contract: Contains functions and storage layout definition, may be upgraded (aka Impl contract)
/// - The logic contract `initializer` sees `msg.sender`
/// - See `ILogicDeployer` for creating the logic contract
/// - By doing `ILogicDeployer.deployLogic` and `ProxyDeployer.deployProxy` in separate transactions, gas overhead is
///   minimized and bytecode size are maximized for a deployer contract that uses multiple contracts as the results of
///   both can be passed to the deployer.
/// @custom:api public
/// @custom:deploy none
contract ProxyDeployer is IProxyDeployer {
    /// @param logic The logic contract
    /// @param name The name of the contract for the event, only used for logging
    /// @param initData Bytes used to initialize the instance, typically something like this:
    ///     `abi.encodeWithSelector(IFoo.initialize.selector, arg1, arg2)`
    /// Where `Foo` has an initialize function receiving arg1 and arg2
    /// @custom:api public
    function deployProxy(address logic, string memory name, bytes calldata initData) external returns (address proxy) {
        proxy = address(new ERC1967Proxy(logic, initData));
        emit ProxyCreated(proxy, logic, name, initData);
    }
}
