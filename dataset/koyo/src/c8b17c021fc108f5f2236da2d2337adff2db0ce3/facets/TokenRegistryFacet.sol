// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "../interfaces/IFacetInterface.sol";

/**
 * @title TokenRegistryFacet
 * @dev Facet contract to manage the addition and removal of supported tokens.
 */
contract TokenRegistryFacet {
    bytes32 public constant TOKEN_ADMIN_ROLE = keccak256("TOKEN_ADMIN_ROLE");
    bool initialized;

    /**
     * @dev Ensures that the caller has the specified role.
     * @param role The role required to execute the function.
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
     * @notice Initializes the TokenRegistryFacet contract.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     */
    function initializeTokenRegistry() external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(!initialized, "LendingPoolFacet: Already initialized");
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
     * @return An array of function selectors.
     */
    function facetFunctionSelectors() public pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = this.addToken.selector;
        selectors[1] = this.removeToken.selector;
        selectors[2] = this.initializeTokenRegistry.selector;
        return selectors;
    }

    // --------------------------------------------------------------------------------------------- EXTERNAL ---------------------------------------------------------------------------------------

    /**
     * @notice Adds a token to the registry of supported tokens.
     * @dev Can only be called by accounts with the TOKEN_ADMIN_ROLE.
     * @param token The address of the token to add.
     */
    function addToken(address token) external onlyRole(RoleConstants.TOKEN_ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(token != address(0), "TokenRegistry: token address is zero");
        require(!ds.isTokenSupported[token], "TokenRegistry: token already supported");

        ds.isTokenSupported[token] = true;
        ds.supportedTokens.push(token);
        emit TokenAdded(token);
    }

    /**
     * @notice Removes a token from the registry of supported tokens.
     * @dev Can only be called by accounts with the TOKEN_ADMIN_ROLE.
     * @param token The address of the token to remove.
     */
    function removeToken(address token) external onlyRole(RoleConstants.TOKEN_ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(token != address(0), "TokenRegistry: token address is zero");
        require(ds.isTokenSupported[token], "TokenRegistry: token not supported");

        // Find the index of the token in the supportedTokens array
        uint256 index = findTokenIndex(ds.supportedTokens, token);
        require(index < ds.supportedTokens.length, "TokenRegistry: token not found in supportedTokens array");

        // Remove the token from the supportedTokens array
        if (index < ds.supportedTokens.length - 1) {
            ds.supportedTokens[index] = ds.supportedTokens[ds.supportedTokens.length - 1];
        }
        ds.supportedTokens.pop();

        ds.isTokenSupported[token] = false;
        emit TokenRemoved(token);
    }

    // --------------------------------------------------------------------------------------------- INTERNAL ---------------------------------------------------------------------------------------

    /**
     * @dev Finds the index of a token in the supportedTokens array.
     * @param tokens The array of supported tokens.
     * @param token The token address to find.
     * @return The index of the token in the array.
     */
    function findTokenIndex(address[] storage tokens, address token) internal view returns (uint256) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return i;
            }
        }
        revert("TokenRegistry: token not found in array");
    }

    // --------------------------------------------------------------------------------------------- EVENTS ---------------------------------------------------------------------------------------

    /**
     * @dev Emitted when a new token is added to the registry.
     * @param NewToken The address of the added token.
     */
    event TokenAdded(address indexed NewToken);

    /**
     * @dev Emitted when a token is removed from the registry.
     * @param RemovedToken The address of the removed token.
     */
    event TokenRemoved(address indexed RemovedToken);
}