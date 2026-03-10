// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title IRoleManagement
 * @dev Interface for managing roles and permissions
 * @notice Defines the interface for role-based access control with proper timelocks
 */
interface IRoleManagement {
    /**
     * @dev Emitted when a role is granted
     */
    event RoleGranted(
        bytes32 indexed role,
        address indexed account,
        address indexed sender,
        uint256 effectiveTime
    );

    /**
     * @dev Emitted when a role is revoked
     */
    event RoleRevoked(
        bytes32 indexed role,
        address indexed account,
        address indexed sender,
        uint256 effectiveTime
    );

    /**
     * @dev Emitted when a role action is scheduled
     */
    event RoleActionScheduled(
        bytes32 indexed role,
        address indexed account,
        bool isGrant,
        uint256 effectiveTime
    );

    /**
     * @notice Grants a role to an account with timelock
     * @param role The role to grant
     * @param account The account to receive the role
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @notice Revokes a role from an account with timelock
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @notice Checks if an account has a role
     * @param role The role to check
     * @param account The account to check
     * @return Whether the account has the role
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @notice Gets the admin role for a role
     * @param role The role to check
     * @return The admin role
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @notice Gets the member count for a role
     * @param role The role to check
     * @return The number of members with the role
     */
    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    /**
     * @notice Schedules a role grant
     * @param role The role to grant
     * @param account The account to receive the role
     */
    function scheduleRoleGrant(bytes32 role, address account) external;

    /**
     * @notice Schedules a role revocation
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    function scheduleRoleRevoke(bytes32 role, address account) external;

    /**
     * @notice Executes a scheduled role grant
     * @param role The role to grant
     * @param account The account to receive the role
     */
    function executeRoleGrant(bytes32 role, address account) external;

    /**
     * @notice Executes a scheduled role revocation
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    function executeRoleRevoke(bytes32 role, address account) external;
}