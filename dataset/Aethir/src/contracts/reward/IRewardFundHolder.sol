// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

interface IRewardFundHolder {
    /// @dev Emitted when reward tokens are sent to a beneficiary.
    event RewardTokenSent(address indexed beneficiary, uint256 amount);
    /// @notice Event emitted when commission tokens are sent to the commission receiver address
    event RewardCommissionTokenSent(uint256 amount);
    /// @notice Event emitted when slashed vesting tokens are sent to the vesting fund holder address
    event RewardVestingTokenSent(uint256 amount);
    /// @notice Event emitted when slashed penalty tokens are sent to the slash reduction receiver address
    event RewardSlashedTokenSent(uint256 amount);
    /// @dev Emitted when reward tokens are withdrawn from the reward fund.
    event RewardTokenWithdrawn(address indexed recipient, uint256 amount);

    /// @dev Sends reward tokens to a beneficiary.
    /// @param beneficiary The address of the beneficiary.
    /// @param amount The amount of reward tokens to send.
    function sendRewardToken(address beneficiary, uint256 amount) external;

    /// @notice Send service fee commission tokens to the commission receiver address
    /// @param amount the amount of tokens to send
    function sendCommissionToken(uint256 amount) external;

    /// @notice Send vesting tokens to the vesting fund holder address
    /// @param amount the amount of tokens to send
    function sendVestingToken(uint256 amount) external;

    /// @notice Send slashed penalty tokens to the slash reduction receiver address
    /// @param amount the amount of tokens to send
    function sendSlashedToken(uint256 amount) external;

    /// @dev Withdraws reward tokens from the reward fund.
    /// @param recipient The address of the recipient.
    /// @param amount The amount of reward tokens to withdraw.
    function withdrawRewardToken(address recipient, uint256 amount) external;
}
