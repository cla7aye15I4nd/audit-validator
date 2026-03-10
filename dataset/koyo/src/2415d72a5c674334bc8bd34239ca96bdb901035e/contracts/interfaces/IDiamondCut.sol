// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title IDiamondCut
 * @dev Interface for diamond cut operations in the Diamond pattern
 * @notice Defines the interface for adding, replacing, and removing facets
 */
interface IDiamondCut {
    /**
     * @dev Enum defining the types of facet cut actions
     */
    enum FacetCutAction {
        Add,     // Add functions from a facet
        Replace, // Replace functions from a facet
        Remove   // Remove functions from a facet
    }

    /**
     * @dev Struct defining a facet cut operation
     */
    struct FacetCut {
        address target;              // The facet address
        FacetCutAction action;      // The action to perform
        bytes4[] functionSelectors; // The function selectors to modify
    }

    /**
     * @notice Performs a diamond cut operation
     * @dev Adds, replaces, or removes facet functions
     * @param _diamondCut Array of FacetCut structs containing cut data
     * @param _init Address of contract or facet to execute _calldata
     * @param _calldata Function call data to execute
     */
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external;

    /**
     * @dev Emitted when a diamond cut is executed
     */
    event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);
}