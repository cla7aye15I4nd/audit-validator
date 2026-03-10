// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../MWXT.sol";

/// @custom:oz-upgrades-from contracts/MWXT.sol:MWXT
contract MWXTV2 is MWXT {
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() public reinitializer(2) {
        __EIP712_init("MWXT", "2");
    }
    
    function newFunction() public pure returns (string memory) {
        return "This is a new function in V2";
    }
}