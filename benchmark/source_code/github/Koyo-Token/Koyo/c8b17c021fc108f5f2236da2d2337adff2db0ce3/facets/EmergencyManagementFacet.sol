// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./LendingPoolFacet.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/IFacetInterface.sol";
import "../libraries/RoleConstants.sol";

/**
 * @title EmergencyManagementFacet
 * @dev Facet contract for managing emergency operations within the diamond, such as pausing the platform and emergency withdrawals.
 */
contract EmergencyManagementFacet is IFacetInterface {
    LendingPoolFacet private lendingPool;

    // State variable to check if the contract has been initialized
    bool internal initialized = false;

    /**
     * @dev Modifier that checks if the caller has the specified role.
     * @param role The role required to execute the function.
     */
    modifier onlyRole(bytes32 role) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.roles[role][msg.sender], "Must have required role");
        _;
    }

    /**
     * @dev Modifier that ensures the platform is paused.
     */
    modifier whenPaused() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.paused, "Platform is not paused");
        _;
    }

    constructor() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.roles[RoleConstants.ADMIN_ROLE][msg.sender] = true;
    }

    /**
     * @notice Initializes the EmergencyManagementFacet contract.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param _lendingPool The address of the lending pool contract.
     */
    function initializeEmergencyManagement(address _lendingPool) external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(!initialized, "EmergencyManagementFacet: Already initialized");

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.facet.selectorCount = 0; // Initialize selectorCount to 0

        lendingPool = LendingPoolFacet(_lendingPool);
        initialized = true;
    }

        /**
     * @notice Grants a role to a specified account.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param account The account to grant the role to.
     */
    function grantRole(address account) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.roles[RoleConstants.ADMIN_ROLE][account] = true;
    }

    // --------------------------------------------------------------------------------------------- PUBLIC ---------------------------------------------------------------------------------------

    /**
     * @notice Gets the function selectors for the facet.
     * @return selectors An array of function selectors.
     */
    function facetFunctionSelectors() public pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = this.pausePlatform.selector;
        selectors[1] = this.unpausePlatform.selector;
        selectors[2] = this.emergencyWithdraw.selector;
        selectors[3] = this.initializeEmergencyManagement.selector;
        return selectors;
    }

    // --------------------------------------------------------------------------------------------- EXTERNAL ---------------------------------------------------------------------------------------

    /**
     * @notice Pauses the platform, preventing certain actions.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     */
    function pausePlatform() external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.diamondStorage().paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpauses the platform, allowing normal operations.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     */
    function unpausePlatform() external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.diamondStorage().paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Performs an emergency withdrawal of a user's funds from the lending pool.
     * @dev Can only be called by accounts with the ADMIN_ROLE and when the platform is paused.
     * @param token The address of the token to withdraw.
     * @param user The address of the user whose funds are being withdrawn.
     */
    function emergencyWithdraw(address token, address user) external whenPaused onlyRole(RoleConstants.ADMIN_ROLE) {
        require(token != address(0), "Invalid token address");
        require(user != address(0), "Invalid user address");

        (uint256 depositBalance, ) = lendingPool.getUserBalance(token, user);
        require(depositBalance > 0, "No funds to withdraw");

        try lendingPool.withdrawFromLendingPool(token, depositBalance) {
            // Withdrawal successful
        } catch {
            revert("Failed to withdraw funds");
        }

        emit EmergencyWithdrawal(user, token, depositBalance);
    }

    // --------------------------------------------------------------------------------------------- EVENTS ---------------------------------------------------------------------------------------

    /**
     * @dev Emitted when the platform is paused.
     * @param account The address of the account that triggered the pause.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the platform is unpaused.
     * @param account The address of the account that triggered the unpause.
     */
    event Unpaused(address account);

    /**
     * @dev Emitted when an emergency withdrawal is performed.
     * @param account The address of the user whose funds were withdrawn.
     * @param token The address of the token that was withdrawn.
     * @param amount The amount of tokens withdrawn.
     */
    event EmergencyWithdrawal(address indexed account, address indexed token, uint256 indexed amount);
}