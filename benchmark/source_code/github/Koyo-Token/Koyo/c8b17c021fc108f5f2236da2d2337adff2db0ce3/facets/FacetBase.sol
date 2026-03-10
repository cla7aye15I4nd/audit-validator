// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibDiamond.sol";
import "../interfaces/IFacetInterface.sol";

/**
 * @title FacetBase
 * @dev Base contract for facets that provides access to the Diamond storage.
 */
contract FacetBase {
    /**
     * @notice Provides access to the diamond storage instance.
     * @return ds The diamond storage instance.
     */
    function diamondStorage() internal pure virtual returns (LibDiamond.DiamondStorage storage ds) {
        ds = LibDiamond.diamondStorage();
    }
}