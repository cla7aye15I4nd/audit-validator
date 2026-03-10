// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/console.sol';
import '../lib/forge-std/src/Test.sol';
import '../lib/forge-std/src/StdError.sol';

import '../contract/v1_0/LibraryIR.sol';
import '../contract/v1_0/LibraryString.sol';

import './LibraryTest.sol';

// Helper to ensure reverts are at a lower level in the callstack to allow them to be handled
contract IR_Emap_Spy {
    IR.Emap private _emap;
    IR.InstRev irStore;
    Vm vm;

    // // Init vars for test
    // bytes32 constant nE = '';                    // Name empty
    // bytes32 constant n1 = 'ABC.11';              // Names
    // bytes32 constant n2 = 'ABC.12';
    // bytes32 constant n3 = 'ABC.13';
    // bytes32 constant n4 = 'ABC.14';

    // bytes32 constant kE = bytes32(0);             // Key empty
    // bytes32 k1 = n1;     // Keys
    // bytes32 k2 = n2;
    // bytes32 k3 = n3;
    // bytes32 k4 = n4;

    // uint constant edE = 0;                      // Earn Date Empty
    // uint constant ed1 = 20260101;               // Earn Dates
    // uint constant ed2 = 20260201;
    // uint constant ed3 = 20260301;
    // uint constant ed4 = 20260401;

    constructor(Vm vm_) {
        vm = vm_;
        IR.Emap_init(_emap);
    }

    function exists(bytes32 instName, uint earnDate) external view returns(bool) {
        return IR.exists(_emap, instName, earnDate);
    }

    function length() external view returns(uint) { return IR.length(_emap); }

    function addInstRevCd(IR.InstRev calldata ir, bytes32 instNameKey, bool checkNew) external {
        IR.addFromCd(_emap, ir, instNameKey, checkNew);
    }

    function addInstRevStore(IR.InstRev memory irMem, bytes32 instNameKey, bool checkNew) external {
        irStore = irMem; // Convert param from memory to storage
        console2.log('addInstRevStore, name', irStore.instName, ', key', String.toString(instNameKey));
        IR.addFromStore(_emap, irStore, instNameKey, checkNew);
    }

    function remove(bytes32 instName, uint earnDate) external {
        IR.remove(_emap, instName, earnDate);
    }

    function getByIndex(uint index) external view returns(IR.InstRev memory) {
        return IR.getByIndex(_emap, index);
    }

    function getInstRevsLen(bytes32 instName, uint earnDate) external view returns(uint) {
        return IR.getInstRevsLen(_emap, instName, earnDate);
    }

    function getInstRevs(bytes32 instName, uint earnDate, uint iBegin, uint count)
        external view returns(IR.InstRev[] memory results)
    {
        return IR.getInstRevs(_emap, instName, earnDate, iBegin, count);
    }

    function _dumpArray(bytes32 name, uint[] memory arr) private view {
        uint len = arr.length;
        console.log(T.concat(String.toString(name), ': array.length=', vm.toString(len)));
        for (uint i = 0; i < len; ++i) {
            console.log(T.concat('i:', vm.toString(i), ', value: ', vm.toString(arr[i])));
        }
    }

    // function dumpState() public view {
    //     uint len = _emap.values.length;
    //     console.log('array.length=', len);
    //     for (uint i = 0; i < len; ++i) {
    //         IR.InstRev storage ir = _emap.values[i];
    //         console.log(i, ', InstRev: ', ir.instName, ir.earnDate);
    //     }
    //     console.log('idxName:');
    //     _dumpArray(n1, _emap.idxName[k1]);
    //     _dumpArray(n2, _emap.idxName[k2]);
    //     _dumpArray(n3, _emap.idxName[k3]);

    //     console.log('idxDate:');
    //     _dumpArray(n1, _emap.idxDate[ed1]);
    //     _dumpArray(n2, _emap.idxDate[ed2]);
    //     _dumpArray(n3, _emap.idxDate[ed3]);

    //     console.log('cursors:');
    //     for (uint i = 1; i < len; ++i) {
    //         IR.InstRev storage ir = _emap.values[i];
    //         uint earnDate = ir.earnDate;
    //         IR.Cursor memory cursor = _emap.idxNameDate[ir.instNameKey][earnDate];
    //         // console.log('i=', i, ', iValue=', cursor.iValue);
    //         // console.log('  cursor.iName=', cursor.iName, ', iDate=', cursor.iDate);
    //         // Multiple steps to reduce IR pipeline pressure
    //         string memory p1 = T.concat(ir.instName, vm.toString(earnDate), ', iValue=', vm.toString(cursor.iValue));
    //         string memory p2 = T.concat(', iName=', vm.toString(cursor.iName), ', iDate=', vm.toString(cursor.iDate));
    //         console.log(T.concat(p1, p2));
    //     }
    // }

    function verifyByKey(
        bool has1, IR.InstRev memory ir1,
        bool has2, IR.InstRev memory ir2,
        bool has3, IR.InstRev memory ir3)
        public view
    {
        IR.InstRev memory irE;          // Empty
        _checkValueByKey(false, irE);   // Sentinel value
        _checkValueByKey(has1, ir1);
        _checkValueByKey(has2, ir2);
        _checkValueByKey(has3, ir3);
    }

    function _checkValueByIndex(uint index, bytes32 instNameKey, uint earnDate) public view {
        IR.InstRev storage ir = IR.getByIndex(_emap, index);
        vm.assertEq(ir.instName, String.toString(instNameKey), 'instName');
        vm.assertEq(ir.instNameKey, instNameKey, 'instNameKey');
        vm.assertEq(ir.earnDate, earnDate, 'earnDate');
    }

    function _checkValueByKey(bool hasValue, IR.InstRev memory ir) public view {
        console.log('_checkValueByKey: ', ir.instName, ', ', ir.earnDate);
        uint earnDate = ir.earnDate;
        bytes32 nameExpect = '';
        uint dateExpect = 0;
        if (hasValue) {
            nameExpect = ir.instNameKey;
            dateExpect = earnDate;
        }

        // Find by key
        IR.InstRev storage instRev = IR.getByKey(_emap, ir.instNameKey, earnDate);
        vm.assertEq(instRev.instNameKey, nameExpect, 'via key');
        vm.assertEq(instRev.earnDate, dateExpect, 'via key');
        IR.Cursor storage cursor = _emap.idxNameDate[ir.instNameKey][earnDate];

        if (!hasValue) {
            // Ensure sentinel values
            vm.assertEq(cursor.iValue, 0);
            vm.assertEq(cursor.iName, 0);
            vm.assertEq(cursor.iDate, 0);
            return;
        }

        // Ensure associated by name
        uint[] storage indexes = _emap.idxName[ir.instNameKey];
        vm.assertLt(cursor.iName, indexes.length, 'via idxName');
        uint i = indexes[cursor.iName];
        instRev = _emap.values[i];
        vm.assertEq(instRev.instNameKey, nameExpect, 'via idxName');
        vm.assertEq(instRev.earnDate, dateExpect, 'via idxName');

        // Ensure associated by date
        indexes = _emap.idxDate[earnDate];
        vm.assertLt(cursor.iDate, indexes.length, 'via idxDate');
        i = indexes[cursor.iDate];
        instRev = _emap.values[i];
        vm.assertEq(instRev.instNameKey, nameExpect, 'via idxDate');
        vm.assertEq(instRev.earnDate, dateExpect, 'via idxDate');
    }
}

