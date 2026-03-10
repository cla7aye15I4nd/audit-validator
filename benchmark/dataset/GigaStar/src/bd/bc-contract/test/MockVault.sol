// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import '../contract/v1_0/IRoleMgr.sol';
import '../contract/v1_0/IVersion.sol';
import '../contract/v1_0/LibraryAC.sol';

contract MockVault is IRoleMgr, IVersion {
    mapping(address => AC.Role) mockedRoles;

    function addMockRole(address a, AC.Role role) external {
        mockedRoles[a] = role;
    }

    function removeMockRole(address a) external {
        delete mockedRoles[a];
    }

    function getRole(address account) external view override returns(AC.Role) {
        return mockedRoles[account];
    }

    function getVersion() external pure override returns (uint) {
        return 1;
    }
}
