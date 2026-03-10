// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './LibraryUtil.sol';
import './Types.sol';

/// @dev Generic enumerable maps with all operations O(1) - except enumeration
/// @custom:api public
// prettier-ignore
library EMAP {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint internal constant SENTINEL_INDEX = 0;   // Index 0 and not found in map both resolve to no item
    uint internal constant FIRST_INDEX = 1;      // First actual item begins after the sentinel

    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Structs
    // ───────────────────────────────────────
    /// @dev A value within `UintUint` with a key for O(1) remove
    /// - Upgradability is not a concern for this fundamental type
    struct UintUintValue {
        uint value;
        uint key;
    }

    /// @dev Enumerable map from uint to uint
    /// - Upgradability is not a concern for this fundamental type
    struct UintUint {
        UintUintValue[] values;
        mapping(uint => uint) indexes;
    }

    /// @dev Enumerable map where both key and value are bytes32 (eg a `string` <= 8 chars)
    /// - Upgradability is not a concern for this fundamental type
    struct Bytes32Bytes32 {
        UintUint inner; // Allows impl to be unified
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // UintUint - Core implementation
    // ───────────────────────────────────────

    /// @dev Initialize a `UintUint`,
    function UintUint_init(UintUint storage emap) internal {
        emap.values.push(); // Empty sentinel item, see `SENTINEL_INDEX`
    }

    /// @dev Returns whether the map was initialized
    function initialized(UintUint storage emap) internal view returns(bool) {
        return emap.values.length >= FIRST_INDEX;
    }

    /// @dev An `UintUint` modifier to add an item to `emap` by `key`, does not check for existance
    /// - This 'NoCheck' function reqires the caller to ensure the item does not exist, saves a storage lookup
    function addNoCheck(UintUint storage emap, uint key, uint value) internal {
        UintUintValue[] storage values = emap.values;
        emap.indexes[key] = values.length;                      // Key => index of new item
        values.push(UintUintValue({value: value, key: key}));   // Add value
    }

    /// @dev An `UintUint` modifier to add an item to `emap` by `key`, does a check for existance, no write if found
    function addIfNew(UintUint storage emap, uint key, uint value) internal {
        if (emap.indexes[key] == SENTINEL_INDEX) addNoCheck(emap, key, value);
    }

    /// @dev An `UintUint` modifier to remove an item from `emap` by `key`, O(1) (unordered values)
    function remove(UintUint storage emap, uint key) internal {
        uint i = emap.indexes[key];
        if (i == SENTINEL_INDEX) return; // Not found

        // Remove from array and map via swap-n-pop for stable array indexes (except the moved item)
        UintUintValue[] storage values = emap.values;
        uint last = values.length - 1;
        if (i != last) { // then move item
            UintUintValue memory item = values[last];   // Cache last item
            values[i] = item;                           // Copy last item
            emap.indexes[item.key] = i;                 // Update index for moved item
        }
        values.pop();                                   // Pop: last=0; --length; (remove item)
        delete emap.indexes[key];                       // Delete index for removed item
    }

    /// @dev An `UintUint` accessor to get the number of values
    function length(UintUint storage emap) internal view returns(uint) {
        uint len = emap.values.length;
        return len >= FIRST_INDEX ? len - FIRST_INDEX : 0;
    }

    /// @dev An `UintUint` accessor to get a value at an index; panic if index is out-of-bounds
    function getByIndex(UintUint storage emap, uint index) internal view returns(uint) {
        return emap.values[index].value;
    }

    /// @dev An `UintUint` accessor to get a value by key; zero value if key not found
    function getByKey(UintUint storage emap, uint key) internal view returns(uint) {
        return emap.values[emap.indexes[key]].value;
    }

    // ───────────────────────────────────────
    // Bytes32Bytes32 - Delegates to UintUint
    // ───────────────────────────────────────

    /// @dev Initialize a `Bytes32Bytes32`,
    function Bytes32Bytes32_init(Bytes32Bytes32 storage emap) internal {
        UintUint_init(emap.inner);
    }

    /// @dev Returns whether the map was initialized
    function initialized(Bytes32Bytes32 storage emap) internal view returns(bool) {
        return emap.inner.values.length >= FIRST_INDEX;
    }

    /// @dev An `Bytes32Bytes32` modifier to add an item to `emap` by `key`, does not check for existance
    /// - This 'NoCheck' function reqires the caller to ensure the item does not exist, saves a storage lookup
    function addNoCheck(Bytes32Bytes32 storage emap, bytes32 key, bytes32 value) internal {
        addNoCheck(emap.inner, uint(bytes32(key)), uint(bytes32(value)));
    }

    /// @dev An `Bytes32Bytes32` modifier to add an item to `emap` by `key`, does a check for existance, no write if found
    function addIfNew(Bytes32Bytes32 storage emap, bytes32 key, bytes32 value) internal {
        addIfNew(emap.inner, uint(bytes32(key)), uint(bytes32(value)));
    }

    /// @dev An `Bytes32Bytes32` modifier to remove an item from `emap` by `key`, O(1) (unordered values)
    function remove(Bytes32Bytes32 storage emap, bytes32 key) internal {
        remove(emap.inner, uint(bytes32(key)));
    }

    /// @dev An `Bytes32Bytes32` accessor to get the number of values
    function length(Bytes32Bytes32 storage emap) internal view returns(uint) {
        return length(emap.inner);
    }

    /// @dev An `Bytes32Bytes32` accessor to get a value at an index
    function getByIndex(Bytes32Bytes32 storage emap, uint index) internal view returns(bytes32) {
        return bytes32(bytes32(emap.inner.values[index].value));
    }

    /// @dev An `Bytes32Bytes32` accessor to get a value by key; zero value if key not found
    function getByKey(Bytes32Bytes32 storage emap, bytes32 key) internal view returns(bytes32) {
        return bytes32(bytes32(emap.inner.values[emap.inner.indexes[uint(bytes32(key))]].value));
    }
}
