// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title IShibaBurn
 * @dev Interface for SHIB token burning operations
 * @notice Defines the interface for buying and burning SHIB tokens
 */
interface IShibaBurn {
    /**
     * @dev Emitted when tokens are burned
     */
    event TokensBurned(
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );

    /**
     * @dev Emitted when tokens are bought for burning
     */
    event TokensBought(
        address indexed token,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );

    /**
     * @notice Buys and burns tokens
     * @param tokenAddress The token address to buy and burn
     * @param minOut The minimum amount of tokens to receive
     */
    function buyAndBurn(
        address tokenAddress,
        uint256 minOut
    ) external payable;

    /**
     * @notice Gets the amount of tokens that would be received for a given input
     * @param tokenAddress The token address
     * @param amountIn The input amount
     * @return The expected output amount
     */
    function getExpectedOutput(
        address tokenAddress,
        uint256 amountIn
    ) external view returns (uint256);

    /**
     * @notice Gets the total amount of tokens burned
     * @param tokenAddress The token address
     * @return The total amount burned
     */
    function getTotalBurned(
        address tokenAddress
    ) external view returns (uint256);
}