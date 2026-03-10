// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title ISlashStorage
/// @notice Interface for SlashStorage
interface ISlashStorage {
    /// @notice Penalty struct
    /// @param amount penalty amount
    /// @param ts creation timestamp
    struct Penalty {
        uint256 amount;
        uint256 ts;
    }

    /// @notice increase penalty for host
    /// @param tid tid
    /// @param gid gid
    /// @param container container
    /// @param amount penalty amount
    function increaseTicket(uint256 tid, uint256 gid, uint256 container, uint256 amount) external;

    /// @notice decrease penalty for host
    /// @param tid tid
    /// @param gid gid
    /// @param container container
    /// @param amount penalty amount
    function decreaseTicket(uint256 tid, uint256 gid, uint256 container, uint256 amount) external;

    /// @notice returns ticket for host
    /// @param tid tid
    /// @param gid gid
    /// @param container container
    function getTicket(uint256 tid, uint256 gid, uint256 container) external view returns (Penalty memory);

    /// @notice deletes penalty for host
    /// @param tid tid
    /// @param gid gid
    /// @param container container
    function deleteTicket(uint256 tid, uint256 gid, uint256 container) external;

    /// @notice returns total penalty amount for host
    /// @param tid tid
    function totalPenalty(uint256 tid) external view returns (uint256);
}
