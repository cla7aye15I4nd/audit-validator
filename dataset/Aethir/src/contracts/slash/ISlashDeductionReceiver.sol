// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title ISlashDeductionReceiver
/// @notice Interface for SlashDeductionReceiver
interface ISlashDeductionReceiver {
    /// @notice emitted when penalty is withdrawn
    event PenaltySlashWithdrawn(address indexed recipient, uint256 amount);

    /// @notice emitted when penalty is sent
    event DeductedSlashingTokenSent(address indexed beneficiary, uint256 amount);

    /// @notice transfer penalty funds
    /// @param recipient recipient of the penalty
    /// @param amount amount of the penalty to transfer
    function withdrawSlashPenalty(address recipient, uint256 amount) external;

    /// @notice Send slash to a beneficiary
    /// @param beneficiary the address of the beneficiary
    /// @param amount the amount of tokens to send
    function sendSlashToken(address beneficiary, uint256 amount) external;
}
