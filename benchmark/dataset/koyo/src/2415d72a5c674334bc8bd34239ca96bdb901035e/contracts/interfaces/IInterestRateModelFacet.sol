// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title IInterestRateModelFacet
 * @dev Interface for managing interest rates and compounding
 * @notice Defines the interface for interest rate calculations and management
 */
interface IInterestRateModelFacet {
    /**
     * @dev Emitted when interest rates are updated
     */
    event InterestRatesUpdated(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 optimal,
        uint256 reserve,
        uint256 timestamp
    );

    /**
     * @dev Emitted when interest is accrued
     */
    event InterestAccrued(
        address indexed token,
        address indexed user,
        uint256 interestAccrued,
        uint256 newTotalBorrows,
        uint256 timestamp
    );

    /**
     * @notice Gets the borrow rate based on utilization rate
     * @param utilizationRate The current utilization rate
     * @return The borrow rate per year, scaled by 1e18
     */
    function getBorrowRate(uint256 utilizationRate) external view returns (uint256);

    /**
     * @notice Compounds interest for a user's token holdings
     * @param _user The address of the user
     * @param _token The address of the token
     */
    function compoundInterestForUser(address _user, address _token) external;

    /**
     * @notice Calculates interest for a borrowed amount
     * @param _borrowedAmount The amount borrowed
     * @return The calculated interest amount
     */
    function calculateInterest(uint256 _borrowedAmount) external view returns (uint256);

    /**
     * @notice Gets the current global interest index
     * @return The current global interest index
     */
    function getGlobalIndex() external view returns (uint256);

    /**
     * @notice Updates the global interest index
     */
    function updateGlobalIndex() external;

    /**
     * @notice Gets the current supply rate
     * @return The supply rate per year, scaled by 1e18
     */
    function getSupplyRate() external view returns (uint256);

    /**
     * @notice Calculates the current utilization rate
     * @return The utilization rate, scaled by 1e18
     */
    function calculateUtilizationRate() external view returns (uint256);

    /**
     * @notice Initializes the interest rate model
     * @param baseRatePerYear The base interest rate per year
     * @param multiplierPerYear The rate multiplier per year
     * @param jumpMultiplierPerYear The jump multiplier per year
     * @param optimal The optimal utilization rate
     * @param reserve The reserve factor
     * @param compoundingFrequency The frequency of compounding
     */
    function initializeInterestRate(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 optimal,
        uint256 reserve,
        uint256 compoundingFrequency
    ) external;
}