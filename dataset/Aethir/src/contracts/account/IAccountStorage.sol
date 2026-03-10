// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IAccountHandler} from "./IAccountHandler.sol";

/// @title the interface for account storage
interface IAccountStorage {
    /// @notice update the account information
    /// @param tid the account tid
    /// @param wallet the account wallet
    function bindWallet(uint256 tid, address wallet) external;

    /// @notice get the account information
    /// @param tid the account tid
    /// @return wallet the account wallet
    function getWallet(uint256 tid) external view returns (address wallet);

    /// @notice get the account tid
    /// @param wallet the account wallet
    /// @return tid the account tid
    function getTid(address wallet) external view returns (uint256 tid);

    /// @notice set the account group
    /// @param group the account group
    function setGroup(IAccountHandler.Group memory group) external;

    /// @notice get the account group
    /// @param tid the account tid
    /// @param gid the group id
    /// @return group the account group
    function getGroup(uint256 tid, uint256 gid) external view returns (IAccountHandler.Group memory group);

    /// @notice check if the account group exists
    /// @param tid the account tid
    /// @param gid the group index
    /// @return true if the group exists
    function isGroupExist(uint256 tid, uint256 gid) external view returns (bool);
}
