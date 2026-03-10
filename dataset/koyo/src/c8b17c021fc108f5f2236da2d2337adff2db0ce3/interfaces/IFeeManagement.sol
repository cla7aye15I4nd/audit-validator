// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IFeeManagement
 * @dev Interface for managing fees within the system.
 */
interface IFeeManagement {
    /**
     * @notice Sets the trading fee in basis points.
     * @param _tradingFeeBasisPoints The trading fee in basis points.
     */
    function setTradingFeeBasisPoints(uint256 _tradingFeeBasisPoints) external;

    /**
     * @notice Sets the borrowing fee in basis points.
     * @param _borrowingFeeBasisPoints The borrowing fee in basis points.
     */
    function setBorrowingFeeBasisPoints(uint256 _borrowingFeeBasisPoints) external;

    /**
     * @notice Sets the lending fee in basis points.
     * @param _lendingFeeBasisPoints The lending fee in basis points.
     */
    function setLendingFeeBasisPoints(uint256 _lendingFeeBasisPoints) external;

    /**
     * @notice Collects a specified token fee.
     * @param token The address of the token.
     * @param amount The amount of the fee to collect.
     */
    function collectFee(address token, uint256 amount) external;

    /**
     * @notice Calculates the trading fee for a given trade amount.
     * @param _tradeAmount The trade amount.
     * @return The trading fee.
     */
    function calculateTradingFee(uint256 _tradeAmount) external view returns (uint256);

    /**
     * @notice Calculates the borrowing fee for a given borrow amount.
     * @param _borrowAmount The borrow amount.
     * @return The borrowing fee.
     */
    function calculateBorrowingFee(uint256 _borrowAmount) external view returns (uint256);

    /**
     * @notice Calculates the lending fee for a given lend amount.
     * @param _lendAmount The lend amount.
     * @return The lending fee.
     */
    function calculateLendingFee(uint256 _lendAmount) external view returns (uint256);
}