// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@gnus.ai/contracts-upgradeable-diamond/contracts/access/AccessControlStorage.sol";

bytes32 constant LAC_CONTRACT_ADMIN_ROLE = keccak256("CONTRACT_ADMIN_ROLE");
bytes32 constant LAC_CONFIG_ADMIN_ROLE = keccak256("CONFIG_ADMIN_ROLE");
bytes32 constant LAC_FRACTIONALIZATION_ADMIN_ROLE = keccak256("FRACTIONALIZATION_ADMIN_ROLE");
bytes32 constant LAC_RECONSTITUTION_ADMIN_ROLE = keccak256("RECONSTITUTION_ADMIN_ROLE");
bytes32 constant LAC_BURNER_ROLE = keccak256("BURNER_ROLE");

library LibAccessControl {
    
    function grantAllAdminRoles(address account) internal {
        AccessControlStorage.layout()._roles[0x00].members[account] = true; // DEFAULT_ADMIN_ROLE
    }
    
    function revokeAllAdminRoles(address account) internal {
        AccessControlStorage.layout()._roles[0x00].members[account] = false; // DEFAULT_ADMIN_ROLE
    }
    
    function enforceHasContractAdminRole() internal view {
        require(
            AccessControlStorage.layout()._roles[LAC_CONTRACT_ADMIN_ROLE].members[msg.sender] ||
            AccessControlStorage.layout()._roles[AccessControlStorage.layout()._roles[LAC_CONTRACT_ADMIN_ROLE].adminRole].members[msg.sender],
            "UNAUTHORIZED-USER"
        );
    }
    
    function enforceHasConfigurationAdminRole() internal view {
        require(
            AccessControlStorage.layout()._roles[LAC_CONFIG_ADMIN_ROLE].members[msg.sender] ||
            AccessControlStorage.layout()._roles[AccessControlStorage.layout()._roles[LAC_CONFIG_ADMIN_ROLE].adminRole].members[msg.sender],
            "UNAUTHORIZED-USER"
        );
    }
    
    function enforceHasFractionalizationAdminRole() internal view {
        require(
            AccessControlStorage.layout()._roles[LAC_FRACTIONALIZATION_ADMIN_ROLE].members[msg.sender] ||
            AccessControlStorage.layout()._roles[AccessControlStorage.layout()._roles[LAC_FRACTIONALIZATION_ADMIN_ROLE].adminRole].members[msg.sender],
            "UNAUTHORIZED-USER"
        );
    }
    
    function enforceHasReconstitutionAdminRole() internal view {
        require(
            AccessControlStorage.layout()._roles[LAC_RECONSTITUTION_ADMIN_ROLE].members[msg.sender] ||
            AccessControlStorage.layout()._roles[AccessControlStorage.layout()._roles[LAC_RECONSTITUTION_ADMIN_ROLE].adminRole].members[msg.sender],
            "UNAUTHORIZED-USER"
        );
    }
    
    function enforceHasBurnerRole() internal view {
        require(
            AccessControlStorage.layout()._roles[LAC_BURNER_ROLE].members[msg.sender] ||
            AccessControlStorage.layout()._roles[AccessControlStorage.layout()._roles[LAC_BURNER_ROLE].adminRole].members[msg.sender],
            "UNAUTHORIZED-USER"
        );
    }
}