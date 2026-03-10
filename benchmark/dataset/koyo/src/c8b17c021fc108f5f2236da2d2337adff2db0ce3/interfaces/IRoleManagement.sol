// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IRoleManagement
 * @dev Interface for managing roles within the system.
 */
interface IRoleManagement {
    /**
     * @notice Grants a role to a specified account.
     * @param role The role to be granted.
     * @param account The account to grant the role to.
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @notice Revokes a role from a specified account.
     * @param role The role to be revoked.
     * @param account The account to revoke the role from.
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @notice Checks if an account has a specified role.
     * @param role The role to check.
     * @param account The account to check for the role.
     * @return True if the account has the role, false otherwise.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);
}