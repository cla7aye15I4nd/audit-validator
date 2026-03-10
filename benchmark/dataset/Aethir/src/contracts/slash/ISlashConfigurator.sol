// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title ISlashConfigurator
/// @notice Interface for SlashConfigurator
interface ISlashConfigurator {
    /// @notice Emitted when the time after which a ticket expires is set
    event TicketExpireTimeSet(uint256 expireTime);

    /// @notice Get the time after which a ticket expires
    /// @return expireTime The time after which a ticket expires
    function getTicketExpireTime() external view returns (uint256);

    /// @notice Set the time after which a ticket expires
    /// @param expireTime The time after which a ticket expires
    function setTicketExpireTime(uint256 expireTime) external;
}
