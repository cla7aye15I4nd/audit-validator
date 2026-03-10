// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/console.sol';
import '../lib/forge-std/src/Test.sol';
import '../lib/forge-std/src/StdError.sol';

import '../contract/v1_0/LibraryEMAP.sol';

contract UtilTest is Test {
    function setUp() public {
    }

    function test_Util_resolveAddr() public pure {
        address miscAddr = address(0xA);
        address custAddr = address(0xB);
        console2.log('No transforms');
        assertEq(Util.resolveAddr(miscAddr, custAddr), miscAddr, 'Misc');
        assertEq(Util.resolveAddr(Util.NativeMint, custAddr), Util.NativeMint, 'NativeMint');
        assertEq(Util.resolveAddr(Util.NativeBurn, custAddr), Util.NativeBurn, 'NativeBurn');

        console2.log('Transforms');
        assertEq(Util.resolveAddr(Util.ContractHeld, custAddr), custAddr, 'Custody');
        assertEq(Util.resolveAddr(Util.ExplicitMint, custAddr), Util.NativeMint, 'ExplicitMint');
        assertEq(Util.resolveAddr(Util.ExplicitBurn, custAddr), Util.NativeBurn, 'ExplicitBurn');
    }

    function test_Util_requireSameArrayLength() public pure {
        assertEq(Util.requireSameArrayLength(2, 2), 2);
    }

    function test_Util_getRangeLen() public pure {
        // Case: full range (count = 0)
        assertEq(Util.getRangeLen(10, 0, 0), 10);     // full range
        assertEq(Util.getRangeLen(10, 3, 0), 7);      // from index 3 to end

        // Case: bounded range (count > 0)
        assertEq(Util.getRangeLen(10, 2, 5), 5);      // in-bounds
        assertEq(Util.getRangeLen(10, 8, 5), 2);      // count overshoots arrayLen
        assertEq(Util.getRangeLen(10, 10, 5), 0);     // iBegin == arrayLen => no range
        assertEq(Util.getRangeLen(10, 11, 5), 0);     // iBegin > arrayLen => invalid

        // Case: count + iBegin exactly hits arrayLen
        assertEq(Util.getRangeLen(10, 6, 4), 4);

        // Edge: empty array
        assertEq(Util.getRangeLen(0, 0, 0), 0);
        assertEq(Util.getRangeLen(0, 0, 5), 0);
        assertEq(Util.getRangeLen(0, 1, 5), 0);
    }
}
