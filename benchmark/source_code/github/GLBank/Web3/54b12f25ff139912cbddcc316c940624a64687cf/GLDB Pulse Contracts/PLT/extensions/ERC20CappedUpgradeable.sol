// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC20Capped.sol)

pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @dev Extension of {ERC20} that adds a cap to the supply of tokens.
 */
abstract contract ERC20CappedUpgradeable is Initializable, ERC20Upgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.ERC20Capped
    struct ERC20CappedStorage {
        uint256 _cap;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20Capped")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20CappedStorageLocation =
        0x0f070392f17d5f958cc1ac31867dabecfc5c9758b4a419a200803226d7155d00;

    function _getERC20CappedStorage() private pure returns (ERC20CappedStorage storage $) {
        assembly {
            $.slot := ERC20CappedStorageLocation
        }
    }

    /**
     * @dev Total supply cap has been exceeded.
     */
    error ERC20ExceededCap(uint256 increasedSupply, uint256 cap);

    /**
     * @dev Sets the value of the `cap`. This value is immutable, it can only be
     * set once during construction.
     */
    function __ERC20Capped_init(uint256 cap_) internal onlyInitializing {
        __ERC20Capped_init_unchained(cap_);
    }

    function __ERC20Capped_init_unchained(uint256 cap_) internal onlyInitializing {
        if (cap_ > 0) {
            ERC20CappedStorage storage $ = _getERC20CappedStorage();
            $._cap = cap_;
        }
    }

    /**
     * @dev Returns the cap on the token's total supply.
     */
    function cap() public view virtual returns (uint256) {
        ERC20CappedStorage storage $ = _getERC20CappedStorage();
        return $._cap;
    }

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);

        uint256 maxSupply = cap();
        if (from == address(0) && maxSupply > 0) {
            uint256 supply = totalSupply();
            if (supply > maxSupply) {
                revert ERC20ExceededCap(supply, maxSupply);
            }
        }
    }
}
