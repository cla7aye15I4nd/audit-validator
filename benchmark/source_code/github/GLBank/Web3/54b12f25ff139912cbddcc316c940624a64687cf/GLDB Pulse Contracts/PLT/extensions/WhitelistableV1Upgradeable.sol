// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AddressListLib} from "../lib/AddressList.sol";
import {BaseWhitelistable} from "./BaseWhitelistable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract WhitelistableV1Upgradeable is BaseWhitelistable, Initializable {
    function __WhitelistableV1_init() internal onlyInitializing {
        __WhitelistableV1_init_unchained();
    }

    function __WhitelistableV1_init_unchained() internal onlyInitializing {}

    // keccak256(abi.encode(uint256(keccak256("eth.storage.AddressList.whitelist")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WhitelistStorageLocation =
        0x1cfa5e7091c18064c617daf65974fb5d5c7430ad724797e7a06249adbc38f100;

    function _getWhitelistStorage() internal view virtual override returns (AddressListLib.AddressList storage $) {
        assembly {
            $.slot := WhitelistStorageLocation
        }
    }
}
