// SPDX-License-Identifier: MIT
// solhint-disable-next-line one-contract-per-file
pragma solidity ^0.8.20;

/// @title Whitelist Core Interface
/// @notice Gas-efficient whitelist management with batch operations
interface IWhitelistCore {

    /// @dev Emit when an address add in whitelist
    event Whitelisted(address indexed account);
    /// @dev Emit when an address remove from whitelist
    event UnWhitelisted(address indexed account);

    /// @notice Checks if address is whitelisted (O(1) lookup)
    /// @param account Address to check
    function isWhitelisted(address account) external view returns (bool);

    /// @notice Batch check whitelist status (gas optimized)
    /// @param addresses Array of addresses to check
    function areWhitelisted(address[] calldata addresses) external view returns (bool[] memory);

    /// @notice Add single address to whitelist
    /// @dev Emits WhitelistAdded event
    /// @param account Address to add
    function addToWhitelist(address account) external;

    /// @notice Batch add addresses
    /// @param addresses Addresses to add
    function batchAddToWhitelist(address[] calldata addresses) external;

    /// @notice Remove single address
    /// @dev Emits WhitelistRemoved event
    /// @param account Address to remove
    function removeFromWhitelist(address account) external;

    /// @notice Batch remove addresses
    /// @param addresses Addresses to remove
    function batchRemoveFromWhitelist(address[] calldata addresses) external;

    /// @notice Atomic add+remove operation
    /// @param addressesToAdd Addresses to add
    /// @param addressesToRemove Addresses to remove
    function updateWhitelist(
        address[] calldata addressesToAdd,
        address[] calldata addressesToRemove
    ) external;
}

/// @title Interface for whitelist address queries
interface IWhitelistQueryExtension {
    /// @notice Get all whitelisted addresses
    /// @return addresses Array of all whitelisted addresses
    /// @dev Warning: This may consume unbounded gas if the list is large
    function whitelistedAddresses() external view returns (address[] memory addresses);

    /// @notice Get paginated whitelisted addresses
    /// @param offset Number of addresses to skip (0-based index)
    /// @param limit Maximum number of addresses to return
    /// @return addresses Array of whitelisted addresses
    /// @dev Recommended for large whitelists to avoid gas limit issues
    function whitelistedAddressesPaginated(uint256 offset, uint256 limit) external view returns (address[] memory addresses);

    /// @notice Get the total number of whitelisted addresses
    /// @return count The total count of addresses in the whitelist
    /// @dev This function provides an efficient way to determine the size of the whitelist
    function whitelistedAddressCount() external view returns (uint256 count);
}

interface IWhitelistToggleExtension {
    /// @notice Returns whitelist enforcement status
    /// @dev When disabled, whitelist checks are bypassed
    /// @return True if whitelist enforcement is active
    function isWhitelistEnabled() external view returns (bool);
}