// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/console.sol';
import '../lib/forge-std/src/Test.sol';
import '../lib/forge-std/src/StdError.sol';

import '../contract/v1_0/LibraryOI.sol';
import '../contract/v1_0/LibraryString.sol';

contract OI_OwnSnap_Test is Test {
    OI.OwnSnap _os;

    uint constant revE = 0;             // Revenue empty
    uint constant rev1 =  1_250_000;    // Revenue: $1.25 w/ 6 decimal offset
    uint constant rev2 =  5_000_000;
    uint constant rev3 = 20_000_000;

    uint64 constant qtyE = 0;
    uint64 constant qty1 = 1;
    uint64 constant qty2 = 4;
    uint64 constant qty3 = 16;

    UUID constant eidE = UUID.wrap(0x00000000000000000000000000000000); // External ID empty: 0x prefix + 32 hex digits
    UUID constant eid1 = UUID.wrap(0x00000000000000000000000000000001); // External IDs
    UUID constant eid2 = UUID.wrap(0x00000000000000000000000000000002);
    UUID constant eid3 = UUID.wrap(0x00000000000000000000000000000003);

    OI.OwnInfo ownE;                                                    // OwnInfo empty
    OI.OwnInfo own1 = OI.OwnInfo({revenue: rev1, qty: qty1, eid: eid1});// OwnInfos
    OI.OwnInfo own2 = OI.OwnInfo({revenue: rev2, qty: qty2, eid: eid2});
    OI.OwnInfo own3 = OI.OwnInfo({revenue: rev3, qty: qty3, eid: eid3});

    function setUp() public {
        OI.OwnSnap_init(_os);
    }

    function test_OI_OwnSnap_initialized() public view {
        assertTrue(OI.initialized(_os));
        assertEq(OI.ownersLen(_os), 0, 'length');
    }

    function _checkOwnSnapAtIndex(uint i, OI.OwnInfo storage expect) internal view {
        _checkOwnSnapAtIndex(i, expect, 1);
    }

    function _checkOwnSnapAtIndex(uint i, OI.OwnInfo storage expect, uint factor) internal view {
        OI.OwnInfo storage actual = _os.owners[i];
        assertEq(UUID.unwrap(actual.eid), UUID.unwrap(expect.eid), 'eid');
        assertEq(actual.qty, expect.qty * factor, 'qty');
        assertEq(actual.revenue, expect.revenue * factor, 'revenue');
    }

    function test_OI_OwnSnap_addOwnerToSnapshot() public {
        // Initial state
        assertEq(OI.ownersLen(_os), 0);
        _checkOwnSnapAtIndex(0, ownE);

        // Add new owner 1
        OI.addOwnerToSnapshot(_os, own1);
        assertEq(OI.ownersLen(_os), 1, 'after owner 1');
        _checkOwnSnapAtIndex(1, own1);

        // Add new owner 2
        OI.addOwnerToSnapshot(_os, own2);
        assertEq(OI.ownersLen(_os), 2, 'after owner 2');
        _checkOwnSnapAtIndex(2, own2);

        // Add new owner 3
        OI.addOwnerToSnapshot(_os, own3);
        assertEq(OI.ownersLen(_os), 3, 'after owner 3');
        _checkOwnSnapAtIndex(3, own3);

        // Add to existing owner 3
        OI.addOwnerToSnapshot(_os, own3);
        assertEq(OI.ownersLen(_os), 3, 'after owner 3 again');
        _checkOwnSnapAtIndex(3, own3, 2);
    }
}

