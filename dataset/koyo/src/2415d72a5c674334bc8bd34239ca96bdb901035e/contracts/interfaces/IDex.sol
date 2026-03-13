// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title IDex
 * @dev Interface for a decentralized exchange (DEX).
 */
interface IDex {
    /**
     * @notice Swaps an exact amount of tokens for ETH, supporting fee on transfer tokens.
     * @param amountIn The amount of input tokens.
     * @param amountOutMin The minimum amount of ETH to receive.
     * @param path An array of token addresses representing the swap path.
     * @param to The address to receive the ETH.
     * @param deadline The deadline by which the swap must be completed.
     */
    function swapExactTokensForEthSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    /**
     * @notice Swaps an exact amount of ETH for tokens, supporting fee on transfer tokens.
     * @param amountOutMin The minimum amount of tokens to receive.
     * @param path An array of token addresses representing the swap path.
     * @param to The address to receive the tokens.
     * @param deadline The deadline by which the swap must be completed.
     */
    function swapExactEthForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
}