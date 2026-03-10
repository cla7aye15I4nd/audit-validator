// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IFeeManagement
 * @dev Interface for managing protocol fees and fee distribution
 * @notice Defines the interface for fee calculations, collection, and distribution
 */
interface IFeeManagement {
    /**
     * @dev Emitted when fees are collected
     */
    event FeesCollected(
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );

    /**
     * @dev Emitted when fees are distributed
     */
    event FeesDistributed(
        uint256 burnAmount,
        uint256 daoAmount,
        uint256 rewardAmount,
        uint256 ecosystemAmount,
        uint256 timestamp
    );

    /**
     * @dev Emitted when fee parameters are updated
     */
    event FeeParametersUpdated(
        uint256 tradingFee,
        uint256 borrowingFee,
        uint256 lendingFee,
        uint256 timestamp
    );

    /**
     * @notice Sets the trading fee in basis points
     * @param _tradingFeeBasisPoints The trading fee in basis points
     */
    function setTradingFeeBasisPoints(uint256 _tradingFeeBasisPoints) external;

    /**
     * @notice Sets the borrowing fee in basis points
     * @param _borrowingFeeBasisPoints The borrowing fee in basis points
     */
    function setBorrowingFeeBasisPoints(uint256 _borrowingFeeBasisPoints) external;

    /**
     * @notice Sets the lending fee in basis points
     * @param _lendingFeeBasisPoints The lending fee in basis points
     */
    function setLendingFeeBasisPoints(uint256 _lendingFeeBasisPoints) external;

    /**
     * @notice Collects fees for a specific token
     * @param token The token address
     * @param amount The amount to collect
     */
    function collectFee(address token, uint256 amount) external;

    /**
     * @notice Calculates the trading fee for a given amount
     * @param amount The amount to calculate the fee for
     * @return The calculated trading fee
     */
    function calculateTradingFee(uint256 amount) external view returns (uint256);

    /**
     * @notice Calculates the borrowing fee for a given amount
     * @param amount The amount to calculate the fee for
     * @return The calculated borrowing fee
     */
    function calculateBorrowingFee(uint256 amount) external view returns (uint256);

    /**
     * @notice Calculates the lending fee for a given amount
     * @param amount The amount to calculate the fee for
     * @return The calculated lending fee
     */
    function calculateLendingFee(uint256 amount) external view returns (uint256);

    /**
     * @notice Updates fee distribution parameters
     * @param burnShare Percentage for token burning
     * @param daoShare Percentage for DAO treasury
     * @param rewardShare Percentage for rewards
     * @param ecosystemShare Percentage for ecosystem development
     */
    function updateFeeDistribution(
        uint256 burnShare,
        uint256 daoShare,
        uint256 rewardShare,
        uint256 ecosystemShare
    ) external;

    /**
     * @notice Sets the fee recipient address
     * @param recipient The new fee recipient address
     */
    function setFeeRecipient(address recipient) external;

    /**
     * @notice Sets the fee token
     * @param token The new fee token
     */
    function setFeeToken(IERC20 token) external;
}