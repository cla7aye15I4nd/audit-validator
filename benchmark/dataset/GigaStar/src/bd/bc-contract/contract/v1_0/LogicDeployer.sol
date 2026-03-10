// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

/// @dev Allows a minimal contract to create a new logic contract. This isolates both bytecode size and gas during
/// deploy. The result is likely passed to `ProxyDeployer.deployProxy`. An example LogicDeployer contract:
///
///     contract BoxLogicDeployer is LogicDeployer {
///         constructor() { _logic = new Box(); } // This line incurs the gas to deploy the entire contract
///     }
///
/// Resulting deployer should be minimal ~0.126 K
/// Estimated gas for the constructor is based on a 36K base cost + 200 gas/byte (based on size of `Box` above)
/// For a full contract (~24K) the gas approaches 5M
/// @custom:api private
/// @custom:deploy none
// prettier-ignore
abstract contract LogicDeployer {
    // slither-disable-next-line uninitialized-state (initialized in derived contract)
    address internal immutable _logic;

    event LogicDeployed(address logic);

    /// @custom:api public
    function deployLogic() external view returns (address) {
        // slither-disable-next-line uninitialized-local (Derived contract will set this in the cstr)
        return _logic;
    }
}
