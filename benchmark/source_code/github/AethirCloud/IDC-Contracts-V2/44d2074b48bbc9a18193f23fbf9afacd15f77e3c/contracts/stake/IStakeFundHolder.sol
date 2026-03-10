// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title IStakeFundHolder
/// @notice Interface for IStakeFundHolder
interface IStakeFundHolder {
    /// @notice Event emitted when staked tokens are sent to a beneficiary
    event StakedTokenSent(address indexed beneficiary, uint256 amount);

    /// @notice Event emitted when slash penalty tokens are sent to the slash reduction receiver address
    event StakeSlashedTokenSent(uint256 amount);

    /// @notice Event emitted when slash vesting tokens are sent to the vesting fund holder address
    event StakeVestingTokenSent(uint256 amount);

    /// @notice Send staked tokens to a beneficiary
    /// @param beneficiary the address of the beneficiary
    /// @param amount the amount of tokens to send
    function sendStakedToken(address beneficiary, uint256 amount) external;

    /// @notice Send slash penalty tokens to the slash reduction receiver address
    /// @param amount the amount of tokens to send
    function sendSlashedToken(uint256 amount) external;

    /// @notice Send vesting tokens to the vesting fund holder address
    /// @param amount the amount of tokens to send
    function sendVestingToken(uint256 amount) external;
}
