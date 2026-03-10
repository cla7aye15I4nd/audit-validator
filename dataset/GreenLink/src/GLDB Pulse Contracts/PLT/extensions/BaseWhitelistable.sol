// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AddressListLib, CommonErrors} from "../lib/AddressList.sol";
import {
    IWhitelistQueryExtension,
    IWhitelistCore
} from "../interfaces/IWhitelistable.sol";

/// @dev Provide whitelist function for Token
abstract contract BaseWhitelistable is IWhitelistCore,IWhitelistQueryExtension {
    using AddressListLib for AddressListLib.AddressList;

    /// @dev Raised if address is not in whitelist
    error Whitelistable__NotInWhitelist();
    /// @dev Raised if address is in whitelist
    error Whitelistable__AlreadyInWhitelist();

    AddressListLib.AddressList private _whitelistStorage;
    uint256 private constant MAX_BATCH_SIZE = 100;

    function _getWhitelistStorage() internal view virtual returns (AddressListLib.AddressList storage);

    modifier onlyWhitelistController() {
        _validateWhitelistController();
        _;
    }

    function _validateWhitelistController() internal view virtual;

    /// @inheritdoc IWhitelistQueryExtension
    /// @notice Returns the complete list of whitelisted addresses. Be aware that this function
    /// may fail when the list grows too large (typically over 10,000 addresses) due to:
    /// 1. RPC node response size limitations
    /// 2. Block gas limits (for on-chain calls)
    /// 3. EVM stack depth restrictions
    /// If you encounter any issues retrieving the complete list, please use the paginated 
    /// alternative: `whitelistedAddressesPaginated(uint256 offset, uint256 limit)` instead,
    /// which allows retrieving the list in manageable chunks.
    function whitelistedAddresses() external view virtual returns (address[] memory) {
         return _getWhitelistStorage().getList();
    }

    /// @inheritdoc IWhitelistQueryExtension
    function whitelistedAddressesPaginated(uint256 offset, uint256 limit)
        external
        virtual
        view
        returns (address[] memory addresses)
    {
        return _getWhitelistStorage().getListPaginated(offset, limit);
    }

    /// @inheritdoc IWhitelistQueryExtension
    function whitelistedAddressCount() public view virtual returns (uint256) {
        return _getWhitelistStorage().count();
    }

    /// @inheritdoc IWhitelistCore
    function isWhitelisted(address account) public view virtual returns (bool) {
        return _isWhitelisted(account);
    }

    /// @inheritdoc IWhitelistCore
    function areWhitelisted(address[] calldata addresses) external view virtual returns (bool[] memory) {
        return _getWhitelistStorage().areInList(addresses);
    }

    /// @inheritdoc IWhitelistCore
    function addToWhitelist(address addr) external virtual onlyWhitelistController {
        _addToWhitelist(addr, true);
    }

    /// @inheritdoc IWhitelistCore
    /// @dev If the address is already in the list, the function will not revert.
    /// This design choice improves usability by eliminating the need for callers to pre-check addresses,
    /// thus simplifying batch operations and reducing additional on-chain transactions and gas costs.
    function batchAddToWhitelist(address[] calldata addresses) public virtual onlyWhitelistController {
        uint256 len = addresses.length;
        if (len > MAX_BATCH_SIZE) {
            revert CommonErrors.ExceedsMaximumAmount(len, MAX_BATCH_SIZE);
        }

        for (uint256 i = 0; i < len;) {
            _addToWhitelist(addresses[i], false);
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IWhitelistCore
    function removeFromWhitelist(address addr) external virtual onlyWhitelistController {
        _removeFromWhitelist(addr, true);
    }

    /// @inheritdoc IWhitelistCore
    /// @dev If the address to remove is not in the list, it will not be reverted,
    /// This design choice improves usability by eliminating the need for callers to pre-check addresses,
    /// thus simplifying batch operations and reducing additional on-chain transactions and gas costs.
    function batchRemoveFromWhitelist(address[] calldata addresses) public virtual onlyWhitelistController {
        uint256 len = addresses.length;
        if (len > MAX_BATCH_SIZE) {
            revert CommonErrors.ExceedsMaximumAmount(len, MAX_BATCH_SIZE);
        }

        for (uint256 i = 0; i < len;) {
            _removeFromWhitelist(addresses[i], false);
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IWhitelistCore
    /// @dev If the address to remove is not in the list or the address to add is already in the list, it will not be reverted,
    /// This design choice improves usability by eliminating the need for callers to pre-check addresses,
    /// thus simplifying batch operations and reducing additional on-chain transactions and gas costs.
    function updateWhitelist(address[] calldata addressesToAdd, address[] calldata addressesToRemove)
        external
        virtual
        onlyWhitelistController
    {
        batchAddToWhitelist(addressesToAdd);
        batchRemoveFromWhitelist(addressesToRemove);
    }

    function _isWhitelisted(address account) internal view virtual returns (bool) {
        return _getWhitelistStorage().isInList(account);
    }

    function _addToWhitelist(address account, bool strict) internal virtual {
        if (!_getWhitelistStorage().addToList(account)) {
            if (strict) {
                revert Whitelistable__AlreadyInWhitelist();
            } else {
                return;
            }
        }
        emit Whitelisted(account);
    }

    function _removeFromWhitelist(address account, bool strict) internal virtual {
        if (!_getWhitelistStorage().removeFromList(account)) {
            if (strict) {
                revert Whitelistable__NotInWhitelist();
            } else {
                return;
            }
        }
        emit UnWhitelisted(account);
    }
}
