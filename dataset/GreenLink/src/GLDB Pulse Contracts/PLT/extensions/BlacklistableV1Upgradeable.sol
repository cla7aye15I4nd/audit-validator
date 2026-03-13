// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AddressListLib} from "../lib/AddressList.sol";
import {BaseBlacklistable} from "./BaseBlacklistable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract BlacklistableV1Upgradeable is BaseBlacklistable, Initializable {
    function __BlacklistableV1_init() internal onlyInitializing {
        __BlacklistableV1_init_unchained();
    }

    function __BlacklistableV1_init_unchained() internal onlyInitializing {}

    // keccak256(abi.encode(uint256(keccak256("eth.storage.AddressList.blacklist")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BlacklistStorageLocation =
        0xe324a5d682b26d0ea8420970e5277ed2e5a32b3840534fa099829ebe4cef1200;

    function _getBlacklistStorage() internal view virtual override returns (AddressListLib.AddressList storage $) {
        assembly {
            $.slot := BlacklistStorageLocation
        }
    }
}
