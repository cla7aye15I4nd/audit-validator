// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/console.sol';
import '../lib/forge-std/src/Test.sol';
import '../lib/forge-std/src/StdError.sol';

import '../contract/v1_0/LibraryEMAP.sol';
import '../contract/v1_0/LibraryString.sol';

contract EmapUintUintTest is Test {
    EMAP.UintUint private _emap;

    function setUp() public {
        EMAP.UintUint_init(_emap);
    }

    function test_Emap_UU_initialized() public view {
        assertTrue(EMAP.initialized(_emap));
        assertEq(EMAP.length(_emap), 0);
        assertEq(EMAP.getByIndex(_emap, 0), 0);  // Sentinel
    }

    function test_Emap_UU_add_remove() public {
        // Add 3 items
        for (uint i = 1; i <= 3; ++i) {
            uint key = i;
            uint value = i * 100;
            EMAP.addNoCheck(_emap, key, value);
            assertEq(EMAP.length(_emap), i);
            assertEq(EMAP.getByIndex(_emap, i), value);
            assertEq(_emap.indexes[key], i);
        }

        console2.log('Attempt to add 4 items, first 3 already added; Net result: 1 added');
        for (uint i = 1; i <= 4; ++i) {
            uint key = i;
            uint value = i * 100;
            EMAP.addIfNew(_emap, key, value);
            assertEq(EMAP.length(_emap), i <= 3 ? 3 : 4);
            assertEq(EMAP.getByIndex(_emap, i), value);
            assertEq(_emap.indexes[key], i);
        }

        {
            console2.log('Remove key=1');
            uint key = 1;
            assertEq(EMAP.length(_emap), 4);
            EMAP.remove(_emap, key);
            assertEq(EMAP.length(_emap), 3);
            assertEq(EMAP.getByKey(_emap, 1), 0);       // Not found
            assertEq(EMAP.getByKey(_emap, 2), 200);
            assertEq(EMAP.getByKey(_emap, 3), 300);
            assertEq(EMAP.getByKey(_emap, 4), 400);

            assertEq(EMAP.getByIndex(_emap, 0), 0);     // Sentinel value
            assertEq(EMAP.getByIndex(_emap, 1), 400);   // Swapped with last
            assertEq(EMAP.getByIndex(_emap, 2), 200);
            assertEq(EMAP.getByIndex(_emap, 3), 300);
        }

        {
            console2.log('Remove key=2');
            uint key = 2;
            EMAP.remove(_emap, key);
            assertEq(EMAP.length(_emap), 2);
            assertEq(EMAP.getByKey(_emap, 1), 0);       // Not found
            assertEq(EMAP.getByKey(_emap, 2), 0);       // Not found
            assertEq(EMAP.getByKey(_emap, 3), 300);
            assertEq(EMAP.getByKey(_emap, 4), 400);

            assertEq(EMAP.getByIndex(_emap, 0), 0);     // Sentinel value
            assertEq(EMAP.getByIndex(_emap, 1), 400);
            assertEq(EMAP.getByIndex(_emap, 2), 300);   // Swapped with last
        }

        console2.log('Only keys(1,3) remain; Add keys(4,5) and ensure all are present');
        EMAP.addIfNew(_emap, 5, 500);
        EMAP.addIfNew(_emap, 6, 600);
        assertEq(EMAP.length(_emap), 4);
        assertEq(EMAP.getByKey(_emap, 3), 300);
        assertEq(EMAP.getByKey(_emap, 4), 400);
        assertEq(EMAP.getByKey(_emap, 5), 500);
        assertEq(EMAP.getByKey(_emap, 6), 600);
        assertEq(EMAP.getByIndex(_emap, 0), 0);     // Sentinel value
        assertEq(EMAP.getByIndex(_emap, 1), 400);
        assertEq(EMAP.getByIndex(_emap, 2), 300);
        assertEq(EMAP.getByIndex(_emap, 3), 500);
        assertEq(EMAP.getByIndex(_emap, 4), 600);

        console2.log('Remove missing key');
        EMAP.remove(_emap, 8);
        assertEq(EMAP.length(_emap), 4);            // No effect

        console2.log('Remove key=3');
        EMAP.remove(_emap, 3);
        assertEq(EMAP.length(_emap), 3);
        assertEq(EMAP.getByKey(_emap, 3), 0);       // Not found
        assertEq(EMAP.getByKey(_emap, 4), 400);
        assertEq(EMAP.getByKey(_emap, 5), 500);
        assertEq(EMAP.getByKey(_emap, 6), 600);
        assertEq(EMAP.getByIndex(_emap, 0), 0);     // Sentinel value
        assertEq(EMAP.getByIndex(_emap, 1), 400);
        assertEq(EMAP.getByIndex(_emap, 2), 600);   // Swapped with last
        assertEq(EMAP.getByIndex(_emap, 3), 500);

        console2.log('Remove key=5');
        EMAP.remove(_emap, 5);
        assertEq(EMAP.length(_emap), 2);
        assertEq(EMAP.getByKey(_emap, 3), 0);       // Not found
        assertEq(EMAP.getByKey(_emap, 4), 400);
        assertEq(EMAP.getByKey(_emap, 5), 0);       // Not found
        assertEq(EMAP.getByKey(_emap, 6), 600);
        assertEq(EMAP.getByIndex(_emap, 0), 0);     // Sentinel value
        assertEq(EMAP.getByIndex(_emap, 1), 400);
        assertEq(EMAP.getByIndex(_emap, 2), 600);

        console2.log('Remove key=4');
        EMAP.remove(_emap, 4);
        assertEq(EMAP.length(_emap), 1);
        assertEq(EMAP.getByKey(_emap, 3), 0);       // Not found
        assertEq(EMAP.getByKey(_emap, 4), 0);       // Not found
        assertEq(EMAP.getByKey(_emap, 5), 0);       // Not found
        assertEq(EMAP.getByKey(_emap, 6), 600);
        assertEq(EMAP.getByIndex(_emap, 0), 0);     // Sentinel value
        assertEq(EMAP.getByIndex(_emap, 1), 600);

        console2.log('Remove key=6');
        EMAP.remove(_emap, 6);
        assertEq(EMAP.length(_emap), 0);
        assertEq(EMAP.getByKey(_emap, 3), 0);       // Not found
        assertEq(EMAP.getByKey(_emap, 4), 0);       // Not found
        assertEq(EMAP.getByKey(_emap, 5), 0);       // Not found
        assertEq(EMAP.getByKey(_emap, 6), 0);       // Not found
        assertEq(EMAP.getByIndex(_emap, 0), 0);     // Sentinel value
    }
}

