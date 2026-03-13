// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../MWXVesting.sol";

/// @custom:oz-upgrades-from contracts/MWXVesting.sol:MWXVesting
contract MWXVestingV2 is MWXVesting {
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() public reinitializer(2) {}
    
    function newFunction() public pure returns (string memory) {
        return "This is a new function in V2";
    }
}