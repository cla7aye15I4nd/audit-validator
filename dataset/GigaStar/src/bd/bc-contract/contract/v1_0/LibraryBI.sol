// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './LibraryUtil.sol';

/// @dev Box Info Library
/// @custom:api public
// prettier-ignore
library BI { // Box Info
    uint private constant SENTINEL_INDEX = 0;    // Index 0 and not found in map both resolve to no item
    uint internal constant FIRST_INDEX = 1;      // First actual item begins after the sentinel

    /// @dev Tracks info per Box
    /// - Upgradability provides backwards compatibility in storage
    struct BoxInfo {
        address boxProxy;
        string name;
        bytes32 nameKey;
        uint version;

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Enumerable multi-key map to BoxInfo from any key in: name, addr
    /// - The core struct where functions are accessors
    /// - Upgradability provides backwards compatibility in storage
    struct Emap {
        BoxInfo[] values;
        mapping(bytes32 => uint) idxByName;
        mapping(address => uint) idxByAddr;

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Initialize a `Emap`,
    function Emap_init(Emap storage emap) internal {
        emap.values.push(); // Empty sentinel item, see `SENTINEL_INDEX`
    }

    /// @dev Returns whether the map was initialized
    function initialized(Emap storage emap) internal view returns(bool) {
        return emap.values.length >= FIRST_INDEX;
    }

    /// @dev A `Emap` accessor to get an item from `emap` by `nameKey`, does not check for existance
    /// - This 'NoCheck' function reqires the caller to ensure the item does not exist, saves a storage lookup
    /// - The box `nameKey` and `value.boxProxy` must be unique across all boxes, validated by caller
    function addBoxNoCheck(Emap storage emap, bytes32 nameKey, BoxInfo memory value) internal {
        BoxInfo[] storage values = emap.values;
        uint i = values.length;             // Index of next value
        values.push(value);                 // Add value
        emap.idxByName[nameKey] = i;        // Associate the item in the map by nameKey
        emap.idxByAddr[value.boxProxy] = i; // Associate the item in the map by addr
    }

    /// @dev A `Emap` modifier to remove an item from `emap` by `nameKey`, O(1) (unordered values)
    function removeBoxByName(Emap storage emap, bytes32 nameKey) internal {
        uint i = emap.idxByName[nameKey];
        if (i == SENTINEL_INDEX) return; // Not found

        // Remove from array and maps via swap-n-pop for stable array indexes (except the moved item)
        BoxInfo[] storage values = emap.values;
        BoxInfo storage info = values[i];
        delete emap.idxByAddr[info.boxProxy];   // Remove mapped index for removed item
        delete emap.idxByName[nameKey];         // Remove mapped index for removed item
        uint last = values.length - 1;
        if (i != last) { // then move item
            BoxInfo memory item = values[last]; // Cache last item
            values[i] = item;                   // Copy last item
            emap.idxByAddr[item.boxProxy] = i;  // Update index for moved item
            emap.idxByName[item.nameKey] = i;   // Update index for moved item
        }
        values.pop();                           // Pop: last=0; --length; (remove item)
    }

    /// @dev Rename an existing box
    /// @return Whether the rename was successful
    function renameBox(Emap storage emap, bytes32 oldNameKey, bytes32 newNameKey, string memory newName)
        internal returns(bool)
    {
        uint i = emap.idxByName[newNameKey];
        if (i != SENTINEL_INDEX) return false; // New name already in use

        i = emap.idxByName[oldNameKey];
        if (i == SENTINEL_INDEX) return false; // Old name not found

        // Update value
        BoxInfo storage box = emap.values[i];
        box.nameKey = newNameKey;
        box.name = newName;

        // Update mapping to `values` index
        delete emap.idxByName[oldNameKey];  // Remove old name mapping to index
        emap.idxByName[newNameKey] = i;     // Add new name mapping to index
        // No need to update `emap.idxByAddr`
        return true;
    }

    /// @dev An `Emap` accessor to get an item from `emap` by `boxProxy`, O(1)
    function tryGetBoxByAddr(Emap storage emap, address boxProxy) internal view
        returns(bool found, BoxInfo storage value)
    {
        uint i = emap.idxByAddr[boxProxy];
        return (i != SENTINEL_INDEX, emap.values[i]);
    }

    /// @dev An `Emap` accessor to get an item from `emap` by `nameKey`, O(1)
    function tryGetBoxByName(Emap storage emap, bytes32 nameKey) internal view
        returns(bool found, BoxInfo storage value)
    {
        uint i = emap.idxByName[nameKey];
        return (i != SENTINEL_INDEX, emap.values[i]);
    }

    /// @dev An `Emap` accessor to get a value at an index; panic if index is out-of-bounds
    function getByIndex(Emap storage emap, uint index) internal view returns(BoxInfo storage) {
        return emap.values[index];
    }

    /// @dev An `Emap` accessor to return whether a box exists by nameKey
    function exists(Emap storage emap, bytes32 nameKey) internal view returns(bool found) {
        return emap.idxByName[nameKey] != SENTINEL_INDEX;
    }

    /// @dev An `Emap` accessor to get the number of values
    function length(Emap storage emap) internal view returns(uint) {
        uint len = emap.values.length;
        return len >= FIRST_INDEX ? len - FIRST_INDEX : 0;
    }
}
