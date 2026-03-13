// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBlacklistToggleExtension} from "../interfaces/IBlacklistable.sol";
import {CommonErrors} from "../lib/AddressList.sol";

abstract contract BaseToggleBlacklistable is IBlacklistToggleExtension {
    /// @dev Emit when blacklist enabled
    event BlacklistEnabled();
    /// @dev Emit when blacklist disabled
    event BlacklistDisabled();

    /// @custom:storage-location erc7201:eth.storage.BlacklistToggle
    struct BlacklistToggleStorage {
        /// @dev Bool indicate blacklist is enabled or not
        bool blacklistEnabled;
    }

    /// @dev Get the blacklist toggle storage
    /// @return storage The blacklist toggle storage
    function _getBlacklistToggleStorage() internal view virtual returns (BlacklistToggleStorage storage);

    /// @inheritdoc IBlacklistToggleExtension
    function isBlacklistEnabled() public view virtual returns (bool) {
        return _getBlacklistToggleStorage().blacklistEnabled;
    }

    function _setBlacklistEnabled(bool enabled) internal virtual {
        BlacklistToggleStorage storage $ = _getBlacklistToggleStorage();
        if ($.blacklistEnabled == enabled) return;
        if (enabled) {
            emit BlacklistEnabled();
        } else {
            emit BlacklistDisabled();
        }
        $.blacklistEnabled = enabled;
    }

    function _requireBlacklistEnabled() internal view virtual {
        if (!isBlacklistEnabled()) {
            revert CommonErrors.Blacklistable__BlacklistNotEnabled();
        }
    }
}
