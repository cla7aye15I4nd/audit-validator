// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../MWXLaunchpad.sol";

/// @custom:oz-upgrades-from contracts/MWXLaunchpad.sol:MWXLaunchpad
contract MWXLaunchpadV2 is MWXLaunchpad {
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() public reinitializer(2) {
        __EIP712_init("MWXLaunchpad", "2");
    }
    
    function newFunction() public pure returns (string memory) {
        return "This is a new function in V2";
    }
}