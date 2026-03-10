// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/**
 * @title IUserStorage
 * @notice Defines the basic interface for the User Storage contract
 */
interface IUserStorage {
    /// @notice Struct to store user data
    struct UserData {
        uint64 nonce;
        uint64 lastUpdateBlock;
    }

    /// @notice Get the user data
    /// @param account The address of the user
    function getUserData(address account) external view returns (UserData memory);

    /// @notice Set the user data
    /// @param account The address of the user
    /// @param data The user data
    function setUserData(address account, UserData memory data) external;
}