contract OI_Emap_Test is Test {
    OI.Emap _emap;
    OI.OwnSnapPool _pool;

    // Init vars for test
    string constant nE = '';                    // Name empty
    string constant n1 = 'ABC.1.';              // Names
    string constant n2 = 'ABC.2.';
    string constant n3 = 'ABC.3.';
    string constant n4 = 'ABC.4.';

    bytes32 constant kE = bytes32(0);             // Key empty
    bytes32 k1 = String.toBytes32Mem(n1);     // Keys
    bytes32 k2 = String.toBytes32Mem(n2);
    bytes32 k3 = String.toBytes32Mem(n3);
    bytes32 k4 = String.toBytes32Mem(n4);

    uint constant edE = 0;                      // Earn Date Empty
    uint constant ed1 = 20260101;               // Earn Dates
    uint constant ed2 = 20260201;
    uint constant ed3 = 20260301;
    uint constant ed4 = 20260401;

    uint constant poolIdE = 0;                  // Pool ID empty
    uint constant poolId1 = 1;                  // Pool IDs
    uint constant poolId2 = 2;
    uint constant poolId3 = 3;
    uint constant poolId4 = 4;
    uint constant poolId5 = 5;
    uint constant poolId6 = 6;

    uint immutable uploadedAt = block.timestamp;
    uint immutable executedAt = block.timestamp + 1;

    function setUp() public {
        OI.Emap_init(_emap);
    }

    function test_OI_emap_initialized() public view {
        assertTrue(OI.initialized(_emap));
        assertEq(OI.poolLen(_emap), 0, 'length');
    }

    function _makePoolRef(uint poolId, bytes32 instNameKey, uint earnDate) internal pure
        returns(OI.PoolRef memory pr)
    {
        pr.poolId = poolId;
        pr.instNameKey = instNameKey;
        pr.earnDate = earnDate;
    }

    function _makeOwnInfo(uint revenue, uint64 qty, UUID eid) internal pure returns(OI.OwnInfo memory oi) {
        oi.revenue = revenue;
        oi.qty = qty;
        oi.eid = eid;
    }

    function test_OI_emap_add_and_upsert() public {
        assertTrue(OI.initialized(_emap));
        assertEq(OI.poolLen(_emap), 0, 'poolLen');
        assertEq(OI.ownSnapsLen(_emap), 0, 'ownSnapsLen');

        console2.log('Add PoolId w/ no underlying pool entry');
        OI.addPoolIdNoCheck(_emap, k1, ed1, poolId1);
        assertEq(OI.poolLen(_emap), 1, 'poolLen');
        _checkPoolRef(1, k1, ed1, poolId1);
        assertTrue(OI.exists(_emap, k1, ed1));
        assertEq(OI.getPoolId(_emap, k1, ed1), poolId1);

        console2.log("Upsert: Update existing index's poolId via upsert");
        _upsertPoolId(k1, ed1, poolId2, 1, 1);

        console2.log('Upsert: Insert a new poolId into index poolId');
        _upsertPoolId(k1, ed2, poolId3, 2, 2);

        console2.log('Upsert: Insert a new poolId into index poolId');
        _upsertPoolId(k2, ed2, poolId4, 3, 3);
    }

    function _checkPoolRef(uint index, bytes32 instNameKey, uint earnDate, uint poolId) internal view {
        OI.PoolRef storage actual = _emap.poolRefs[index];
        assertGe(OI.poolLen(_emap), index, 'poolRefs length');
        assertEq(actual.instNameKey, instNameKey, 'instNameKey');
        assertEq(actual.earnDate, earnDate, 'earnDate');
        assertEq(actual.poolId, poolId, 'poolId');
    }

    function _upsertPoolId(bytes32 instNameKey, uint earnDate, uint poolId, uint expectLen, uint index) internal {
        OI.upsertPoolId(_emap, instNameKey, earnDate, poolId);
        assertEq(OI.poolLen(_emap), expectLen, 'poolLen');
        _checkPoolRef(index, instNameKey, earnDate, poolId);
        assertTrue(OI.exists(_emap, instNameKey, earnDate));
        assertEq(OI.getPoolId(_emap, instNameKey, earnDate), poolId);
    }

    struct Key {
        uint poolId;
        string instName;        // Instrument name, string version of `instNameKey`, max len 32 chars
        bytes32 instNameKey;
        uint earnDate;
    }

    function makeKey(uint poolId, bytes32 instNameKey, uint earnDate) internal pure returns(Key memory) {
        string memory instName = String.toString(instNameKey);
        return Key({poolId: poolId, instName: instName, instNameKey: instNameKey, earnDate: earnDate});
    }

    function verifyByIndex(uint expectLen, Key memory key1, Key memory key2, Key memory key3,
        Key memory key4, Key memory key5, Key memory key6) internal view
    {
        assertEq(OI.poolLen(_emap), expectLen, 'poolLen');
        assertEq(_emap.poolRefs.length, expectLen + 1, 'poolRefs.length');

        Key memory keyE = makeKey(0, kE, edE);
        assertEq(_emap.poolRefs[0].poolId, keyE.poolId, 'key empty poolId');
        // assertEq(_emap.poolRefs[0].instName, keyE.instName, 'key empty name');
        assertEq(_emap.poolRefs[0].instNameKey, keyE.instNameKey, 'key empty name');
        assertEq(_emap.poolRefs[0].earnDate, keyE.earnDate, 'key empty date');

        if (expectLen == 0) return;
        assertEq(_emap.poolRefs[1].poolId, key1.poolId, 'key1 poolId');
        // assertEq(_emap.poolRefs[1].instName, key1.instName, 'key1 name');
        assertEq(_emap.poolRefs[1].instNameKey, key1.instNameKey, 'key1 nameKey');
        assertEq(_emap.poolRefs[1].earnDate, key1.earnDate, 'key1 date');

        if (expectLen == 1) return;
        assertEq(_emap.poolRefs[2].poolId, key2.poolId, 'key2 poolId');
        // assertEq(_emap.poolRefs[2].instName, key2.instName, 'key2 name');
        assertEq(_emap.poolRefs[2].instNameKey, key2.instNameKey, 'key2 nameKey');
        assertEq(_emap.poolRefs[2].earnDate, key2.earnDate, 'key2 date');

        if (expectLen == 2) return;
        assertEq(_emap.poolRefs[3].poolId, key3.poolId, 'key3 poolId');
        // assertEq(_emap.poolRefs[3].instName, key3.instName, 'key3 name');
        assertEq(_emap.poolRefs[3].instNameKey, key3.instNameKey, 'key3 nameKey');
        assertEq(_emap.poolRefs[3].earnDate, key3.earnDate, 'key3 date');

        if (expectLen == 3) return;
        assertEq(_emap.poolRefs[4].poolId, key4.poolId, 'key4 poolId');
        // assertEq(_emap.poolRefs[4].instName, key4.instName, 'key4 name');
        assertEq(_emap.poolRefs[4].instNameKey, key4.instNameKey, 'key4 nameKey');
        assertEq(_emap.poolRefs[4].earnDate, key4.earnDate, 'key4 date');

        if (expectLen == 4) return;
        assertEq(_emap.poolRefs[5].poolId, key5.poolId, 'key5 poolId');
        // assertEq(_emap.poolRefs[5].instName, key5.instName, 'key5 name');
        assertEq(_emap.poolRefs[5].instNameKey, key5.instNameKey, 'key5 nameKey');
        assertEq(_emap.poolRefs[5].earnDate, key5.earnDate, 'key5 date');

        if (expectLen == 5) return;
        assertEq(_emap.poolRefs[6].poolId, key6.poolId, 'key6 poolId');
        // assertEq(_emap.poolRefs[6].instName, key6.instName, 'key6 name');
        assertEq(_emap.poolRefs[6].instNameKey, key6.instNameKey, 'key6 nameKey');
        assertEq(_emap.poolRefs[6].earnDate, key6.earnDate, 'key6 date');
    }

    function test_OI_emap_remove() public {
        Key memory keyE = makeKey(0, kE, edE);
        Key memory key1 = makeKey(1, k1, ed1);
        Key memory key2 = makeKey(2, k1, ed2);
        Key memory key3 = makeKey(3, k2, ed2);
        Key memory key4 = makeKey(4, k1, ed3);
        Key memory key5 = makeKey(5, k2, ed3);
        Key memory key6 = makeKey(6, k3, ed3);

        OI.addPoolIdNoCheck(_emap, key1.instNameKey, key1.earnDate, key1.poolId);
        OI.addPoolIdNoCheck(_emap, key2.instNameKey, key2.earnDate, key2.poolId);
        OI.addPoolIdNoCheck(_emap, key3.instNameKey, key3.earnDate, key3.poolId);
        OI.addPoolIdNoCheck(_emap, key4.instNameKey, key4.earnDate, key4.poolId);
        OI.addPoolIdNoCheck(_emap, key5.instNameKey, key5.earnDate, key5.poolId);
        OI.addPoolIdNoCheck(_emap, key6.instNameKey, key6.earnDate, key6.poolId);
        assertEq(OI.poolLen(_emap), 6, 'poolLen initial');

        // Remove keys not found - no effect
        OI.remove(_emap, kE, edE);
        OI.remove(_emap, k1, edE);
        OI.remove(_emap, kE, ed1);
        OI.remove(_emap, k3, ed1);
        OI.remove(_emap, k1, ed4);
        assertEq(OI.poolLen(_emap), 6, 'poolLen post noops');
        verifyByIndex(6, key1, key2, key3, key4, key5, key6);

        // Remove key3 - Swap(key3, key6)
        OI.remove(_emap, key3.instNameKey, key3.earnDate);
        verifyByIndex(5, key1, key2, key6, key4, key5, keyE);

        // Remove key3 - Not found; no effect
        OI.remove(_emap, key3.instNameKey, key3.earnDate);
        verifyByIndex(5, key1, key2, key6, key4, key5, keyE);

        // Remove key1 - Swap(key1, key5)
        OI.remove(_emap, key1.instNameKey, key1.earnDate);
        verifyByIndex(4, key5, key2, key6, key4, keyE, keyE);

        // Remove key4 - No swap
        OI.remove(_emap, key4.instNameKey, key4.earnDate);
        verifyByIndex(3, key5, key2, key6, keyE, keyE, keyE);

        // Remove key2 - Swap(key2, key6)
        OI.remove(_emap, key2.instNameKey, key2.earnDate);
        verifyByIndex(2, key5, key6, keyE, keyE, keyE, keyE);

        // Remove key5 - Swap(key5, key6)
        OI.remove(_emap, key5.instNameKey, key5.earnDate);
        verifyByIndex(1, key6, keyE, keyE, keyE, keyE, keyE);

        // Remove key6 - No swap
        OI.remove(_emap, key6.instNameKey, key6.earnDate);
        verifyByIndex(0, key6, keyE, keyE, keyE, keyE, keyE);
    }

    function test_OI_getSnapshot() public {
        assertEq(OI.poolLen(_emap), 0, 'poolLen initial');
        Key memory key1 = makeKey(1, k1, ed1);
        Key memory key2 = makeKey(2, k1, ed2);

        // Try to get the OwnSnap from the pool - Not created, does not exist
        OI.OwnSnap storage os = OI.tryGetOwnSnap(_emap, key1.instNameKey, key1.earnDate, _pool);
        assertFalse(OI.initialized(os));
        assertEq(OI.ownersLen(os), 0, 'ownersLen');
        assertEq(OI.poolLen(_emap), 0, 'poolLen');

        // Get the OwnSnap from the pool - Created
        os = OI.getSnapshot(_emap, key1.instNameKey, key1.earnDate, _pool);
        assertTrue(OI.initialized(os));
        assertEq(OI.ownersLen(os), 0, 'ownersLen');
        assertEq(OI.poolLen(_emap), 1, 'poolLen');
        assertEq(_emap.poolRefs[1].poolId, key1.poolId, 'key1 poolId');
        assertEq(_emap.poolRefs[1].instNameKey, key1.instNameKey, 'key1 name');
        assertEq(_emap.poolRefs[1].earnDate, key1.earnDate, 'key1 date');

        // Add poolId
        OI.addPoolIdNoCheck(_emap, key2.instNameKey, key2.earnDate, key2.poolId);

        // Get the OwnSnap from the pool - Created
        os = OI.getSnapshot(_emap, key2.instNameKey, key2.earnDate, _pool);
        assertTrue(OI.initialized(os));
        assertEq(OI.ownersLen(os), 0, 'ownersLen');
        assertEq(OI.poolLen(_emap), 2, 'poolLen');
        assertEq(_emap.poolRefs[2].poolId, key2.poolId, 'key2 poolId');
        assertEq(_emap.poolRefs[2].instNameKey, key2.instNameKey, 'key2 name');
        assertEq(_emap.poolRefs[2].earnDate, key2.earnDate, 'key2 date');
    }
}