contract EmapBytes32Bytes32Test is Test {
    EMAP.Bytes32Bytes32 private _emap;

    function setUp() public {
        EMAP.Bytes32Bytes32_init(_emap);
    }

    function test_Emap_BB_initialized() public view {
        assertTrue(EMAP.initialized(_emap));
        assertEq(EMAP.length(_emap), 0);
        assertEq(EMAP.getByIndex(_emap, 0), 0); // Sentinel
    }

    function makeKey(uint i) private pure returns (bytes32) {
        return String.toBytes32Mem(vm.toString(i));
    }

    function test_Emap_BB_add_remove() public {
        // Keys
        bytes32 k1 = makeKey(1);
        bytes32 k2 = makeKey(2);
        bytes32 k3 = makeKey(3);
        bytes32 k4 = makeKey(4);
        bytes32 k5 = makeKey(5);
        bytes32 k6 = makeKey(6);
        bytes32 k7 = makeKey(7);
        bytes32 vEmpty = bytes32(0); // makeKey(0) would be different than bytes32(0)
        bytes32 v100 = makeKey(100);
        bytes32 v200 = makeKey(200);
        bytes32 v300 = makeKey(300);
        bytes32 v400 = makeKey(400);
        bytes32 v500 = makeKey(500);
        bytes32 v600 = makeKey(600);

        // console.log('key', String.toString(k4));

        console2.log('Add 3 items');
        for (uint i = 1; i <= 3; ++i) {
            bytes32 key = makeKey(i);
            bytes32 value = makeKey(i * 100);
            // console.log('key', i, String.toString(key));
            // console.log('value', i, String.toString(value));
            EMAP.addNoCheck(_emap, key, value);
            assertEq(EMAP.length(_emap), i);
            assertEq(EMAP.getByIndex(_emap, i), value);
        }

        console2.log('Attempt to add 4 items, first 3 already added; Net result: 1 added');
        for (uint i = 1; i <= 4; ++i) {
            bytes32 key = makeKey(i);
            bytes32 value = makeKey(i * 100);
            // console.log('key', i, String.toString(key));
            // console.log('value', i, String.toString(value));
            EMAP.addIfNew(_emap, key, value);
            uint len = EMAP.length(_emap);
            assertEq(len, i <= 3 ? 3 : 4);
            assertEq(EMAP.getByIndex(_emap, i), value);
        }

        console2.log('Remove key=1');
        {
            assertEq(EMAP.length(_emap), 4);
            assertEq(EMAP.getByKey(_emap, k1), v100);
            EMAP.remove(_emap, k1);
            assertEq(EMAP.length(_emap), 3);
            assertEq(EMAP.getByKey(_emap, k1), vEmpty);     // Not found
            assertEq(EMAP.getByKey(_emap, k2), v200);
            assertEq(EMAP.getByKey(_emap, k3), v300);
            assertEq(EMAP.getByKey(_emap, k4), v400);

            assertEq(EMAP.getByIndex(_emap, 0), vEmpty);    // Sentinel value
            assertEq(EMAP.getByIndex(_emap, 1), v400);      // Swapped with last
            assertEq(EMAP.getByIndex(_emap, 2), v200);
            assertEq(EMAP.getByIndex(_emap, 3), v300);
        }

        console2.log('Remove key=2');
        {
            EMAP.remove(_emap, k2);
            assertEq(EMAP.length(_emap), 2);
            assertEq(EMAP.getByKey(_emap, k1), vEmpty);     // Not found
            assertEq(EMAP.getByKey(_emap, k2), vEmpty);     // Not found
            assertEq(EMAP.getByKey(_emap, k3), v300);
            assertEq(EMAP.getByKey(_emap, k4), v400);

            assertEq(EMAP.getByIndex(_emap, 0), vEmpty);    // Sentinel value
            assertEq(EMAP.getByIndex(_emap, 1), v400);
            assertEq(EMAP.getByIndex(_emap, 2), v300);      // Swapped with last
        }

        console2.log('Only keys(1,3) remain; Add keys(4,5) and ensure all are present');
        EMAP.addIfNew(_emap, k5, v500);
        EMAP.addIfNew(_emap, k6, v600);
        assertEq(EMAP.length(_emap), 4);
        assertEq(EMAP.getByKey(_emap, k3), v300);
        assertEq(EMAP.getByKey(_emap, k4), v400);
        assertEq(EMAP.getByKey(_emap, k5), v500);
        assertEq(EMAP.getByKey(_emap, k6), v600);
        assertEq(EMAP.getByIndex(_emap, 0), vEmpty);        // Sentinel value
        assertEq(EMAP.getByIndex(_emap, 1), v400);
        assertEq(EMAP.getByIndex(_emap, 2), v300);
        assertEq(EMAP.getByIndex(_emap, 3), v500);
        assertEq(EMAP.getByIndex(_emap, 4), v600);

        console2.log('Remove missing key');
        EMAP.remove(_emap, k7);
        assertEq(EMAP.length(_emap), 4);                    // No effect

        console2.log('Remove key=3');
        EMAP.remove(_emap, k3);
        assertEq(EMAP.length(_emap), 3);
        assertEq(EMAP.getByKey(_emap, k3), vEmpty);         // Not found
        assertEq(EMAP.getByKey(_emap, k4), v400);
        assertEq(EMAP.getByKey(_emap, k5), v500);
        assertEq(EMAP.getByKey(_emap, k6), v600);
        assertEq(EMAP.getByIndex(_emap, 0), vEmpty);        // Sentinel value
        assertEq(EMAP.getByIndex(_emap, 1), v400);
        assertEq(EMAP.getByIndex(_emap, 2), v600);          // Swapped with last
        assertEq(EMAP.getByIndex(_emap, 3), v500);

        console2.log('Remove key=5');
        EMAP.remove(_emap, k5);
        assertEq(EMAP.length(_emap), 2);
        assertEq(EMAP.getByKey(_emap, k3), vEmpty);         // Not found
        assertEq(EMAP.getByKey(_emap, k4), v400);
        assertEq(EMAP.getByKey(_emap, k5), vEmpty);         // Not found
        assertEq(EMAP.getByKey(_emap, k6), v600);
        assertEq(EMAP.getByIndex(_emap, 0), vEmpty);        // Sentinel value
        assertEq(EMAP.getByIndex(_emap, 1), v400);
        assertEq(EMAP.getByIndex(_emap, 2), v600);

        console2.log('Remove key=4');
        EMAP.remove(_emap, k4);
        assertEq(EMAP.length(_emap), 1);
        assertEq(EMAP.getByKey(_emap, k3), vEmpty);         // Not found
        assertEq(EMAP.getByKey(_emap, k4), vEmpty);         // Not found
        assertEq(EMAP.getByKey(_emap, k5), vEmpty);         // Not found
        assertEq(EMAP.getByKey(_emap, k6), v600);
        assertEq(EMAP.getByIndex(_emap, 0), vEmpty);        // Sentinel value
        assertEq(EMAP.getByIndex(_emap, 1), v600);

        console2.log('Remove key=6');
        EMAP.remove(_emap, k6);
        assertEq(EMAP.length(_emap), 0);
        assertEq(EMAP.getByKey(_emap, k3), vEmpty);         // Not found
        assertEq(EMAP.getByKey(_emap, k4), vEmpty);         // Not found
        assertEq(EMAP.getByKey(_emap, k5), vEmpty);         // Not found
        assertEq(EMAP.getByKey(_emap, k6), vEmpty);         // Not found
        assertEq(EMAP.getByIndex(_emap, 0), vEmpty);        // Sentinel value
    }
}
