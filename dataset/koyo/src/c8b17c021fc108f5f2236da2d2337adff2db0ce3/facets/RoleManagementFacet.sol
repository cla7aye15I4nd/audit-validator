// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "../interfaces/IFacetInterface.sol";

/**
 * @title RoleManagementFacet
 * @dev Facet contract for managing roles in the system.
 */
contract RoleManagementFacet is IFacetInterface {
    using LibDiamond for LibDiamond.DiamondStorage;

    /**
     * @dev Modifier that checks if the caller has the specified role.
     * @param role The role to check for.
     */
    modifier onlyRole(bytes32 role) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.roles[role][msg.sender], "Must have required role");
        _;
    }

    constructor() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.roles[RoleConstants.ADMIN_ROLE][msg.sender] = true;
    }

    /**
     * @notice Initializes the RoleManagementFacet contract.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     */
    function initializeRoleManagement() external onlyRole(RoleConstants.ADMIN_ROLE) {
        // Initialization logic for RoleManagementFacet (if any)
    }

    // --------------------------------------------------------------------------------------------- PUBLIC ---------------------------------------------------------------------------------------

    /**
     * @notice Gets the function selectors for the facet.
     * @return An array of function selectors.
     */
    function facetFunctionSelectors() public pure override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = this.grantRole.selector;
        selectors[1] = this.revokeRole.selector;
        selectors[2] = this.initializeRoleManagement.selector;
        return selectors;
    }
    
    // --------------------------------------------------------------------------------------------- EXTERNAL ---------------------------------------------------------------------------------------

        /**
     * @notice Grants a role to a specified account.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param account The account to grant the role to.
     */
    function grantRole(address account) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.roles[RoleConstants.ADMIN_ROLE][account] = true;
    }

    /**
     * @notice Revokes a role from a specified account.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param role The role to revoke.
     * @param account The account to revoke the role from.
     */
    function revokeRole(bytes32 role, address account) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.roles[role][account] = false;
    }
}