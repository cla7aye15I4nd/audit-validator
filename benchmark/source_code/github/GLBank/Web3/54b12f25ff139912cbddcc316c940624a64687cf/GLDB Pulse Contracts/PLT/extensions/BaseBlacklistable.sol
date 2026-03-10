// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AddressListLib, CommonErrors} from "../lib/AddressList.sol";
import {
    IBlacklistQueryExtension,
    IBlacklistCore
} from "../interfaces/IBlacklistable.sol";

/// @dev Provide blacklist function for Token
abstract contract BaseBlacklistable is IBlacklistCore, IBlacklistQueryExtension {
    using AddressListLib for AddressListLib.AddressList;

    /// @dev Raised if address is not in blacklist
    error Blacklistable__NotInBlacklist();
    /// @dev Raised if address is in blacklist
    error Blacklistable__AlreadyInBlacklist();

    uint256 private constant MAX_BATCH_SIZE = 100;

    function _getBlacklistStorage() internal view virtual returns (AddressListLib.AddressList storage);

    modifier onlyBlacklistController() {
        _validateBlacklistController();
        _;
    }

    function _validateBlacklistController() internal view virtual;

    /// @inheritdoc IBlacklistQueryExtension
    /// @notice Returns the complete list of blacklisted addresses. Be aware that this function
    /// may fail when the list grows too large (typically over 10,000 addresses) due to:
    /// 1. RPC node response size limitations
    /// 2. Block gas limits (for on-chain calls)
    /// 3. EVM stack depth restrictions
    /// If you encounter any issues retrieving the complete list, please use the paginated 
    /// alternative: `blacklistedAddressesPaginated(uint256 offset, uint256 limit)` instead,
    /// which allows retrieving the list in manageable chunks.
    function blacklistedAddresses() external view virtual returns (address[] memory) {
        return _getBlacklistStorage().getList();
    }

    /// @inheritdoc IBlacklistQueryExtension
    function blacklistedAddressesPaginated(uint256 offset, uint256 limit)
        external
        view
        virtual
        returns (address[] memory addresses)
    {
        return _getBlacklistStorage().getListPaginated(offset, limit);
    }

    /// @inheritdoc IBlacklistQueryExtension
    function blacklistedAddressCount() public view virtual returns (uint256) {
        return _getBlacklistStorage().count();
    }

    /// @inheritdoc IBlacklistCore
    function isBlacklisted(address account) public view virtual returns (bool) {
        return _isBlacklisted(account);
    }

    /// @inheritdoc IBlacklistCore
    function areBlacklisted(address[] calldata addresses) external view virtual returns (bool[] memory) {
        return _getBlacklistStorage().areInList(addresses);
    }

    /// @inheritdoc IBlacklistCore
    function addToBlacklist(address addr) external virtual onlyBlacklistController {
        _addToBlacklist(addr, true);
    }

    /// @inheritdoc IBlacklistCore
    /// @dev If the address is already in the blacklist, the function will not revert.
    /// This design choice improves usability by eliminating the need for callers to pre-check addresses,
    /// thus simplifying batch operations and reducing additional on-chain transactions and gas costs.
    function batchAddToBlacklist(address[] calldata addresses) public virtual onlyBlacklistController {
        uint256 len = addresses.length;
        if (len > MAX_BATCH_SIZE) {
            revert CommonErrors.ExceedsMaximumAmount(len, MAX_BATCH_SIZE);
        }

        for (uint256 i = 0; i < len;) {
            _addToBlacklist(addresses[i], false);
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IBlacklistCore
    function removeFromBlacklist(address addr) external virtual onlyBlacklistController {
        _removeFromBlacklist(addr, true);
    }

    /// @inheritdoc IBlacklistCore
    /// @dev If the address to remove is not in the list, it will not be reverted,
    /// This design choice improves usability by eliminating the need for callers to pre-check addresses,
    /// thus simplifying batch operations and reducing additional on-chain transactions and gas costs.
    function batchRemoveFromBlacklist(address[] calldata addresses) public virtual onlyBlacklistController {
        uint256 len = addresses.length;
        if (len > MAX_BATCH_SIZE) {
            revert CommonErrors.ExceedsMaximumAmount(len, MAX_BATCH_SIZE);
        }

        for (uint256 i = 0; i < len;) {
            _removeFromBlacklist(addresses[i], false);
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IBlacklistCore
    /// @dev If the address to remove is not in the list or the address to add is already in the list, it will not be reverted,
    /// This design choice improves usability by eliminating the need for callers to pre-check addresses,
    /// thus simplifying batch operations and reducing additional on-chain transactions and gas costs.
    function updateBlacklist(address[] calldata addressesToAdd, address[] calldata addressesToRemove)
        external
        virtual
        onlyBlacklistController
    {
        batchAddToBlacklist(addressesToAdd);
        batchRemoveFromBlacklist(addressesToRemove);
    }

    function _isBlacklisted(address account) internal view virtual returns (bool) {
        return _getBlacklistStorage().isInList(account);
    }

    function _addToBlacklist(address account, bool strict) internal virtual {
        if (!_getBlacklistStorage().addToList(account)) {
            if (strict) {
                revert Blacklistable__AlreadyInBlacklist();
            } else {
                return;
            }
        }
        emit Blacklisted(account);
    }

    function _removeFromBlacklist(address account, bool strict) internal virtual {
        if (!_getBlacklistStorage().removeFromList(account)) {
            if (strict) {
                revert Blacklistable__NotInBlacklist();
            } else {
                return;
            }
        }
        emit UnBlacklisted(account);
    }
}
