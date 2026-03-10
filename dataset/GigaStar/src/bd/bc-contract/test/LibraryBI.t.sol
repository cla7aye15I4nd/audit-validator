// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/console.sol';
import '../lib/forge-std/src/Test.sol';
import '../lib/forge-std/src/StdError.sol';

import '../contract/v1_0/LibraryBI.sol';
import '../contract/v1_0/LibraryString.sol';
import '../contract/v1_0/Types.sol';

// Wrapper allows state isolation, calldata params, and call boundry for exception handling
contract Spy_BI_Emap {
    BI.Emap private _emap;
    Vm vm;

    constructor(Vm vm_) {
        BI.Emap_init(_emap);
        vm = vm_;
    }

    function initialized() external view returns(bool) {
        return BI.initialized(_emap);
    }

    function addBoxNoCheck(bytes32 nameKey, BI.BoxInfo memory value) external {
        BI.addBoxNoCheck(_emap, nameKey, value);
    }

    function removeBoxByName(bytes32 nameKey) external {
        BI.removeBoxByName(_emap, nameKey);
    }

    function renameBox(bytes32 oldNameKey, bytes32 newNameKey, string calldata newName) external returns(bool) {
        return BI.renameBox(_emap, oldNameKey, newNameKey, newName);
    }

    function tryGetBoxByAddr(address addr, bool expectFound) external view returns(BI.BoxInfo memory) {
        (bool found, BI.BoxInfo storage value) = BI.tryGetBoxByAddr(_emap, addr);
        vm.assertEq(expectFound, found);
        return value;
    }

    function tryGetBoxByName(bytes32 nameKey, bool expectFound) external view returns(BI.BoxInfo memory) {
        (bool found, BI.BoxInfo storage value) = BI.tryGetBoxByName(_emap, nameKey);
        vm.assertEq(expectFound, found);
        return value;
    }

    function getByIndex(uint index) external view returns(BI.BoxInfo memory) {
        return BI.getByIndex(_emap, index);
    }

    function exists(bytes32 nameKey) external view returns(bool) {
        return BI.exists(_emap, nameKey);
    }

    function length() external view returns(uint) {
        return BI.length(_emap);
    }

    // function dumpState() external view {
    //     uint len = _emap.values.length;
    //     console.log('array.length=', len);
    //     for (uint i = 0; i < len; ++i) {
    //         BI.BoxInfo storage info = _emap.values[i];
    //         console.log('i=', i, 'name=', info.name);
    //     }
    //     console.log('idxByName, key=', nE, ', value=', _emap.idxByName[kE]);
    //     console.log('idxByName, key=', n0, ', value=', _emap.idxByName[k0]);
    //     console.log('idxByName, key=', n1, ', value=', _emap.idxByName[k1]);
    //     console.log('idxByName, key=', n2, ', value=', _emap.idxByName[k2]);
    //     console.log('idxByAddr, key=', aE, ', value=', _emap.idxByAddr[aE]);
    //     console.log('idxByAddr, key=', a0, ', value=', _emap.idxByAddr[a0]);
    //     console.log('idxByAddr, key=', a1, ', value=', _emap.idxByAddr[a1]);
    //     console.log('idxByAddr, key=', a2, ', value=', _emap.idxByAddr[a2]);
    // }
}

