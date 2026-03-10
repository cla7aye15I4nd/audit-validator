// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IFacetInterface
 * @dev Interface for facets to provide their function selectors.
 */
interface IFacetInterface {
    /**
     * @notice Gets the function selectors from a facet.
     * @return An array of function selectors.
     */
    function facetFunctionSelectors() external pure returns (bytes4[] memory);
}