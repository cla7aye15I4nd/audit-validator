// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IWhitelistToggleExtension} from "../interfaces/IWhitelistable.sol";
import {CommonErrors} from "../lib/AddressList.sol";

/// @dev Provide whitelist function for Token
abstract contract BaseToggleWhitelistable is IWhitelistToggleExtension {
    /// @dev Emit when whitelist enabled
    event WhitelistEnabled();
    /// @dev Emit when whitelist disabled
    event WhitelistDisabled();

    /// @custom:storage-location erc7201:eth.storage.WhitelistToggle
    struct WhitelistToggleStorage {
        /// @dev Bool indicate whitelist is enabled or not
        bool whitelistEnabled;
    }

    /// @dev Get the whitelist toggle storage
    /// @return storage The whitelist toggle storage
    function _getWhitelistToggleStorage() internal view virtual returns (WhitelistToggleStorage storage);

    /// @inheritdoc IWhitelistToggleExtension
    function isWhitelistEnabled() public view virtual returns (bool) {
        return _getWhitelistToggleStorage().whitelistEnabled;
    }

    function _setWhitelistEnabled(bool enabled) internal virtual {
        WhitelistToggleStorage storage $ = _getWhitelistToggleStorage();
        if ($.whitelistEnabled == enabled) return;
        if (enabled) {
            emit WhitelistEnabled();
        } else {
            emit WhitelistDisabled();
        }
        $.whitelistEnabled = enabled;
    }

    function _requireWhitelistEnabled() internal view virtual {
        if (!isWhitelistEnabled()) {
            revert CommonErrors.Whitelistable__WhitelistNotEnabled();
        }
    }
}
