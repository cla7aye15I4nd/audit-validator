// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

interface IVestingPenaltyReceiver {
    /// @notice Emitted when the penalty tokens are withdrawn
    event EarlyClaimPenaltyWithdrawn(address indexed to, uint256 amount);

    /// @notice Withdraw the penalty tokens
    /// @param to the address to send the penalty tokens to
    /// @param amount the amount of penalty tokens to send
    function withdrawEarlyClaimPenalty(address to, uint256 amount) external;
}
