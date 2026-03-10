// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

// LIB_PATHS: CLI is ok with lib paths but vscode ignores the foundry config and other attempts to set them for .sol
// files, consequently relative paths are used to suppress the error/noise in vscode with lib paths like:
// import 'forge-std/Test.sol';
// import '@openzeppelin/contracts/proxy/Clones.sol';
// vs:
// import '../lib/forge-std/src/Test.sol';
// import '../lib/openzeppelin-contracts/contracts/proxy/Clones.sol';

import '../lib/forge-std/src/Test.sol';

import '../contract/v1_0/ICallTracker.sol';

/// @dev Test utilities
// prettier-ignore
library T {

    // ───────────────────────────────────────
    // `concat` overloads to concatenate vars
    // ───────────────────────────────────────

    function concat(string memory a, string memory b) internal pure returns(string memory) {
        return string(abi.encodePacked(a, b));
    }
    function concat(string memory a, string memory b, string memory c) internal pure returns(string memory) {
        // Multiple steps to reduce IR pipeline pressure
        bytes memory p1 = abi.encodePacked(a, b);
        return string(abi.encodePacked(p1, c));
    }
    function concat(string memory a, string memory b, string memory c, string memory d) internal pure
        returns(string memory)
    {
        // Multiple steps to reduce IR pipeline pressure
        bytes memory p1 = abi.encodePacked(a, b);
        bytes memory p2 = abi.encodePacked(c, d);
        return string(abi.encodePacked(p1, p2));
    }
    function concat(string memory a, string memory b, string memory c, string memory d, string memory e)
        internal pure returns(string memory)
    {
        // Multiple steps to reduce IR pipeline pressure
        bytes memory p1 = abi.encodePacked(a, b);
        bytes memory p2 = abi.encodePacked(c, d);
        bytes memory p3 = abi.encodePacked(p1, p2);
        return string(abi.encodePacked(p3, e));
    }

    // ───────────────────────────────────────
    // `checkCall` overloads to check a `CallRes` vs expectations
    // ───────────────────────────────────────

    /// @dev Checks a CallRes vs expected values
    function checkCall(Vm vm, ICallTracker.CallRes memory cr,
        uint rc, uint lrc, uint count, string memory prefix) internal pure
    {
        vm.assertEq(rc, cr.rc, concat(prefix, ' rc'));
        vm.assertEq(lrc, cr.lrc, concat(prefix, ' lrc'));
        vm.assertEq(count, cr.count, concat(prefix, ' count'));
    }

    function checkCall(Vm vm, ICallTracker.CallRes memory cr, uint rc, uint lrc, uint count)
        internal pure
    {
        checkCall(vm, cr, rc, lrc, count, '');
    }

    function checkCall(Vm vm, ICallTracker.CallRes memory cr, ICallTracker.CallRes memory expect,
        string memory prefix) internal pure
    {
        checkCall(vm, cr, expect.rc, expect.lrc, expect.count, prefix);
    }

    function checkCall(Vm vm, ICallTracker.CallRes memory cr, ICallTracker.CallRes memory expect)
        internal pure
    {
        checkCall(vm, cr, expect.rc, expect.lrc, expect.count, '');
    }

    // ───────────────────────────────────────
    // UUID
    // ───────────────────────────────────────

    function checkEqual(Vm vm, UUID a, UUID b, string memory desc) internal pure {
        vm.assertEq(UUID.unwrap(a), UUID.unwrap(b), desc);
    }

    function checkEqual(Vm vm, UUID a, UUID b) internal pure {
        vm.assertEq(UUID.unwrap(a), UUID.unwrap(b), 'uuid');
    }
}
