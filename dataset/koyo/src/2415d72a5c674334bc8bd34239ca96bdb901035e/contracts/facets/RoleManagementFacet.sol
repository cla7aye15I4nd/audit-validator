// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./FacetBase.sol";
import "./ReentrancyGuardBase.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "../interfaces/IRoleManagement.sol";

/**
 * @title RoleManagementFacet
 * @dev Manages roles and permissions within the protocol
 */
contract RoleManagementFacet is FacetBase, ReentrancyGuardBase, IRoleManagement {
    uint256 private constant TIMELOCK_DELAY = 2 days;
    uint256 private constant ROLE_DELAY = 1 days;

    /**
     * @dev Event emitted when a role hierarchy is updated
     */
    event RoleHierarchyUpdated(
        bytes32 indexed role,
        bytes32 indexed adminRole
    );

    /**
     * @dev Struct for pending role actions
     */
    struct PendingRoleAction {
        bool isGrant;
        uint256 effectiveTime;
        bool executed;
    }

    /**
     * @dev Modifier that checks if the caller has the specified role
     */
    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "Must have required role");
        _;
    }

    /**
     * @dev Modifier that ensures the caller is the admin of the specified role
     */
    modifier onlyRoleAdmin(bytes32 role) {
        bytes32 adminRole = getRoleAdmin(role);
        require(hasRole(adminRole, msg.sender), "Must have admin role");
        _;
    }

    /**
     * @dev Initializes the role management system
     */
    function initializeRoleManagement() external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.initialized, "Already initialized");

        // Set up role hierarchy
        _setRoleAdmin(RoleConstants.ADMIN_ROLE, RoleConstants.ADMIN_ROLE);
        _setRoleAdmin(RoleConstants.PRICE_MANAGER, RoleConstants.ADMIN_ROLE);
        _setRoleAdmin(RoleConstants.MARGIN_TRADER_ROLE, RoleConstants.ADMIN_ROLE);
        _setRoleAdmin(RoleConstants.STAKED_TRADER_ROLE, RoleConstants.ADMIN_ROLE);
        _setRoleAdmin(RoleConstants.TOKEN_ADMIN_ROLE, RoleConstants.ADMIN_ROLE);
        _setRoleAdmin(RoleConstants.LIQUIDATOR_ROLE, RoleConstants.ADMIN_ROLE);
        _setRoleAdmin(RoleConstants.OOO_ROUTER_ROLE, RoleConstants.ADMIN_ROLE);
        _setRoleAdmin(RoleConstants.PLATFORM_CONTRACT_ROLE, RoleConstants.ADMIN_ROLE);
        _setRoleAdmin(RoleConstants.PARAMETER_MANAGER_ROLE, RoleConstants.ADMIN_ROLE);

        ds.initialized = true;
    }

    /**
     * @dev Grants a role to an account with delay
     */
    function scheduleRoleGrant(
        bytes32 role,
        address account
    ) public onlyRoleAdmin(role) {
        require(account != address(0), "Invalid account");
        
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        bytes32 actionHash = keccak256(abi.encodePacked(role, account, true));
        
        uint256 effectiveTime = block.timestamp + ROLE_DELAY;
        ds.pendingRoleActions[actionHash] = LibDiamond.PendingRoleAction({
            isGrant: true,
            effectiveTime: effectiveTime,
            executed: false
        });

        emit RoleActionScheduled(role, account, true, effectiveTime);
    }

    /**
     * @dev Revokes a role from an account with delay
     */
    function scheduleRoleRevoke(
        bytes32 role,
        address account
    ) public onlyRoleAdmin(role) {
        require(account != address(0), "Invalid account");
        
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        bytes32 actionHash = keccak256(abi.encodePacked(role, account, false));
        
        uint256 effectiveTime = block.timestamp + ROLE_DELAY;
        ds.pendingRoleActions[actionHash] = LibDiamond.PendingRoleAction({
            isGrant: false,
            effectiveTime: effectiveTime,
            executed: false
        });

        emit RoleActionScheduled(role, account, false, effectiveTime);
    }

    /**
     * @dev Grants a role to an account (legacy support)
     */
    function grantRole(
        bytes32 role,
        address account
    ) external override onlyRoleAdmin(role) {
        scheduleRoleGrant(role, account);
    }

    /**
     * @dev Revokes a role from an account (legacy support)
     */
    function revokeRole(
        bytes32 role,
        address account
    ) external override onlyRoleAdmin(role) {
        scheduleRoleRevoke(role, account);
    }

    /**
     * @dev Executes a pending role grant
     */
    function executeRoleGrant(
        bytes32 role,
        address account
    ) external onlyRoleAdmin(role) {
        bytes32 actionHash = keccak256(abi.encodePacked(role, account, true));
        _executeRoleAction(role, account, actionHash, true);
    }

    /**
     * @dev Executes a pending role revocation
     */
    function executeRoleRevoke(
        bytes32 role,
        address account
    ) external onlyRoleAdmin(role) {
        bytes32 actionHash = keccak256(abi.encodePacked(role, account, false));
        _executeRoleAction(role, account, actionHash, false);
    }

    /**
     * @dev Sets the admin role for a role
     */
    function setRoleAdmin(
        bytes32 role,
        bytes32 adminRole
    ) external onlyRole(RoleConstants.ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }

    /**
     * @dev Checks if an account has a role
     */
    function hasRole(
        bytes32 role,
        address account
    ) public view override returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.roles[role][account];
    }

    /**
     * @dev Gets the admin role for a role
     */
    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.roleAdmins[role];
    }

    /**
     * @dev Gets the member count for a role
     */
    function getRoleMemberCount(bytes32 role) external view returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.roleMemberCount[role];
    }

    /**
     * @dev Returns the function selectors for this facet
     */
    function getRoleFacetSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](11);
        selectors[0] = this.initializeRoleManagement.selector;
        selectors[1] = this.grantRole.selector;
        selectors[2] = this.revokeRole.selector;
        selectors[3] = this.hasRole.selector;
        selectors[4] = this.getRoleAdmin.selector;
        selectors[5] = this.getRoleMemberCount.selector;
        selectors[6] = this.setRoleAdmin.selector;
        selectors[7] = this.executeRoleGrant.selector;
        selectors[8] = this.executeRoleRevoke.selector;
        selectors[9] = this.scheduleRoleGrant.selector;
        selectors[10] = this.scheduleRoleRevoke.selector;
        return selectors;
    }

    /**
     * @dev Internal function to set role admin
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.roleAdmins[role] = adminRole;
        emit RoleHierarchyUpdated(role, adminRole);
    }

    /**
     * @dev Internal function to execute role actions
     */
    function _executeRoleAction(
        bytes32 role,
        address account,
        bytes32 actionHash,
        bool isGrant
    ) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.PendingRoleAction storage action = ds.pendingRoleActions[actionHash];
        
        require(action.effectiveTime != 0, "No pending action");
        require(!action.executed, "Already executed");
        require(block.timestamp >= action.effectiveTime, "Time lock not expired");
        require(action.isGrant == isGrant, "Invalid action type");

        if (isGrant) {
            require(!ds.roles[role][account], "Role already granted");
            ds.roles[role][account] = true;
            ds.roleMemberCount[role] += 1;
            emit RoleGranted(role, account, msg.sender, block.timestamp);
        } else {
            require(ds.roles[role][account], "Role not granted");
            ds.roles[role][account] = false;
            ds.roleMemberCount[role] -= 1;
            emit RoleRevoked(role, account, msg.sender, block.timestamp);
        }

        action.executed = true;
    }
}