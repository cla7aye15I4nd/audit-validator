// SPDX-License-Identifier: MIT
// solhint-disable-next-line one-contract-per-file
pragma solidity ^0.8.20;

/// @title Blacklist Core Interface
/// @notice Gas-efficient blacklist management with batch operations
interface IBlacklistCore {

    /// @dev Emit when an address add in blacklist
    event Blacklisted(address indexed account);
    /// @dev Emit when an address remove from blacklist
    event UnBlacklisted(address indexed account);

    /// @notice Checks if address is blacklisted (O(1) lookup)
    /// @param account Address to check
    function isBlacklisted(address account) external view returns (bool);

    /// @notice Batch check blacklist status (gas optimized)
    /// @param addresses Array of addresses to check
    function areBlacklisted(address[] calldata addresses) external view returns (bool[] memory);

    /// @notice Add single address to blacklist
    /// @dev Emits BlacklistAdded event
    /// @param account Address to add
    function addToBlacklist(address account) external;

    /// @notice Batch add addresses
    /// @param addresses Addresses to add
    function batchAddToBlacklist(address[] calldata addresses) external;

    /// @notice Remove single address
    /// @dev Emits BlacklistRemoved event
    /// @param account Address to remove
    function removeFromBlacklist(address account) external;

    /// @notice Batch remove addresses
    /// @param addresses Addresses to remove
    function batchRemoveFromBlacklist(address[] calldata addresses) external;

    /// @notice Atomic add+remove operation
    /// @param addressesToAdd Addresses to add
    /// @param addressesToRemove Addresses to remove
    function updateBlacklist(
        address[] calldata addressesToAdd,
        address[] calldata addressesToRemove
    ) external;
}

/// @title Interface for blacklist address queries
interface IBlacklistQueryExtension {
    /// @notice Get all blacklisted addresses
    /// @return addresses Array of all blacklisted addresses
    /// @dev Warning: This may consume unbounded gas if the list is large
    function blacklistedAddresses() external view returns (address[] memory addresses);

    /// @notice Get paginated blacklisted addresses
    /// @param offset Number of addresses to skip (0-based index)
    /// @param limit Maximum number of addresses to return
    /// @return addresses Array of blacklisted addresses
    /// @dev Recommended for large blacklists to avoid gas limit issues
    function blacklistedAddressesPaginated(uint256 offset, uint256 limit) external view returns (address[] memory addresses);

    /// @notice Get the total number of blacklisted addresses
    /// @return count The total count of addresses in the blacklist
    /// @dev This function provides an efficient way to determine the size of the blacklist
    function blacklistedAddressCount() external view returns (uint256 count);
}

/// @title Blacklist Toggle Interface
interface IBlacklistToggleExtension {
    /// @notice Returns blacklist enforcement status
    /// @dev When disabled, blacklist checks are bypassed
    /// @return True if blacklist enforcement is active
    function isBlacklistEnabled() external view returns (bool);
}