// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IDiamondCut
 * @dev Interface for the Diamond Cut, which manages the addition, replacement, and removal of facets.
 */
interface IDiamondCut {
    enum FacetCutAction { Add, Replace, Remove }

    struct FacetCut {
        address target;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    /**
     * @notice Add/replace/remove facets and optionally execute a function.
     * @param _diamondCut Array of FacetCut structs defining the actions.
     * @param _init The address of the contract or facet to execute _calldata.
     * @param _calldata Function call, including function selector and arguments, to execute on _init after facets are cut.
     */
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external;
}