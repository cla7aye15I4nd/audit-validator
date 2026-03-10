// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../staking/MWXStaking.sol";

/// @custom:oz-upgrades-from contracts/staking/MWXStaking.sol:MWXStaking
contract MWXStakingV2 is MWXStaking {
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() public reinitializer(2) {
    }
    
    function newFunction() public pure returns (string memory) {
        return "This is a new function in V2";
    }
}