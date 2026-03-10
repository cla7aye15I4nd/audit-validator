// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

interface IVestingFundHolder {
    /// @notice Event emitted when vested tokens are sent to a beneficiary
    event VestedTokenSent(address indexed beneficiary, uint256 amount);
    /// @notice Event emitted when restake fee tokens are sent to the restake fee receiver address
    event RestakeFeeTokenSent(uint256 amount);
    /// @notice Event emitted when restake tokens are sent to the restake fund holder address
    event RestakeTokenSent(uint256 amount);
    /// @notice Event emitted when penalty tokens are sent to the penalty holder address
    event PenaltyTokenSent(uint256 amount);
    /// @notice Event emitted when slashed penalty tokens are sent to the slash reduction receiver address
    event SettleSlashTokenSent(uint256 amount);

    /// @notice Send vested tokens to a beneficiary
    /// @param beneficiary the address of the beneficiary
    /// @param amount the amount of tokens to send
    function sendVestedToken(address beneficiary, uint256 amount) external;

    /// @notice Send restake fee tokens to the restake fee receiver address
    /// @param amount the amount of tokens to send
    function sendRestakeFeeToken(uint256 amount) external;

    /// @notice Send restake tokens to the stake fund holder address
    /// @param amount the amount of tokens to send
    function sendRestakeToken(uint256 amount) external;

    /// @notice Send penalty tokens to the penalty holder address
    /// @param amount the amount of tokens to send
    function sendPenaltyToken(uint256 amount) external;

    /// @notice Send slashed penalty tokens to the slash reduction receiver address
    /// @param amount the amount of tokens to send
    function sendSettleSlashToken(uint256 amount) external;
}
