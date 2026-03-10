// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

abstract contract AccessControl is Context {
    /// @custom:storage-location erc7201:eth.storage.AccessControl
    struct AccessControlStorage {
        mapping(bytes32 => mapping(address => bool)) roles;
    }

    /// @dev the role that can manage the access control
    bytes32 public constant MANAGE_ROLE = keccak256("MANAGE_ROLE");

    /**
     * @dev Role grant event
     * @param role The role being granted
     * @param account The address of the account receiving the role
     * @param operator The address of the operator granting the role
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed operator);

    /**
     * @dev Role revocation event
     * @param role The role being revoked
     * @param account The address of the account whose role is being revoked
     * @param operator The address of the operator revoking the role
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed operator);

    /**
     * @dev Unauthorized account error
     * @param account The address of the account attempting to perform the operation
     * @param neededRole The required role permission
     */
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    /**
     * @dev if the caller is not the owner, it will check if the caller has the specified role
     * @param role The role to check
     */
    modifier onlyRole(bytes32 role) {
        address sender = _msgSender();
        if (!hasRole(role, sender)) {
            revert AccessControlUnauthorizedAccount(sender, role);
        }
        _;
    }

    function _isOwner(address account) internal view virtual returns (bool);

    function _getAccessControlStorage() internal view virtual returns (AccessControlStorage storage);

    /**
     * @dev Checks if an account has a specific role
     * @param role The role identifier
     * @param account The address to check
     * @return Returns true if the account has the role, false otherwise
     */
    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return _isOwner(account) || _getAccessControlStorage().roles[role][account];
    }

    /**
     * @dev Grants a role to an account
     * @param role The role identifier to grant
     * @param account The address of the account receiving the role
     * @notice Only accounts with the admin role can call this function
     */
    function grantRole(bytes32 role, address account) public virtual onlyRole(MANAGE_ROLE) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes a role from an account
     * @param role The role identifier to revoke
     * @param account The address of the account whose role is being revoked
     * @notice Only accounts with the admin role can call this function
     */
    function revokeRole(bytes32 role, address account) public virtual onlyRole(MANAGE_ROLE) {
        _revokeRole(role, account);
    }

    function _grantRole(bytes32 role, address account) internal virtual {
        mapping(address => bool) storage roleMembers = _getAccessControlStorage().roles[role];
        if (roleMembers[account]) {
            return;
        }
        roleMembers[account] = true;
        emit RoleGranted(role, account, _msgSender());
    }

    function _revokeRole(bytes32 role, address account) internal virtual {
        mapping(address => bool) storage roleMembers = _getAccessControlStorage().roles[role];
        if (!roleMembers[account]) {
            return;
        }
        roleMembers[account] = false;
        emit RoleRevoked(role, account, _msgSender());
    }
}
