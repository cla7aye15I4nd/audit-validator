// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/// @title IServiceFeeStorage
/// @notice Interface for the ServiceFeeStorage contract
interface IServiceFeeStorage {
    /// @notice Get the deposited amount for a tenant
    /// @param tid Tenant ID
    /// @return amount deposited amount
    function getDepositedAmount(uint256 tid) external view returns (uint256);

    /// @notice Get the locked amount for a tenant
    /// @param tid Tenant ID
    /// @return amount locked amount
    function getLockedAmount(uint256 tid) external view returns (uint256);

    /// @notice Increase the deposited amount for a tenant
    /// @param tid Tenant ID
    /// @param amount Amount to increase
    function increaseDepositedAmount(uint256 tid, uint256 amount) external;

    /// @notice Increase the deposited amounts for multiple tenants
    /// @param tids Array of tenant IDs
    /// @param amounts Array of amounts
    function increaseDepositedAmounts(uint256[] calldata tids, uint256[] calldata amounts) external;

    /// @notice Decrease the deposited amount for a tenant
    /// @param tid Tenant ID
    /// @param amount Amount to decrease
    function decreaseDepositedAmount(uint256 tid, uint256 amount) external;

    /// @notice Decrease the deposited amounts for multiple tenants
    /// @param tids Array of tenant IDs
    /// @param amounts Array of amounts
    function decreaseDepositedAmounts(uint256[] calldata tids, uint256[] calldata amounts) external;

    /// @notice Increase the locked amount for a tenant
    /// @param tid Tenant ID
    /// @param amount Amount to increase
    function increaseLockedAmount(uint256 tid, uint256 amount) external;

    /// @notice Increase the locked amounts for multiple tenants
    /// @param tids Array of tenant IDs
    /// @param amounts Array of amounts
    function increaseLockedAmounts(uint256[] calldata tids, uint256[] calldata amounts) external;

    /// @notice Decrease the locked amount for a tenant
    /// @param tid Tenant ID
    /// @param amount Amount to decrease
    function decreaseLockedAmount(uint256 tid, uint256 amount) external;

    /// @notice Decrease the locked amounts for multiple tenants
    /// @param tids Array of tenant IDs
    /// @param amounts Array of amounts
    function decreaseLockedAmounts(uint256[] calldata tids, uint256[] calldata amounts) external;
}
