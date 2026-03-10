// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EnumerableSet} from "../../../lib/openzeppelin/utils/structs/EnumerableSet.sol";

library OgNftDepositStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("anome.og.nft.manager.storage.v1");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    struct Layout {
        mapping(address => EnumerableSet.UintSet) depositedIds;
        mapping(uint256 => uint256) claimRequestTime;
        mapping(uint256 => bool) isClaimedCards;
    }
}
