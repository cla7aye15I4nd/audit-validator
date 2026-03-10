// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './LibraryUtil.sol';
import './Types.sol';

/// @dev Owner Info Library
/// @custom:api public
// prettier-ignore
library OI { // Owner Info
    uint internal constant SENTINEL_INDEX = 0; // Index 0 and not found in map both resolve to no item
    uint internal constant SentinelValue = 0;
    uint internal constant FIRST_INDEX = 1;    // First actual item begins after the sentinel

    // ───────────────────────────────────────
    // Structs (See MEM_LAYOUT)
    // ───────────────────────────────────────

    /// @dev An OwnSnap pool to allow pass-by-ref to reduce txs
    /// - Each poolId is essentially a pointer where the `ownSnaps` pool is the heap
    /// - `ownSnaps` is where `OwnSnap` instances live for low cost copies from proposal during execution
    /// - Upgradability provides backwards compatibility in storage
    struct OwnSnapPool {
        uint poolId;                         /// Seed for the next ID
        mapping(uint => OwnSnap) ownSnaps;   /// Key: poolId; OwnSnap (pending and complete)

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev `eid` is a stable id that decouples an owner and wallet. This allows:
    /// - Investor with no wallet (on-chain asset custody)
    /// - Investor wallet update (eid avoids an O(N) update of existing records)
    /// - Dynamic wallets for off-ramping
    /// - Upgradability skipped for performance (fast-loop storage), though not all bytes are used
    struct OwnInfo { //  Slot, Bytes: Description
        uint revenue;   /// 0,    all: Owner's revenue (qty x unit revenue)
        uint64 qty;     /// 1,   0-15: Intrument units owned (in token units with decimals offset)
        UUID eid;       /// 1,  16-23: Owner's external id
    }

    /// @dev Ownership Snapshot: Contains the owners for an instrument's earn date
    /// - Does not contain instName and earnDate as external enumeration requires both fields
    /// - Upgradability provides backwards compatibility in storage
    struct OwnSnap {
        uint totalRevenue;              /// Total revenue across owners
        OwnInfo[] owners;               /// List of owners of an instrument on an earn date
        mapping(UUID => uint) idxEid;   /// Key: Owner's External Id; Index of `owners`
        uint uploadedAt;                /// block.timestamp when fully uploaded
        uint executedAt;                /// block.timestamp when fully executed

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Acts as an object reference with a key and object id in a resource pool
    /// - Upgradability provides backwards compatibility in storage
    struct PoolRef {
        uint poolId;            /// Key into the `ownSnapPool` which maps the key to an `OwnSnap`
        bytes32 instNameKey;    /// Instrument name; for O(1) remove
        uint earnDate;          /// Earn date; for O(1) remove

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev An enumerable map from (InstName,EarnDate) => poolId; where poolId is like a reference to OwnSnap
    /// - Allows: OwnSnapPool.ownSnaps[poolId] => OwnSnap
    /// - Upgradability provides backwards compatibility in storage
    struct Emap {
        PoolRef[] poolRefs; /// Allows O(1) find/remove in this map and pool
        mapping(bytes32 => mapping(uint => uint)) idxNameDate;  /// Keys: InstName, EarnDate; `poolRefs` index

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    // ───────────────────────────────────────
    // OwnSnap Functions
    // ───────────────────────────────────────

    /// @dev Initialize an `OwnSnap`
    function OwnSnap_init(OwnSnap storage os) internal {
        os.owners.push(); // Empty sentinel item, see `SENTINEL_INDEX`
    }

    /// @dev Returns whether the map was initialized
    function initialized(OwnSnap storage os) internal view returns(bool) {
        return os.owners.length >= FIRST_INDEX;
    }

    /// @dev Get the number of owners in an ownership snapshot (ie the owners for an instrument's earn date)
    function ownersLen(OwnSnap storage ownSnap) internal view returns(uint len) {
        len = ownSnap.owners.length;
        return len >= FIRST_INDEX ? len - FIRST_INDEX : 0;
    }

    /// @dev Get OwnInfo at an index
    function getByIndex(OwnSnap storage ownSnap, uint index) internal view returns(OwnInfo storage) {
        return ownSnap.owners[index + FIRST_INDEX];
    }

    /// @dev Add an owner to a snapshot and index it, if found then aggrengate qty and revenue
    function addOwnerToSnapshot(OwnSnap storage ownSnap, OwnInfo memory owner) internal {
        uint i = ownSnap.idxEid[owner.eid];
        if (i == SENTINEL_INDEX) { // then new item
            ownSnap.idxEid[owner.eid] = ownSnap.owners.length; // Key => index of new item
            ownSnap.owners.push(owner);                        // Add item
            return;
        }
        // Aggregate with existing record
        OwnInfo storage oi = ownSnap.owners[i];
        oi.qty += owner.qty;
        oi.revenue += owner.revenue;
    }

    // ───────────────────────────────────────
    // Emap Functions
    // ───────────────────────────────────────

    /// @dev Initialize an `Emap`,
    function Emap_init(Emap storage emap) internal {
        emap.poolRefs.push(); // Empty sentinel item, see `SENTINEL_INDEX`
    }

    /// @dev Returns whether the map was initialized
    function initialized(Emap storage emap) internal view returns(bool) {
        return emap.poolRefs.length >= FIRST_INDEX;
    }

    /// @dev An `Emap` accessor to get the pool length
    function poolLen(Emap storage emap) internal view returns(uint len) {
        len = emap.poolRefs.length;
        return len >= FIRST_INDEX ? len - FIRST_INDEX : 0;
    }

    /// @dev Get the number of owner snapshots
    function ownSnapsLen(Emap storage emap) internal view returns(uint len) { len = poolLen(emap); }

    // `addOwnInfo` would require paging so integrated into the external function `addOwnersToRegistry`

    /// @dev Add a reference (poolId) to an `OwnSnap` that was previously constructed
    /// - This 'NoCheck' function reqires the caller to ensure the item does not exist, saves a storage lookup
    function addPoolIdNoCheck(Emap storage emap, bytes32 instNameKey, uint earnDate, uint poolId) internal {
        // PoolRef[] storage poolRefs = emap.poolRefs;
        // uint i = poolRefs.length;
        emap.idxNameDate[instNameKey][earnDate] = emap.poolRefs.length; // Associate new PoolRef index in map

        // Add to array
        emap.poolRefs.push(
            PoolRef({ poolId: poolId, instNameKey: instNameKey, earnDate: earnDate, __gap: Util.gap5() }));

        // PoolRef storage pr = poolRefs[i];
        // pr.poolId = poolId;
        // pr.instNameKey = instNameKey;
        // pr.earnDate = earnDate;
    }

    /// @dev Add a reference (poolId) to an `OwnSnap` that was previously constructed
    /// - This 'NoCheck' function reqires the caller to ensure the item does not exist, saves a storage lookup
    function upsertPoolId(Emap storage emap, bytes32 instNameKey, uint earnDate, uint poolId) internal {
        // PoolRef[] storage poolRefs = emap.poolRefs;
        uint i = emap.idxNameDate[instNameKey][earnDate];
        if (i == SENTINEL_INDEX) { // then not found
            addPoolIdNoCheck(emap, instNameKey, earnDate, poolId);
        } else {
            emap.poolRefs[i].poolId = poolId; // Overwrite reference; No need to remove old resource and too expensive
        }
    }

    /// @dev Remove OwnSnap reference from emap, this is a shallow remove (drop pool id) to avoid a multi-tx action
    function remove(Emap storage emap, bytes32 instNameKey, uint earnDate) internal {
        uint i = emap.idxNameDate[instNameKey][earnDate];
        if (i == SENTINEL_INDEX) return; // Not found

        // Remove from array and map via swap-n-pop for stable array indexes (except the moved item)
        PoolRef[] storage poolRefs = emap.poolRefs;
        uint last = poolRefs.length - 1;
        if (i != last) { // then move item
            poolRefs[i] = poolRefs[poolRefs.length - 1];             // Move: Ignores case when i == last
            PoolRef storage moved = poolRefs[i];                     // Get moved item for keys
            emap.idxNameDate[moved.instNameKey][moved.earnDate] = i; // Update index for moved item
        }
        poolRefs.pop();                                              // Pop: last=0; --length; (remove item)
        delete emap.idxNameDate[instNameKey][earnDate];              // Delete index for removed item
    }

    /// @dev Get an OwnSnap from the pool; do not create
    function exists(Emap storage emap, bytes32 instNameKey, uint earnDate) internal view returns(bool) {
        return emap.idxNameDate[instNameKey][earnDate] != SENTINEL_INDEX;
    }

    /// @dev Get a poolId for the given key; `SentinelValue` if not found
    function getPoolId(Emap storage emap, bytes32 instNameKey, uint earnDate) internal view returns(uint) {
        uint i = emap.idxNameDate[instNameKey][earnDate];
        if (i == SENTINEL_INDEX) return SentinelValue;
        return emap.poolRefs[i].poolId;
    }

    // ───────────────────────────────────────
    // OwnSnapPool Functions
    // ───────────────────────────────────────

    /// @dev Get an OwnSnap from the pool; create if not found
    function getSnapshot(Emap storage emap, bytes32 instNameKey, uint earnDate, OwnSnapPool storage pool)
        internal returns(OwnSnap storage ownSnap)
    {
        uint iPoolRefs = emap.idxNameDate[instNameKey][earnDate];
        uint poolId;
        if (iPoolRefs == SentinelValue) { // Not found
            // Create new: While related to the request/proposal, the lifetime of the snapshot is in a contract pool
            // to allow copy-by-ref during execute rather than an expensive copy/reindex. Pool Id is basically a ref
            poolId = ++pool.poolId;
            addPoolIdNoCheck(emap, instNameKey, earnDate, poolId);
        } else { // Found existing
            poolId = emap.poolRefs[iPoolRefs].poolId;
        }
        ownSnap = pool.ownSnaps[poolId];
        if (!initialized(ownSnap)) OwnSnap_init(ownSnap);
    }

    /// @dev Get an OwnSnap from the pool; empty if not found
    function tryGetOwnSnap(Emap storage emap, bytes32 instNameKey, uint earnDate, OwnSnapPool storage pool)
        internal view returns(OwnSnap storage ownSnap)
    {
        uint iPoolRefs = emap.idxNameDate[instNameKey][earnDate];
        return pool.ownSnaps[emap.poolRefs[iPoolRefs].poolId]; // Sentinel value if not found
    }
}
