// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IDiamondLoupe
 * @dev Interface for the Diamond Loupe, which provides introspection on the diamond's facets.
 */
interface IDiamondLoupe {
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    /**
     * @notice Gets all facet addresses and their selectors.
     * @return facets_ An array of Facet structs.
     */
    function facets() external view returns (Facet[] memory facets_);

    /**
     * @notice Gets all the function selectors supported by a specific facet.
     * @param _facet The facet address.
     * @return facetFunctionSelectors_ An array of function selectors.
     */
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory facetFunctionSelectors_);

    /**
     * @notice Gets all the facet addresses used by the diamond.
     * @return facetAddresses_ An array of facet addresses.
     */
    function facetAddresses() external view returns (address[] memory facetAddresses_);

    /**
     * @notice Gets the facet that supports the specified function.
     * @param _functionSelector The function selector.
     * @return facetAddress_ The address of the facet that implements the function.
     */
    function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);
}