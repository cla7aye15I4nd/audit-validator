// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

interface IVestingConfigurator {
    /// @notice emitted when minimum claim amount is changed
    event MinimumClaimAmountChanged(uint256 value);

    /// @notice returns minimum claim amount
    function getMinimumClaimAmount() external view returns (uint256);

    /// @notice configures minimum claim amount
    /// @param value: new minimum claim amount
    function setMinimumClaimAmount(uint256 value) external;
}
