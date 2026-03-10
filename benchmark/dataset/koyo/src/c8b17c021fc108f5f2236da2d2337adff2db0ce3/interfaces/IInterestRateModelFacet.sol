// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IInterestRateModelFacet
 * @dev Interface for the Interest Rate Model Facet, which provides interest rate calculations.
 */
interface IInterestRateModelFacet {
    /**
     * @notice Gets the borrow rate based on the utilization rate.
     * @param utilizationRate The current utilization rate.
     * @return The borrow rate in basis points.
     */
    function getBorrowRate(uint256 utilizationRate) external view returns (uint256);

    /**
     * @notice Compounds interest for a user's token holdings.
     * @param _user The address of the user.
     * @param _token The address of the token.
     */
    function compoundInterestForUser(address _user, address _token) external;
}