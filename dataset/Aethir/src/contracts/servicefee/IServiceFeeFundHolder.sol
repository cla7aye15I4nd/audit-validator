// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

interface IServiceFeeFundHolder {
    /// @notice Event emitted when service fee tokens are sent
    event ServiceFeeTokenSent(address indexed beneficiary, uint256 amount);
    /// @notice Event emitted when commission tokens are sent to the commission receiver address
    event ServiceFeeCommissionTokenSent(uint256 amount);
    /// @notice Event emitted when slashed vesting tokens are sent to the vesting fund holder address
    event ServiceFeeVestingTokenSent(uint256 amount);
    /// @notice Event emitted when slashed penalty tokens are sent to the slash reduction receiver address
    event ServiceFeeSlashedTokenSent(uint256 amount);

    /// @notice Send service fee tokens to a beneficiary
    /// @param beneficiary the address of the beneficiary
    /// @param amount the amount of tokens to send
    function sendServiceFeeToken(address beneficiary, uint256 amount) external;

    /// @notice Send service fee commission tokens to the commission receiver address
    /// @param amount the amount of tokens to send
    function sendCommissionToken(uint256 amount) external;

    /// @notice Send vesting tokens to the vesting fund holder address
    /// @param amount the amount of tokens to send
    function sendVestingToken(uint256 amount) external;

    /// @notice Send slashed penalty tokens to the slash reduction receiver address
    /// @param amount the amount of tokens to send
    function sendSlashedToken(uint256 amount) external;
}
