// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title RoleConstants
 * @dev Library containing role definitions for the protocol
 * @notice Defines all roles and their hierarchical relationships
 */
library RoleConstants {
    /**
     * @dev Admin role with highest privileges
     * @notice Can manage all other roles and system parameters
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /**
     * @dev Platform contract role for internal contract calls
     * @notice Used for authenticated inter-contract communication
     */
    bytes32 public constant PLATFORM_CONTRACT_ROLE = keccak256("PLATFORM_CONTRACT_ROLE");

    /**
     * @dev Parameter manager role
     * @notice Can update system parameters within defined limits
     */
    bytes32 public constant PARAMETER_MANAGER_ROLE = keccak256("PARAMETER_MANAGER_ROLE");

    /**
     * @dev Margin trader role
     * @notice Can perform margin trading operations
     */
    bytes32 public constant MARGIN_TRADER_ROLE = keccak256("MARGIN_TRADER_ROLE");

    /**
     * @dev Staked trader role
     * @notice Can perform trading operations with staked collateral
     */
    bytes32 public constant STAKED_TRADER_ROLE = keccak256("STAKED_TRADER_ROLE");

    /**
     * @dev Token admin role
     * @notice Can manage supported tokens and their parameters
     */
    bytes32 public constant TOKEN_ADMIN_ROLE = keccak256("TOKEN_ADMIN_ROLE");

    /**
     * @dev Liquidator role
     * @notice Can perform liquidations on undercollateralized positions
     */
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    /**
     * @dev Oracle router role
     * @notice Can update price data from oracle sources
     */
    bytes32 public constant OOO_ROUTER_ROLE = keccak256("OOO_ROUTER_ROLE");

    /**
     * @dev Price manager role
     * @notice Can manage price feeds and oracle configurations
     */
    bytes32 public constant PRICE_MANAGER = keccak256("PRICE_MANAGER");

    /**
     * @dev Emergency admin role
     * @notice Can trigger emergency procedures and circuit breakers
     */
    bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");

    /**
     * @dev Fee manager role
     * @notice Can manage fee parameters and distributions
     */
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    /**
     * @dev Governance role
     * @notice Can participate in protocol governance
     */
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    /**
     * @dev Pause operator role
     * @notice Can pause specific protocol functions
     */
    bytes32 public constant PAUSE_OPERATOR_ROLE = keccak256("PAUSE_OPERATOR_ROLE");

    /**
     * @dev Risk manager role
     * @notice Can adjust risk parameters within defined limits
     */
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");

    /**
     * @dev Returns the admin role for a given role
     * @param role The role to get the admin for
     * @return The admin role
     */
    function getAdminRole(bytes32 role) internal pure returns (bytes32) {
        if (role == ADMIN_ROLE) {
            return ADMIN_ROLE;
        }
        return ADMIN_ROLE;
    }

    /**
     * @dev Checks if a role is a system role
     * @param role The role to check
     * @return Whether the role is a system role
     */
    function isSystemRole(bytes32 role) internal pure returns (bool) {
        return role == PLATFORM_CONTRACT_ROLE ||
               role == ADMIN_ROLE ||
               role == EMERGENCY_ADMIN_ROLE;
    }

    /**
     * @dev Checks if a role can be granted by a specific admin role
     * @param role The role to check
     * @param adminRole The admin role
     * @return Whether the admin role can grant the role
     */
    function canGrantRole(bytes32 role, bytes32 adminRole) internal pure returns (bool) {
        if (adminRole == ADMIN_ROLE) {
            return true;
        }
        if (role == ADMIN_ROLE) {
            return false;
        }
        if (role == EMERGENCY_ADMIN_ROLE && adminRole != ADMIN_ROLE) {
            return false;
        }
        return getAdminRole(role) == adminRole;
    }

    /**
     * @dev Gets the role hierarchy level
     * @param role The role to check
     * @return The hierarchy level (0 is highest)
     */
    function getRoleHierarchyLevel(bytes32 role) internal pure returns (uint256) {
        if (role == ADMIN_ROLE) {
            return 0;
        }
        if (role == EMERGENCY_ADMIN_ROLE || role == GOVERNANCE_ROLE) {
            return 1;
        }
        if (role == RISK_MANAGER_ROLE || role == FEE_MANAGER_ROLE) {
            return 2;
        }
        return 3;
    }

    /**
     * @dev Checks if a role requires timelock
     * @param role The role to check
     * @return Whether the role requires timelock
     */
    function requiresTimelock(bytes32 role) internal pure returns (bool) {
        return role == ADMIN_ROLE ||
               role == EMERGENCY_ADMIN_ROLE ||
               role == GOVERNANCE_ROLE ||
               role == RISK_MANAGER_ROLE ||
               role == FEE_MANAGER_ROLE;
    }

    /**
     * @dev Gets the timelock delay for a role
     * @param role The role to check
     * @return The timelock delay in seconds
     */
    function getTimelockDelay(bytes32 role) internal pure returns (uint256) {
        if (role == ADMIN_ROLE) {
            return 2 days;
        }
        if (role == EMERGENCY_ADMIN_ROLE) {
            return 1 days;
        }
        if (role == GOVERNANCE_ROLE) {
            return 3 days;
        }
        return 1 days;
    }
}