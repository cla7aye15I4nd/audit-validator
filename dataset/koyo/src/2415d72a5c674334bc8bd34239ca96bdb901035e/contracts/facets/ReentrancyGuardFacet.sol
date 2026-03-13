// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./FacetBase.sol";
import "../libraries/LibDiamond.sol";

/**
 * @title ReentrancyGuardFacet
 * @dev Facet for querying reentrancy guard status
 */
contract ReentrancyGuardFacet is FacetBase {
    /**
     * @dev Checks if a function group is currently locked
     * @param group The function group identifier
     * @return bool Whether the group is locked
     */
    function isGroupLocked(bytes32 group) external view returns (bool) {
        return LibDiamond.diamondStorage().groupReentrantStatus[group];
    }

    /**
     * @dev Checks if a facet function is currently locked
     * @param selector The function selector
     * @return bool Whether the function is locked
     */
    function isFacetLocked(bytes4 selector) external view returns (bool) {
        return LibDiamond.diamondStorage().facetReentrantStatus[selector];
    }

    /**
     * @dev Checks if a critical operation is in progress
     * @param operator The address performing the critical operation
     * @return bool Whether a critical operation is in progress
     */
    function isCriticalOperationInProgress(address operator) external view returns (bool) {
        return LibDiamond.diamondStorage().criticalOperationStatus[operator];
    }

    /**
     * @dev Gets the current reentrancy status
     * @return uint256 The current reentrancy status
     */
    function getReentrancyStatus() external view returns (uint256) {
        return LibDiamond.diamondStorage().reentrantStatus;
    }

    /**
     * @dev Returns the function selectors for this facet
     * @return selectors Array of function selectors
     */
    function getReentrancyGuardFacetSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = this.isGroupLocked.selector;
        selectors[1] = this.isFacetLocked.selector;
        selectors[2] = this.isCriticalOperationInProgress.selector;
        selectors[3] = this.getReentrancyStatus.selector;
        return selectors;
    }
}