contract IR_Emap_Test is Test {
    // Init vars for test
    bytes32 constant nE = '';                    // Name empty
    bytes32 constant n1 = 'ABC.11';              // Names
    bytes32 constant n2 = 'ABC.12';
    bytes32 constant n3 = 'ABC.13';
    bytes32 constant n4 = 'ABC.14';

    bytes32 constant kE = bytes32(0);             // Key empty
    bytes32 k1 = n1;     // Keys
    bytes32 k2 = n2;
    bytes32 k3 = n3;
    bytes32 k4 = n4;

    uint constant edE = 0;                      // Earn Date Empty
    uint constant ed1 = 20260101;               // Earn Dates
    uint constant ed2 = 20260201;
    uint constant ed3 = 20260301;
    uint constant ed4 = 20260401;

    IR.InstRev irE;                             // InstRev empty
    IR.InstRev ir1Jan = _makeInstRev(n1, ed1);  // InstRevs
    IR.InstRev ir2Jan = _makeInstRev(n2, ed1);
    IR.InstRev ir3Jan = _makeInstRev(n3, ed1);
    IR.InstRev ir1Feb = _makeInstRev(n1, ed2);
    IR.InstRev ir2Feb = _makeInstRev(n2, ed2);
    IR.InstRev ir3Feb = _makeInstRev(n3, ed2);
    IR.InstRev ir1Mar = _makeInstRev(n1, ed3);
    IR.InstRev ir2Mar = _makeInstRev(n2, ed3);
    IR.InstRev ir3Mar = _makeInstRev(n3, ed3);

    function setUp() public {
    }

    function _makeInstRev(bytes32 instNameKey, uint earnDate) internal pure returns(IR.InstRev memory ir) {
        ir.instNameKey = instNameKey;
        ir.instName = String.toString(instNameKey);
        ir.earnDate = earnDate;
        // Other fields are irrelevant for these tests
    }

    function _addInstRev(IR_Emap_Spy spy, IR.InstRev memory ir) internal {
        _addInstRev(spy, ir, false, false);
    }

    function _addInstRev(IR_Emap_Spy spy, IR.InstRev memory ir, bool checkNew, bool useStoreParam) internal {
        bytes32 instNameKey = String.toBytes32Mem(ir.instName);
        if (checkNew) assertEq(!checkNew, spy.exists(instNameKey, ir.earnDate), 'exists before');
        if (useStoreParam) {
            spy.addInstRevStore(ir, instNameKey, checkNew);
        } else {
            spy.addInstRevCd(ir, instNameKey, checkNew);
        }
        assertTrue(spy.exists(instNameKey, ir.earnDate), 'exists after');
        // spy.dumpState();
    }

    function test_IR_emap_initialized() public {
        IR_Emap_Spy spy = new IR_Emap_Spy(vm);
        assertEq(spy.length(), 0, 'length');
        vm.expectRevert();
        spy.getByIndex(0);
    }

    function test_IR_emap_add_prevent_dups() public {
        IR_Emap_Spy spy = new IR_Emap_Spy(vm);

        // Add InstRev for Jan (3 insts, 1 date)
        spy.addInstRevCd(ir1Jan, String.toBytes32Mem(ir1Jan.instName), true);
        assertEq(spy.length(), 1, 'length before');

        // Add an existing item, prevent duplicate, fail as already exists
        vm.expectRevert(abi.encodeWithSelector(IR.InstRevExists.selector, ir1Jan.instName, ir1Jan.earnDate));
        spy.addInstRevCd(ir1Jan, String.toBytes32Mem(ir1Jan.instName), true);
        assertEq(spy.length(), 1, 'length after');
    }

    function test_IR_emap_add_remove_store() public {
        _do_add_remove(true); // storage
    }

    function test_IR_emap_add_remove_cd() public {
        _do_add_remove(false); // calldata
    }

    function _do_add_remove(bool useStoreParam) private {
        IR_Emap_Spy spy = new IR_Emap_Spy(vm);

        console2.log('Add InstRev for Jan (3 insts, 1 date)');
        _addInstRev(spy, ir1Jan, true, useStoreParam);
        assertEq(spy.length(), 1, 'length');
        _addInstRev(spy, ir2Jan, true, useStoreParam);
        assertEq(spy.length(), 2, 'length');
        _addInstRev(spy, ir3Jan, true, useStoreParam);
        assertEq(spy.length(), 3, 'length');
        spy.verifyByKey(true, ir1Jan, true, ir2Jan, true, ir3Jan);

        console2.log('Add an existing item, allow duplicate, overwrite');
        _addInstRev(spy, ir3Jan, false, useStoreParam);
        assertEq(spy.length(), 3, 'length');
        spy.verifyByKey(true, ir1Jan, true, ir2Jan, true, ir3Jan);

        console2.log('Add InstRev for Feb (3 insts, 1 date)');
        _addInstRev(spy, ir1Feb, true, useStoreParam);
        _addInstRev(spy, ir2Feb, true, useStoreParam);
        _addInstRev(spy, ir3Feb, true, useStoreParam);
        assertEq(spy.length(), 6, 'length');
        spy.verifyByKey(true, ir1Feb, true, ir2Feb, true, ir3Feb);

        console2.log('Add InstRev for Mar (3 insts, 1 date)');
        _addInstRev(spy, ir1Mar, true, useStoreParam);
        _addInstRev(spy, ir2Mar, true, useStoreParam);
        _addInstRev(spy, ir3Mar, true, useStoreParam);
        assertEq(spy.length(), 9, 'length');
        spy.verifyByKey(true, ir1Mar, true, ir2Mar, true, ir3Mar);

        // _dumpState();

        console2.log('Remove InstRev 2 for Feb');
        spy.remove(k2, ir2Feb.earnDate);
        assertEq(spy.length(), 8, 'length');
        // _dumpState();
        spy.verifyByKey(true, ir1Jan, true, ir2Jan, true, ir3Jan);
        spy.verifyByKey(true, ir1Feb, false, ir2Feb, true, ir3Feb);
        spy.verifyByKey(true, ir1Mar, true, ir2Mar, true, ir3Mar);

        console2.log('Remove InstRev 2 for Jan');
        spy.remove(k2, ir2Jan.earnDate);
        assertEq(spy.length(), 7, 'length');
        // _dumpState();
        spy.verifyByKey(true, ir1Jan, false, ir2Jan, true, ir3Jan);
        spy.verifyByKey(true, ir1Feb, false, ir2Feb, true, ir3Feb);
        spy.verifyByKey(true, ir1Mar, true, ir2Mar, true, ir3Mar);

        console2.log('Remove InstRev 2 for Mar');
        spy.remove(k2, ir2Mar.earnDate);
        assertEq(spy.length(), 6, 'length');
        spy.verifyByKey(true, ir1Jan, false, ir2Jan, true, ir3Jan);
        spy.verifyByKey(true, ir1Feb, false, ir2Feb, true, ir3Feb);
        spy.verifyByKey(true, ir1Mar, false, ir2Mar, true, ir3Mar);

        console2.log('Re-Add InstRev 2 for Mar');
        _addInstRev(spy, ir2Mar, true, useStoreParam);
        assertEq(spy.length(), 7, 'length');
        spy.verifyByKey(true, ir1Jan, false, ir2Jan, true, ir3Jan);
        spy.verifyByKey(true, ir1Feb, false, ir2Feb, true, ir3Feb);
        spy.verifyByKey(true, ir1Mar, true, ir2Mar, true, ir3Mar);

        console2.log('Remove all InstRev for k1');
        spy.remove(k1, ir1Jan.earnDate);
        spy.remove(k1, ir1Feb.earnDate);
        spy.remove(k1, ir1Mar.earnDate);
        assertEq(spy.length(), 4, 'length');
        spy.verifyByKey(false, ir1Jan, false, ir2Jan, true, ir3Jan);
        spy.verifyByKey(false, ir1Feb, false, ir2Feb, true, ir3Feb);
        spy.verifyByKey(false, ir1Mar, true, ir2Mar, true, ir3Mar);

        console2.log('Remove all InstRev for Jan');
        spy.remove(k3, ir3Jan.earnDate);
        assertEq(spy.length(), 3, 'length');
        spy.verifyByKey(false, ir1Jan, false, ir2Jan, false, ir3Jan);
        spy.verifyByKey(false, ir1Feb, false, ir2Feb, true, ir3Feb);
        spy.verifyByKey(false, ir1Mar, true, ir2Mar, true, ir3Mar);

        console2.log('Remove all InstRev for Feb');
        spy.remove(k3, ir3Feb.earnDate);
        assertEq(spy.length(), 2, 'length');
        spy.verifyByKey(false, ir1Jan, false, ir2Jan, false, ir3Jan);
        spy.verifyByKey(false, ir1Feb, false, ir2Feb, false, ir3Feb);
        spy.verifyByKey(false, ir1Mar, true, ir2Mar, true, ir3Mar);

        console2.log('Remove all InstRev for Mar');
        spy.remove(k2, ir2Mar.earnDate);
        spy.remove(k3, ir3Mar.earnDate);
        assertEq(spy.length(), 0, 'length');
        spy.verifyByKey(false, ir1Jan, false, ir2Jan, false, ir3Jan);
        spy.verifyByKey(false, ir1Feb, false, ir2Feb, false, ir3Feb);
        spy.verifyByKey(false, ir1Mar, false, ir2Mar, false, ir3Mar);
    }

    function test_IR_getInstRevsLen_store() public {
        _do_getInstRevsLen(true); // storage
    }

    function test_IR_getInstRevsLen_cd() public {
        _do_getInstRevsLen(false); // calldata
    }

    function _do_getInstRevsLen(bool useStoreParam) public {
        IR_Emap_Spy spy = new IR_Emap_Spy(vm);

        console2.log('Add InstRev for Jan (1 inst, 1 date)');
        _addInstRev(spy, ir1Jan, false, useStoreParam);

        console2.log('Add InstRev for Feb (2 insts, 1 date)');
        _addInstRev(spy, ir1Feb, false, useStoreParam);
        _addInstRev(spy, ir2Feb, false, useStoreParam);

        console2.log('Add InstRev for Mar (3 insts, 1 date)');
        _addInstRev(spy, ir1Mar, false, useStoreParam);
        _addInstRev(spy, ir2Mar, false, useStoreParam);
        _addInstRev(spy, ir3Mar, false, useStoreParam);
        assertEq(spy.length(), 6, 'length');

        console2.log('Verify filter with instName=set, earnDate=set');
        assertEq(spy.getInstRevsLen(k1, ed1), 1);
        assertEq(spy.getInstRevsLen(k2, ed1), 0);
        assertEq(spy.getInstRevsLen(k3, ed1), 0);
        assertEq(spy.getInstRevsLen(k1, ed2), 1);
        assertEq(spy.getInstRevsLen(k2, ed2), 1);
        assertEq(spy.getInstRevsLen(k3, ed2), 0);
        assertEq(spy.getInstRevsLen(k1, ed3), 1);
        assertEq(spy.getInstRevsLen(k2, ed3), 1);
        assertEq(spy.getInstRevsLen(k3, ed3), 1);
        assertEq(spy.getInstRevsLen(k4, ed4), 0);

        console2.log('Verify filter with instName=set, earnDate=empty');
        assertEq(spy.getInstRevsLen(k1, edE), 3);
        assertEq(spy.getInstRevsLen(k2, edE), 2);
        assertEq(spy.getInstRevsLen(k3, edE), 1);
        assertEq(spy.getInstRevsLen(k4, edE), 0);

        console2.log('Verify filter with instName=empty, earnDate=set');
        assertEq(spy.getInstRevsLen(kE, ed1), 1);
        assertEq(spy.getInstRevsLen(kE, ed2), 2);
        assertEq(spy.getInstRevsLen(kE, ed3), 3);
        assertEq(spy.getInstRevsLen(kE, ed4), 0);

        console2.log('Verify filter with instName=empty, earnDate=empty');
        assertEq(spy.getInstRevsLen(kE, edE), 6);
    }

    function _verifyItem(IR.InstRev[] memory revs, uint expectLen, IR.InstRev memory ir) internal pure {
        if (expectLen == 0 && revs.length == 1) {
            console.log('InstRev: ', String.toString(revs[0].instNameKey), revs[0].earnDate);
        }
        assertEq(revs.length, expectLen);
        if (expectLen == 0) return;
        assertEq(revs[0].instName, ir.instName, 'instName');
        assertEq(revs[0].earnDate, ir.earnDate, 'earnDate');
    }

    function _verifyArray(IR.InstRev[] memory revs, uint expectLen,
        IR.InstRev memory ir0, IR.InstRev memory ir1, IR.InstRev memory ir2
    ) internal pure {
        assertEq(revs.length, expectLen);

        if (expectLen == 0) return;
        _checkSameInst(revs[0], ir0);

        if (expectLen == 1) return;
        _checkSameInst(revs[1], ir1);

        if (expectLen == 2) return;
        _checkSameInst(revs[2], ir2);
    }

    function _checkSameInst(IR.InstRev memory ir1, IR.InstRev memory ir2) internal pure {
        assertEq(ir1.instName, ir2.instName, 'instName');
        assertEq(ir1.earnDate, ir2.earnDate, 'earnDate');
    }

    function test_IR_getInstRevs() public {
        IR_Emap_Spy spy = new IR_Emap_Spy(vm);

        console2.log('Add InstRev for Jan (1 inst, 1 date)');
        _addInstRev(spy, ir1Jan);

        console2.log('Add InstRev for Feb (2 insts, 1 date)');
        _addInstRev(spy, ir1Feb);
        _addInstRev(spy, ir2Feb);

        console2.log('Add InstRev for Mar (3 insts, 1 date)');
        _addInstRev(spy, ir1Mar);
        _addInstRev(spy, ir2Mar);
        _addInstRev(spy, ir3Mar);
        uint len = 6;
        assertEq(spy.length(), len, 'length');

        IR.InstRev[] memory revs;
        uint iBegin = 0;
        uint count = len;

        console2.log('Verify filter with instName=set, earnDate=set');
        revs = spy.getInstRevs(k1, ed1, iBegin, count); _verifyItem(revs, 1, ir1Jan);
        revs = spy.getInstRevs(k2, ed1, iBegin, count); _verifyItem(revs, 0, irE);
        revs = spy.getInstRevs(k3, ed1, iBegin, count); _verifyItem(revs, 0, irE);

        revs = spy.getInstRevs(k1, ed2, iBegin, count); _verifyItem(revs, 1, ir1Feb);
        revs = spy.getInstRevs(k2, ed2, iBegin, count); _verifyItem(revs, 1, ir2Feb);
        revs = spy.getInstRevs(k3, ed2, iBegin, count); _verifyItem(revs, 0, irE);

        revs = spy.getInstRevs(k1, ed3, iBegin, count); _verifyItem(revs, 1, ir1Mar);
        revs = spy.getInstRevs(k2, ed3, iBegin, count); _verifyItem(revs, 1, ir2Mar);
        revs = spy.getInstRevs(k3, ed3, iBegin, count); _verifyItem(revs, 1, ir3Mar);

        console2.log('Verify filter with instName=set, earnDate=empty');
        revs = spy.getInstRevs(k1, edE, iBegin, count); _verifyArray(revs, 3, ir1Jan, ir1Feb, ir1Mar);
        revs = spy.getInstRevs(k2, edE, iBegin, count); _verifyArray(revs, 2, ir2Feb, ir2Mar, irE);
        revs = spy.getInstRevs(k3, edE, iBegin, count); _verifyArray(revs, 1, ir3Mar, irE, irE);
        revs = spy.getInstRevs(k4, edE, iBegin, count); _verifyArray(revs, 0, irE, irE, irE);

        console2.log('Verify filter with instName=empty, earnDate=set');
        revs = spy.getInstRevs(kE, ed1, iBegin, count); _verifyArray(revs, 1, ir1Jan, irE, irE);
        revs = spy.getInstRevs(kE, ed2, iBegin, count); _verifyArray(revs, 2, ir1Feb, ir2Feb, irE);
        revs = spy.getInstRevs(kE, ed3, iBegin, count); _verifyArray(revs, 3, ir1Mar, ir2Mar, ir3Mar);
        revs = spy.getInstRevs(kE, ed4, iBegin, count); _verifyArray(revs, 0, irE, irE, irE);

        console2.log('Verify filter with instName=empty, earnDate=empty');
        revs = spy.getInstRevs(kE, edE, iBegin, count); _verifyArray(revs, 6, ir1Jan, ir1Feb, ir2Feb);
        _checkSameInst(revs[3], ir1Mar);
        _checkSameInst(revs[4], ir2Mar);
        _checkSameInst(revs[5], ir3Mar);
    }
}