contract BI_Emap_Test is Test {

    // Init vars for test
    string constant nE = '';                // Name empty
    string constant n0 = 'ABC.0';           // Names
    string constant n1 = 'ABC.1';
    string constant n2 = 'ABC.2';
    string constant n3 = 'ABC.3';

    bytes32 kE;                             // Name Key empty
    bytes32 k0 = String.toBytes32Mem(n0);   // Name Keys
    bytes32 k1 = String.toBytes32Mem(n1);
    bytes32 k2 = String.toBytes32Mem(n2);
    bytes32 k3 = String.toBytes32Mem(n3);

    address constant aE = AddrZero;
    address constant a0 = address(10);      // Addresses
    address constant a1 = address(11);
    address constant a2 = address(12);

    BI.BoxInfo bE;
    BI.BoxInfo b0 = BI.BoxInfo({boxProxy: a0, nameKey: String.toBytes32Mem(n0), name: n0, version: 1, __gap: Util.gap5()});
    BI.BoxInfo b1 = BI.BoxInfo({boxProxy: a1, nameKey: String.toBytes32Mem(n1), name: n1, version: 1, __gap: Util.gap5()});
    BI.BoxInfo b2 = BI.BoxInfo({boxProxy: a2, nameKey: String.toBytes32Mem(n2), name: n2, version: 1, __gap: Util.gap5()});

    function setUp() public {
    }

    function test_BI_emap_initialized() public {
        Spy_BI_Emap spy = new Spy_BI_Emap(vm);
        assertTrue(spy.initialized());
        assertEq(spy.length(), 0);
        assertEq(spy.getByIndex(0).version, 0);  // Sentinel
    }

    function verifyByKey(Spy_BI_Emap spy, bool has0, bool has1, bool has2) internal view {
        // _dumpState(emap);

        // Verify by address
        assertEq(spy.tryGetBoxByAddr(aE, false).name, nE, 'aE');  // Sentinel value
        assertEq(spy.tryGetBoxByAddr(a0, has0).name, has0 ? n0 : nE, 'a0');
        assertEq(spy.tryGetBoxByAddr(a1, has1).name, has1 ? n1 : nE, 'a1');
        assertEq(spy.tryGetBoxByAddr(a2, has2).name, has2 ? n2 : nE, 'a2');

        // Verify by name
        assertEq(spy.tryGetBoxByName(kE, false).name, nE, 'nE');  // Sentinel value
        assertEq(spy.tryGetBoxByName(k0, has0).name, has0 ? n0 : nE, 'n0');
        assertEq(spy.tryGetBoxByName(k1, has1).name, has1 ? n1 : nE, 'n1');
        assertEq(spy.tryGetBoxByName(k2, has2).name, has2 ? n2 : nE, 'n2');
    }

    function test_BI_emap_add_remove() public {
        Spy_BI_Emap spy = new Spy_BI_Emap(vm);

        console2.log('Add 3 items');
        spy.addBoxNoCheck(k0, b0);
        verifyByKey(spy, true, false, false);
        spy.addBoxNoCheck(k1, b1);
        verifyByKey(spy, true, true, false);
        spy.addBoxNoCheck(k2, b2);
        assertEq(spy.length(), 3);
        verifyByKey(spy, true, true, true);
        assertEq(spy.getByIndex(0).name, nE, 'index 0');
        assertEq(spy.getByIndex(1).name, n0, 'index 0');
        assertEq(spy.getByIndex(2).name, n1, 'index 0');
        assertEq(spy.getByIndex(3).name, n2, 'index 0');

        {
            console2.log('Remove key 0');
            assertEq(spy.length(), 3, 'length');
            // console.log('removeBoxByName: ', n0);
            spy.removeBoxByName(k0);
            assertEq(spy.length(), 2, 'length');
            verifyByKey(spy, false, true, true);
            assertEq(spy.getByIndex(0).name, nE, 'index 0'); // Sentinel value
            assertEq(spy.getByIndex(1).name, n2, 'index 1'); // Swapped with last
            assertEq(spy.getByIndex(2).name, n1, 'index 2');
        }

        {
            console2.log('Rename n1 -> n3 -> n1');
            spy.renameBox(k1, k3, n3);
            assertEq(spy.tryGetBoxByAddr(a1, true).name, n3, 'a3');
            assertEq(spy.tryGetBoxByName(k3, true).name, n3, 'n3');

            spy.renameBox(k3, k1, n1);
            assertEq(spy.tryGetBoxByAddr(a1, true).name, n1, 'a1');
            assertEq(spy.tryGetBoxByName(k1, true).name, n1, 'n1');
        }

        {
            console2.log('Remove key n1');
            assertEq(spy.length(), 2, 'length');
            // console.log('removeBoxByName: ', n1);
            spy.removeBoxByName(k1);
            assertEq(spy.length(), 1, 'length');
            verifyByKey(spy, false, false, true);
            assertEq(spy.getByIndex(0).name, nE, 'index 0'); // Sentinel value
            assertEq(spy.getByIndex(1).name, n2, 'index 1');
        }

        {
            console2.log('Remove key n2');
            assertEq(spy.length(), 1, 'length');
            // console.log('removeBoxByName: ', n1);
            spy.removeBoxByName(k2);
            assertEq(spy.length(), 0, 'length');
            verifyByKey(spy, false, false, false);
            assertEq(spy.getByIndex(0).name, nE, 'index 0'); // Sentinel value
        }
    }
}
