// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IShibaBurn
 * @dev Interface for the ShibaBurn contract, which executes token buy and burn operations.
 */
interface IShibaBurn {
    /**
     * @notice Buys and burns a specified amount of tokens.
     * @param tokenAddress The address of the token to buy and burn.
     * @param minOut The minimum amount of tokens expected from the swap.
     */
    function buyAndBurn(address tokenAddress, uint256 minOut) external payable;
}