// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "../libraries/LibDiamond.sol";

/**
 * @title ReentrancyGuardBase
 * @dev Contract module that helps prevent reentrant calls to a function.
 * Inheriting from this contract will make the reentrancy modifiers available.
 */
contract ReentrancyGuardBase {
    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.reentrantStatus != LibDiamond._ENTERED, "ReentrancyGuard: reentrant call");

        ds.reentrantStatus = LibDiamond._ENTERED;

        _;

        ds.reentrantStatus = LibDiamond._NOT_ENTERED;
    }

    /**
     * @dev Prevents reentrancy for a specific group of functions
     * @param group The function group identifier
     */
    modifier nonReentrantGroup(bytes32 group) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.groupReentrantStatus[group], "ReentrancyGuard: reentrant call in group");

        ds.groupReentrantStatus[group] = true;

        _;

        ds.groupReentrantStatus[group] = false;
    }

    /**
     * @dev Prevents reentrancy across all facets
     */
    modifier nonReentrantFacets() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.facetReentrantStatus[msg.sig], "ReentrancyGuard: reentrant call across facets");

        ds.facetReentrantStatus[msg.sig] = true;

        _;

        ds.facetReentrantStatus[msg.sig] = false;
    }

    /**
     * @dev Prevents reentrancy during critical operations
     */
    modifier nonReentrantCritical() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.criticalOperationStatus[msg.sender], "ReentrancyGuard: critical operation in progress");

        ds.criticalOperationStatus[msg.sender] = true;

        _;

        ds.criticalOperationStatus[msg.sender] = false;
    }
}