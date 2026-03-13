// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './LibraryUtil.sol';
import './Types.sol';

/// @dev Instrument Revenue Library
/// @custom:api public
// prettier-ignore
library IR { // Instrument Revenue
    uint internal constant SENTINEL_INDEX = 0; // Index 0 and not found in map both resolve to no item
    uint internal constant FIRST_INDEX = 1;    // First actual item begins after the sentinel

    error InstRevExists(string instName, uint earnDate);

    // ───────────────────────────────────────
    // Structs (See MEM_LAYOUT)
    // ───────────────────────────────────────

    /// @dev Instrument Revenue for investors
    /// - Upgradability provides backwards compatibility in storage
    struct InstRev {
        string instName;        /// Instrument name, Symbol and series (eg. ABCD.1), max len 32 chars
        bytes32 instNameKey;    /// key: (Set on-chain from `instName`, awkward but avoids another type)
        uint earnDate;          /// key: When revenue was earned by investors, UTC unix epoch seconds
        uint unitRev;           /// Owner revenue per unit; basically: totalRev / totalQty
        uint totalRev;          /// Instrument's total revenue for investors (unitRev x totalQty) - no residual
        uint totalQty;          /// Instrument's total units
        address dropAddr;       /// Revenue drop/deposit box address
        address ccyAddr;        /// Revenue token address
        uint uploadedAt;        /// block.timestamp when fully uploaded
        uint executedAt;        /// block.timestamp when fully executed

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Stores the index into each array; allows O(1) find and remove in each array
    /// - Upgradability is not a concern for this fundamental type
    struct Cursor {
        uint iValue;            /// Index in `values` array, like a pointer
        uint iName;             /// Index in `idxName` value array, like a double ptr
        uint iDate;             /// Index in `idxDate` value array, like a double ptr
    }

    /// @dev The core struct where functions are accessors
    /// - An enumerable map from (InstName, EarnDate) to InstRev[]
    /// - Each index relates to a branch in `getInstRevs` conditioned on the input filter
    /// - Upgradability provides backwards compatibility in storage
    struct Emap {
        InstRev[] values;                           /// Items across all keys
        mapping(bytes32 =>
            mapping(uint => Cursor)) idxNameDate;   /// Keys: InstName, EarnDate; Indexes
        mapping(bytes32 => uint[]) idxName;         /// Key: InstName; Indexes in `values`; (name => value indexes)
        mapping(uint => uint[]) idxDate;            /// Key: EarnDate; Indexes in `values`; (date => value indexes)

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Initialize a `Emap`,
    function Emap_init(Emap storage emap) internal {
        emap.values.push(); // Empty sentinel item, see `SENTINEL_INDEX`
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    /// @dev Returns whether the map was initialized
    function initialized(Emap storage emap) internal view returns(bool) {
        return emap.values.length >= FIRST_INDEX;
    }

    /// @dev Get an OwnSnap from the pool, do not create
    function exists(Emap storage emap, bytes32 instName, uint earnDate) internal view returns(bool) {
        return emap.idxNameDate[instName][earnDate].iValue != SENTINEL_INDEX;
    }

    /// @dev An `Emap` accessor to add an item by `instName,earnDate`, error if already exists
    /// - The calldata parameter version of `addMem`
    function addFromCd(Emap storage emap, InstRev calldata ir, bytes32 instNameKey, bool checkNew) internal {
        Cursor storage cursor = emap.idxNameDate[instNameKey][ir.earnDate];
        uint iValue = cursor.iValue;
        if (iValue != SENTINEL_INDEX) { // then exists
            if (checkNew) revert InstRevExists(ir.instName, ir.earnDate); // Update not allowed

            // Update existing value, `ir.instNameKey` is fixed, part of PK
            emap.values[iValue] = ir;                            // Overwrite fields from source
            emap.values[iValue].uploadedAt = block.timestamp;    // Overwrite field
            return;
        }

        // Not found, add to `values` and indexes
        { // var scope
            InstRev[] storage values = emap.values;
            iValue = values.length;                 // New value's index
            values.push(ir);                        // Copy fields from source
            InstRev storage irNew = values[iValue]; // Get new mutable storage (must not change `ir`)
            irNew.uploadedAt = block.timestamp;     // Set field
            irNew.instNameKey = instNameKey;        // Set field
            cursor.iValue = iValue;                 // Ref for O(1) find in `values`
        }

        _addToIndexes(emap.idxName[instNameKey], emap.idxDate[ir.earnDate], cursor, iValue);
    }

    /// @dev An `Emap` accessor to add an item by `instName,earnDate`, error if already exists
    /// - The storage parameter version of `addMem` where the param should not be modified
    function addFromStore(Emap storage emap, InstRev storage ir, bytes32 instNameKey, bool checkNew) internal {
        Cursor storage cursor = emap.idxNameDate[instNameKey][ir.earnDate];
        uint iValue = cursor.iValue;
        if (iValue != SENTINEL_INDEX) { // then exists
            if (checkNew) revert InstRevExists(ir.instName, ir.earnDate); // Update not allowed

            // Update existing value, `ir.instNameKey` is fixed, part of PK
            emap.values[iValue] = ir;                            // Overwrite fields from source
            emap.values[iValue].uploadedAt = block.timestamp;    // Overwrite field
            return;
        }

        // Not found, add to `values` and indexes
        { // var scope
            InstRev[] storage values = emap.values;
            iValue = values.length;                 // New value's index
            values.push(ir);                        // Copy fields from source
            InstRev storage irNew = values[iValue]; // Get new mutable storage (must not change `ir`)
            irNew.uploadedAt = block.timestamp;     // Set field
            irNew.instNameKey = instNameKey;        // Set field
            cursor.iValue = iValue;                 // Ref for O(1) find in `values`
        }

        _addToIndexes(emap.idxName[instNameKey], emap.idxDate[ir.earnDate], cursor, iValue);
    }

    function _addToIndexes(uint[] storage indexesByName, uint[] storage indexesByDate,
        Cursor storage cursor, uint iValue) private
    {
        cursor.iName = indexesByName.length;        // Update name array index for the following value
        indexesByName.push(iValue);                 // Ref for O(1) find in `values`

        cursor.iDate = indexesByDate.length;        // Update date array index for the following value
        indexesByDate.push(iValue);                 // Ref for O(1) find in `values`
    }

    function remove(Emap storage emap, bytes32 instName, uint earnDate) internal {
        Cursor memory remCur = emap.idxNameDate[instName][earnDate];    // Removed item cursor
        if (remCur.iValue == SENTINEL_INDEX) return;                     // Not found

        // Remove from arrays and maps via swap-n-pop for stable array indexes (except the moved item)
        // Temoved item is replaced by the last item and then the last item is removed,
        // Cursor is conditionally updated for each array, it's tedious as iName and iDate are like double ptrs

        { // var scope
            // Get info for the value to be moved during swap-n-pop
            uint iValueLast = emap.values.length - 1;                       // Index of last item (item to move)
            InstRev storage movedIr = emap.values[iValueLast];
            bytes32 movedName = movedIr.instNameKey;
            uint movedDate = movedIr.earnDate;
            Cursor storage movCur = emap.idxNameDate[movedName][movedDate];  // Moved item cursor

            // Remove from emap.values
            uint iRemove = remCur.iValue;                           // Index of item to remove (item to overwrite)
            if (iRemove != iValueLast) {                            // If the item to remove is last, skip the move
                emap.values[iRemove] = movedIr;                     // Swap-n-pop part 1 of 2

                movCur.iValue = iRemove;                            // Update cursor to values array
                emap.idxName[movedName][movCur.iName] = iRemove;    // Update array's value for moved item
                emap.idxDate[movedDate][movCur.iDate] = iRemove;    // Update array's value for moved item
            }
        }
        emap.values.pop();                                          // Swap-n-pop part 2 of 2
        delete emap.idxNameDate[instName][earnDate];                // Delete cursor for removed item

        // Remove from name array
        _removeFromArray(emap, emap.idxName[instName], remCur.iName, true);

        // Remove from date array
        _removeFromArray(emap, emap.idxDate[earnDate], remCur.iDate, false);
    }

    /// @dev Helper for `remove` to remove an item from an array of indexes into `values`
    /// @param arr An array of indexes into `values`
    /// @param iRemove The index in `arr` that is being removed
    /// @param isName Whether the subject array is by name
    function _removeFromArray(Emap storage emap, uint[] storage arr, uint iRemove, bool isName) private {
        uint iLast = arr.length - 1;    // Index of last item (item to move)
        if (iRemove != iLast) {         // If the item to remove is last, skip the move
            uint iValue = arr[iLast];   // Cache the value to move (an index into `values`)
            arr[iRemove] = iValue;      // Swap-n-pop part 1 of 2

            // Update the moved index's cursor (unrelated to the moved value as this array is a subset of indexes)
            // Ignoring an optimization of the existing cursor being affected - simplifies already complex code
            InstRev storage ir = emap.values[iValue];                              // Find InstRev for iValue
            Cursor storage cursor = emap.idxNameDate[ir.instNameKey][ir.earnDate]; // Cursor for iValue
            if (isName) {
                cursor.iName = iRemove;
            } else {
                cursor.iDate = iRemove;
            }
        }
        arr.pop(); // Swap-n-pop part 2 of 2; If `arr` is empty, deleted implicitly
    }

    /// @dev An `Emap` accessor to get the InstRev count
    function length(Emap storage emap) internal view returns(uint) {
        uint len = emap.values.length;
        return len >= FIRST_INDEX ? len - FIRST_INDEX : 0;
    }

    /// @dev An `Emap` accessor to get a value at an index
    function getByIndex(Emap storage emap, uint index) internal view returns(InstRev storage) {
        return emap.values[index + FIRST_INDEX];
    }

    /// @dev An `Emap` accessor to get an item by key; result is empty if not found
    function getByKey(Emap storage emap, bytes32 instName, uint earnDate) internal view
        returns(InstRev storage instRev)
    {
        return emap.values[emap.idxNameDate[instName][earnDate].iValue];
    }

    /// @dev An `Emap` accessor to get item count based on the filter of params
    /// @param emap Map on which this is an accessor
    /// @param instName Instrument name to filter or empty to get all
    /// @param earnDate Earn date to filter or 0 to get all
    function getInstRevsLen(Emap storage emap, bytes32 instName, uint earnDate) internal view returns(uint) {
        if (instName != bytes32(0)) {
            if (earnDate == 0) {
                // Get length where instName=set, earnDate=empty (all InstRev for an instrument)
                return emap.idxName[instName].length;
            }
            // Length where instName=set, earnDate=set (a single instrument and earn date)
            return exists(emap, instName, earnDate) ? 1 : 0;
        }
        if (earnDate > 0) {
            // Get length where instName=empty, earnDate=set (all InstRev for an earn date)
            return emap.idxDate[earnDate].length;
        }
        // Get length where instName=empty, earnDate=empty (all InstRev)
        return length(emap);
    }

    /// @dev An `Emap` accessor to get InstRevs matching the filter: `instName`, `earnDate`
    /// - To get a single result prefer `getByKey`
    /// - Caller must page outputs to avoid gas issues, see PAGE_REQUESTS
    /// @param emap Map on which this is an accessor
    /// @param instName An instrument name to filter or empty to get all
    /// @param earnDate An earn date to filter or 0 to get all
    /// @param iBegin Index in the array to begin processing
    /// @param count Items to get, 0 = [iBegin:] (may exceed gas), May call `getInstRevsLen` with same inputs
    /// @return results Items matching the given filter
    function getInstRevs(Emap storage emap, bytes32 instName, uint earnDate, uint iBegin, uint count)
        internal view returns(InstRev[] memory results)
    { unchecked {
        if (instName != bytes32(0)) {
            if (earnDate == 0) {
                // Get all earn dates for an instrument (instName=set, earnDate=empty)
                return _getInstRevs(emap, emap.idxName[instName], iBegin, count);
            }
            // Get 1 result (instName=set, earnDate=set)
            uint iValue = emap.idxNameDate[instName][earnDate].iValue;
            if (iValue != SENTINEL_INDEX) { // then found
                results = new InstRev[](1);
                results[0] = emap.values[iValue];
            }
            return results;
        }
        if (earnDate > 0) {
            // Get all instruments for an earn dates (instName=empty, earnDate=set)
            return _getInstRevs(emap, emap.idxDate[earnDate], iBegin, count);
        }
        // Get all results (instName=empty, earnDate=empty)
        InstRev[] storage values = emap.values;

        // Calculate results length
        iBegin += FIRST_INDEX; // to ignore sentinel value
        uint resultsLen = Util.getRangeLen(values.length, iBegin, count);
        if (resultsLen == 0) return results;

        // Get results slice
        results = new InstRev[](resultsLen);
        for (uint i = 0; i < resultsLen; ++i) { // Ubound: Caller must page
            results[i] = values[iBegin + i];
        }
    } }

    /// @dev utility for `getInstRevs`
    function _getInstRevs(Emap storage emap, uint[] memory indexes, uint iBegin, uint count) private view
        returns(InstRev[] memory results)
    { unchecked {
        // Calculate results length
        // iBegin += FIRST_INDEX; This does not occur here as `iBegin` refers to indexes, not values
        uint resultsLen = Util.getRangeLen(indexes.length, iBegin, count);
        if (resultsLen == 0) return results;

        // Get results slice, indexes are scattered across the global array
        results = new InstRev[](resultsLen);
        for (uint i = 0; i < resultsLen; ++i) { // Ubound: Caller must page
            results[i] = emap.values[indexes[iBegin + i]];
        }
    } }
}
