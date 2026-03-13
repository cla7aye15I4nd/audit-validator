// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title IDiamondLoupe
 * @dev Interface for diamond loupe functions
 * @notice Provides introspection functions for the Diamond pattern
 */
interface IDiamondLoupe {
    /**
     * @dev Struct containing facet information
     */
    struct Facet {
        address facetAddress;          // The facet contract address
        bytes4[] functionSelectors;    // Array of function selectors supported by the facet
    }

    /**
     * @notice Gets all facets and their selectors
     * @return facets_ Array of Facet structs containing facet information
     */
    function facets() external view returns (Facet[] memory facets_);

    /**
     * @notice Gets all function selectors supported by a specific facet
     * @param _facet The facet address
     * @return facetFunctionSelectors_ Array of function selectors
     */
    function facetFunctionSelectors(address _facet)
        external
        view
        returns (bytes4[] memory facetFunctionSelectors_);

    /**
     * @notice Gets all facet addresses used by the diamond
     * @return facetAddresses_ Array of facet addresses
     */
    function facetAddresses()
        external
        view
        returns (address[] memory facetAddresses_);

    /**
     * @notice Gets the facet address that supports a specific function
     * @param _functionSelector The function selector
     * @return facetAddress_ The facet address
     */
    function facetAddress(bytes4 _functionSelector)
        external
        view
        returns (address facetAddress_);
}